import CoreLocation
import SwiftUI

struct ActiveRoundView: View {
    let controller: RoundController
    let location: LocationManager
    @Binding var bag: [ClubID]

    @Environment(\.palette) private var palette
    @AppStorage("units") private var unitsRaw: String = Units.yards.rawValue

    @State private var isMarkingShot = false
    @State private var actionError: String?
    @State private var reviewingHole: Hole?
    @State private var showPenaltySheet = false
    @State private var endedRoundForReview: Round?
    @State private var showEndRoundConfirm = false
    @State private var showUndoConfirm = false
    @State private var showCoursePicker = false
    @State private var showHoleGrid = false
    @State private var curatedCourses: [CuratedCourse] = []
    @State private var showMissingShotSheet = false
    /// Snapshot of the missing-shot pin center, computed once when "+ MISS"
    /// is tapped (NOT inside the sheet closure on every view diff). Keeps
    /// the GRDB lookups in `missingShotInitialCenter` off whatever async
    /// context SwiftUI uses for sheet content evaluation — that's what was
    /// tripping the "unsafeForcedSync" concurrency check.
    @State private var pendingMissingShotCenter: CLLocationCoordinate2D?
    @State private var mapFollowMode: Bool = true
    @State private var lyingPulse: Bool = false
    @State private var showScorecard: Bool = false

    var body: some View {
        Group {
            if controller.isActive {
                activeBody
            } else {
                idleBody
            }
        }
        // Push (not sheet) so HoleDetailView can stack on top of Summary, and
        // so the paper-styled Summary fills the screen edge-to-edge. The
        // controller's `mostRecentlyEndedRound` survives across this push so
        // the back navigation doesn't lose the ended round.
        .navigationDestination(isPresented: endedRoundBinding) {
            if let round = endedRoundForReview {
                RoundReviewView(
                    round: round,
                    bag: bag,
                    onResume: { resumeRound(round) },
                    onDismiss: {
                        endedRoundForReview = nil
                        controller.clearMostRecentlyEndedRound()
                    },
                    onDeleted: {
                        // The just-ended round was nuked — clear the in-memory
                        // pointer; the navigation pop is handled by the view
                        // calling `dismiss()` itself.
                        endedRoundForReview = nil
                        controller.clearMostRecentlyEndedRound()
                    }
                )
            }
        }
        .alert("End Round?", isPresented: $showEndRoundConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("End Round", role: .destructive) {
                performEndRound()
            }
        } message: {
            Text("Your round will be saved. You can resume it from the review screen if you change your mind.")
        }
        .alert("Undo last action?", isPresented: $showUndoConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Undo", role: .destructive) {
                performUndoLastAction()
            }
        } message: {
            // Picks whichever of {newest shot, newest penalty} the controller
            // would actually remove (most recent by timestamp) so the confirm
            // text matches the deletion. Falls back to a generic message when
            // the hole is empty — the button is disabled in that state anyway.
            Text(undoConfirmMessage)
        }
        // Mid-round retro-link to a curated course — recovery for "auto-detect
        // missed at start" or "auto-detect picked the wrong course." Mirrors
        // the post-round picker on RoundReviewView, but routes through the
        // controller so the in-memory `curatedCourseId` and `state` refresh
        // and the @Observable consumers (distance-to-green, anchor capture,
        // par auto-fill, holeBearing) pick up the change immediately.
        .sheet(isPresented: $showCoursePicker) {
            CoursePickerSheet(
                courses: curatedCourses,
                current: controller.curatedCourseId,
                onPick: { id in
                    controller.setCuratedCourseId(id)
                    showCoursePicker = false
                },
                onCancel: { showCoursePicker = false }
            )
        }
    }

    private var idleBody: some View {
        HomeView(
            bag: $bag,
            onStartRound: { startRound(startingHole: $0) },
            actionError: actionError
        )
    }

    private var activeBody: some View {
        ZStack {
            ActiveRoundMap(
                shots: controller.currentHoleShots,
                holeHeading: holeBearing,
                green: holeGreenCoordinate,
                followMode: $mapFollowMode
            )
            .ignoresSafeArea()
            // Dim layer so paper cards stay legible on top of bright satellite imagery.
            Color.black.opacity(0.18)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            // Top overlays — hole pill on the left, action stamps on the right.
            VStack(spacing: 8) {
                HStack(alignment: .top, spacing: 8) {
                    holeNav
                    Spacer(minLength: 4)
                    VStack(alignment: .trailing, spacing: 6) {
                        // LYING N is shot-tracking detail — hidden in casual mode.
                        if !controller.isCasualMode {
                            lyingStamp
                        }
                        HStack(spacing: 6) {
                            modeToggleButton
                            cardStampButton
                            endStampButton
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 2)

                HStack(alignment: .top) {
                    distanceCard
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        gpsIndicator
                        if !mapFollowMode {
                            Button {
                                mapFollowMode = true
                            } label: {
                                PaperCard(padding: EdgeInsets(top: 8, leading: 10, bottom: 8, trailing: 10)) {
                                    HStack(spacing: 4) {
                                        Image(systemName: "location.fill")
                                            .font(.system(size: 11, weight: .bold))
                                        Text("FOLLOW")
                                            .font(AppFont.stamp)
                                            .tracking(1.2)
                                    }
                                    .foregroundStyle(palette.ink)
                                }
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 4)

                // Shot strip is shot-tracking detail — hidden in casual mode.
                if !controller.isCasualMode, !controller.currentHoleShots.isEmpty {
                    shotStrip
                        .padding(.horizontal, 12)
                        .padding(.top, 6)
                }

                Spacer()
            }

            // Bottom paper sheet — casual mode swaps the tracking controls for a
            // simple per-hole score stepper.
            VStack {
                Spacer()
                if controller.isCasualMode {
                    casualSheet
                } else {
                    bottomSheet
                }
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .sheet(item: $reviewingHole) { hole in
            HoleReviewSheet(
                hole: hole,
                bag: bag,
                greenCoordinate: GlassesStateMapper.greenCoordinate(
                    courseId: controller.curatedCourseId, holeNumber: hole.holeNumber),
                onConfirm: { par in
                    confirmHole(par: par)
                },
                onCancel: {
                    reviewingHole = nil
                }
            )
        }
        #if DEBUG
        .onAppear {
            if UserDefaults.standard.bool(forKey: "DebugShowHoleGrid") { showHoleGrid = true }
        }
        #endif
        .sheet(isPresented: $showHoleGrid) {
            HoleGridSheet(
                currentHole: controller.currentHole?.holeNumber ?? 1,
                holes: controller.holesForCurrentRound(),
                onPick: { number in
                    controller.goToHole(number)
                    mapFollowMode = true
                    showHoleGrid = false
                },
                onCancel: { showHoleGrid = false }
            )
        }
        .sheet(isPresented: $showPenaltySheet) {
            PenaltySheet(
                onPick: { type in
                    addPenaltyToCurrentHole(type: type)
                },
                onCancel: {
                    showPenaltySheet = false
                }
            )
        }
        .sheet(isPresented: $showScorecard) {
            if let round = controller.currentRound {
                InRoundScorecardSheet(
                    round: round,
                    currentHoleNumber: currentHoleNumber,
                    bag: bag,
                    curatedCourseId: controller.curatedCourseId,
                    onDismiss: { showScorecard = false }
                )
            }
        }
        // Catalog is small and read-only; load eagerly so tapping the hole
        // pill / "Link course" prompt opens the picker without a fetch wait.
        // `onAppear` (not `.task`) deliberately — GRDB's sync dispatch inside
        // `CourseDataRepository.allCourses` trips Swift's concurrency check
        // ("unsafeForcedSync called from Swift Concurrent context") when run
        // inside a `.task` closure. Same pattern RoundReviewView uses for
        // the same call.
        .onAppear {
            curatedCourses = (try? CourseDataRepository.allCourses()) ?? []
        }
        // Field-test 2026-05-22: when the player realizes mid-hole they
        // forgot to tap Log Shot, this sheet lets them retroactively pin
        // the location and pick a club. Appends at the end of the active
        // hole's shots via the controller (keeps `currentHoleShots` in
        // sync). For inserting at an arbitrary position, end the round and
        // use HoleDetailView's full editor.
        .sheet(isPresented: $showMissingShotSheet) {
            // Reads the snapshot taken on the "+ MISS" tap. Fallback (0, 0)
            // would only fire if the sheet were forced open without a tap,
            // which the UI doesn't expose; user pans from there anyway.
            MissingShotPinSheet(
                bag: bag,
                initialCenter: pendingMissingShotCenter ?? CLLocationCoordinate2D(latitude: 0, longitude: 0),
                onAdd: { coord, club in
                    insertMissingShot(at: coord, club: club)
                },
                onCancel: { showMissingShotSheet = false }
            )
        }
        // Glasses-advance retro summary (field-test 2026-05-22): the phone
        // Next button presents `HoleReviewSheet` pre-confirm; the glasses
        // path skipped that and felt like a regression. We now pop the
        // same sheet retroactively in `isRetro` mode — read-only-ish, par
        // editable, "Done" closes it.
        .sheet(item: glassesRetroHoleBinding) { hole in
            HoleReviewSheet(
                hole: hole,
                bag: bag,
                isRetro: true,
                greenCoordinate: GlassesStateMapper.greenCoordinate(
                    courseId: controller.curatedCourseId, holeNumber: hole.holeNumber),
                onConfirm: { par in
                    saveRetroPar(hole: hole, par: par)
                },
                onCancel: {
                    controller.clearMostRecentlyConfirmedHoleFromGlasses()
                }
            )
        }
    }

    // MARK: - Top overlays

    // Tappable so it doubles as a discreet, always-available entry point to
    // the course picker — the recovery path for "auto-detect picked the wrong
    // course" (the just-in-time "Link course" CTA in `distanceCard` only
    // surfaces when nothing is linked at all).
    /// Prev ‹ · hole pill (tap → grid) · › Next — pure navigation chevrons
    /// (step one hole, wrapping) flanking the tappable hole number.
    private var holeNav: some View {
        HStack(spacing: 4) {
            holeStepChevron("‹") { controller.stepHole(by: -1); mapFollowMode = true }
            holePill
            holeStepChevron("›") { controller.stepHole(by: 1); mapFollowMode = true }
        }
    }

    private func holeStepChevron(_ glyph: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            PaperCard(padding: EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9)) {
                Text(glyph)
                    .font(.custom(AppFont.serifName, size: 20).weight(.bold))
                    .foregroundStyle(palette.ink)
            }
        }
        .buttonStyle(.plain)
    }

    private var holePill: some View {
        Button {
            showHoleGrid = true
        } label: {
            PaperCard(padding: EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)) {
                VStack(spacing: 2) {
                    Text("Hole \(currentHoleNumber)")
                        .font(.custom(AppFont.serifName, size: 17).italic().weight(.bold))
                        .foregroundStyle(palette.ink)
                    Text(holePillCaption)
                        .font(.custom(AppFont.monoName, size: 9).weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(palette.ink2)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private var cardStampButton: some View {
        Button {
            showScorecard = true
        } label: {
            PaperCard(padding: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)) {
                Text("CARD")
                    .font(AppFont.stamp)
                    .tracking(1.2)
                    .foregroundStyle(palette.ink)
            }
        }
        .buttonStyle(.plain)
    }

    private var gpsIndicator: some View {
        PaperCard(padding: EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 10)) {
            HStack(spacing: 5) {
                Circle()
                    .fill(gpsColor)
                    .frame(width: 6, height: 6)
                Text(gpsAccuracyText)
                    .font(.custom(AppFont.monoName, size: 9).weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(palette.ink2)
                    .tabularNumerals()
            }
        }
    }

    /// Compact list of clubs hit on this hole so far. Each shot is a small
    /// pill — `1 Dr`, `2 7i`, `3 PW` — so the player can see what they've
    /// played without needing to read the map.
    private var shotStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(controller.currentHoleShots, id: \.id) { shot in
                    PaperCard(padding: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)) {
                        HStack(spacing: 6) {
                            Text("\(shot.sequenceNumber)")
                                .font(.custom(AppFont.monoName, size: 10).weight(.bold))
                                .foregroundStyle(palette.ink3)
                                .tabularNumerals()
                            Text(shot.club?.shortName ?? "—")
                                .font(.custom(AppFont.serifName, size: 13).italic().weight(.bold))
                                .foregroundStyle(palette.ink)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var holePillCaption: String {
        let parPart: String = {
            if let par = controller.currentHole?.par { return "PAR \(par)" }
            return "PAR —"
        }()
        if let yds = curatedYardsForCurrentHole {
            let f = units.format(yards: yds)
            return "\(parPart) · \(f.value) \(f.unit.uppercased())"
        }
        return parPart
    }

    // Stroke breakdown: shots logged + penalty strokes + their sum. Field-
    // test 2026-05-22 found a single "LYING N" rolled up too much — users
    // wanted to see the components separately. Labels in muted ink, values
    // in ink (shots) / flag (pen, when > 0) / flag (total) so the eye lands
    // on what changed.
    private var lyingStamp: some View {
        let shots = controller.shotsInCurrentHole
        let pen = controller.currentHolePenaltyStrokes
        let total = shots + pen
        return PaperCard(padding: EdgeInsets(top: 6, leading: 10, bottom: 6, trailing: 10)) {
            (
                Text("SHOTS ").foregroundStyle(palette.ink3)
                + Text("\(shots)").foregroundStyle(palette.ink)
                + Text(" · PEN ").foregroundStyle(palette.ink3)
                + Text("\(pen)").foregroundStyle(pen > 0 ? palette.flag : palette.ink3)
                + Text(" · TOT ").foregroundStyle(palette.ink3)
                + Text("\(total)").foregroundStyle(palette.flag)
            )
            .font(AppFont.stamp)
            .tracking(1.2)
            .scaleEffect(lyingPulse ? 1.08 : 1.0)
        }
    }

    private var endStampButton: some View {
        Button {
            showEndRoundConfirm = true
        } label: {
            PaperCard(padding: EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8)) {
                Text("END")
                    .font(AppFont.stamp)
                    .tracking(1.2)
                    .foregroundStyle(palette.flag)
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Distance card

    private var distanceCard: some View {
        PaperCard(padding: EdgeInsets(top: 12, leading: 16, bottom: 10, trailing: 16)) {
            VStack(alignment: .leading, spacing: 6) {
                Text("TO PIN")
                    .font(.custom(AppFont.monoName, size: 9).weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(palette.ink2)

                if let yards = distanceToGreenYards {
                    let f = units.format(yards: yards)
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text("\(f.value)")
                            .font(AppFont.distanceHero)
                            .tracking(-2.5)
                            .foregroundStyle(palette.ink)
                            .tabularNumerals()
                        Text(f.unit)
                            .font(.custom(AppFont.monoName, size: 14).weight(.bold))
                            .foregroundStyle(palette.ink2)
                    }

                    Rectangle().fill(palette.rule).frame(height: 1)
                        .padding(.vertical, 4)

                    HStack(spacing: 18) {
                        VStack(alignment: .leading, spacing: 1) {
                            Text("FRONT")
                                .font(.custom(AppFont.monoName, size: 8).weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(palette.ink3)
                            Text("\(units.format(yards: max(0, yards - 14)).value)")
                                .font(.custom(AppFont.monoName, size: 14).weight(.bold))
                                .foregroundStyle(palette.ink)
                                .tabularNumerals()
                        }
                        VStack(alignment: .leading, spacing: 1) {
                            Text("BACK")
                                .font(.custom(AppFont.monoName, size: 8).weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(palette.ink3)
                            Text("\(units.format(yards: yards + 14).value)")
                                .font(.custom(AppFont.monoName, size: 14).weight(.bold))
                                .foregroundStyle(palette.ink)
                                .tabularNumerals()
                        }
                    }
                } else if controller.curatedCourseId == nil {
                    // No course linked yet — distance-to-green is gated on
                    // `curatedCourseId`, so surface the picker right where the
                    // missing reading would have been. Recovery path for
                    // "auto-detect missed (or had no GPS) at startRound."
                    Button {
                        showCoursePicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Stamp(text: "Link course", color: palette.flag)
                            Text("›")
                                .font(.custom(AppFont.serifName, size: 14).italic().weight(.bold))
                                .foregroundStyle(palette.flag)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                } else {
                    // Course is linked, but distance still isn't computable —
                    // green anchor is missing (no curated anchor + nothing
                    // locally captured yet) or GPS has no fix.
                    Stamp(text: "No anchor", color: palette.ink3)
                        .padding(.top, 4)
                }

                // Always-available re-link/unlink. The picker used to appear ONLY
                // when nothing was linked, so a wrong auto-detect (or a multi-course
                // facility where it grabbed the wrong nine) couldn't be fixed until
                // the round ended. Tap to change the course or remove the link
                // (the picker's "No course" choice unlinks).
                if let id = controller.curatedCourseId {
                    Rectangle().fill(palette.rule).frame(height: 1).padding(.top, 6)
                    Button {
                        showCoursePicker = true
                    } label: {
                        HStack(spacing: 6) {
                            Text(curatedCourses.first { $0.id == id }?.name ?? "Course linked")
                                .font(.custom(AppFont.monoName, size: 9).weight(.bold))
                                .tracking(0.6)
                                .foregroundStyle(palette.ink3)
                                .lineLimit(1)
                            Spacer(minLength: 4)
                            Text("CHANGE ›")
                                .font(.custom(AppFont.monoName, size: 9).weight(.bold))
                                .tracking(1.0)
                                .foregroundStyle(palette.flag)
                        }
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
        }
    }

    // MARK: - Bottom sheet

    private var bottomSheet: some View {
        VStack(spacing: 0) {
            // Drag handle
            Rectangle().fill(palette.rule)
                .frame(width: 40, height: 3)
                .clipShape(Capsule())
                .padding(.top, 8)
                .padding(.bottom, 12)

            // Selected club row — penalty stamp on the right (small, secondary).
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SELECTED")
                        .font(AppFont.stamp)
                        .tracking(1.4)
                        .foregroundStyle(palette.ink3)
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(controller.currentClub?.longName ?? "—")
                            .font(.custom(AppFont.serifName, size: 22).italic().weight(.bold))
                            .foregroundStyle(palette.ink)
                        if let club = controller.currentClub,
                           let avg = ClubAverages.shared.average(for: club) {
                            let f = units.format(yards: avg)
                            Text("avg \(f.value) \(f.unit)")
                                .font(.custom(AppFont.monoName, size: 12).weight(.bold))
                                .foregroundStyle(palette.ink3)
                        }
                    }
                }
                Spacer()
                HStack(spacing: 8) {
                    missingShotStampButton
                    penaltyStampButton
                }
            }
            .padding(.horizontal, 20)

            // Horizontal-scroll club row
            clubRow
                .padding(.vertical, 6)
                .overlay(alignment: .top) {
                    Rectangle().fill(palette.ink).frame(height: 1.5)
                }
                .overlay(alignment: .bottom) {
                    Rectangle().fill(palette.ink).frame(height: 1)
                }
                .padding(.top, 14)

            // Action row: Undo · Log shot (primary) · +Putt · Next hole.
            HStack(spacing: 10) {
                actionIconButton(systemName: "arrow.uturn.backward") {
                    showUndoConfirm = true
                }
                .disabled(controller.currentHoleShots.isEmpty && controller.currentHolePenalties.isEmpty)

                logShotCTA

                puttButton

                nextHoleButton
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)

            errorBanner
                .padding(.horizontal, 20)
                .padding(.top, 12)
        }
        .padding(.bottom, 32)
        .background(
            ZStack {
                palette.paper
                // Subtle cross-hatch on the sheet too.
                Canvas { ctx, size in
                    let opacity = 0.018
                    let stroke = Color(red: palette.inkRgb.r, green: palette.inkRgb.g, blue: palette.inkRgb.b, opacity: opacity)
                    let spacing: CGFloat = 12
                    var x: CGFloat = -size.height
                    while x < size.width + size.height {
                        var path = Path()
                        path.move(to: CGPoint(x: x, y: 0))
                        path.addLine(to: CGPoint(x: x + size.height, y: size.height))
                        ctx.stroke(path, with: .color(stroke), lineWidth: 1)
                        x += spacing
                    }
                }
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.5), radius: 40, x: 0, y: -8)
    }

    // MARK: - Casual mode (GPS + simple score)

    private var modeToggleButton: some View {
        Button {
            controller.setCasualMode(!controller.isCasualMode)
        } label: {
            Text(controller.isCasualMode ? "○ CASUAL" : "● TRACKING")
                .font(AppFont.stamp)
                .tracking(1.2)
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(palette.ink, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var casualSheet: some View {
        let score = controller.currentHoleShots.count
        let par = controller.currentHole?.par
        return VStack(spacing: 0) {
            Rectangle().fill(palette.rule)
                .frame(width: 40, height: 3)
                .clipShape(Capsule())
                .padding(.top, 8)
                .padding(.bottom, 16)

            Text("STROKES THIS HOLE")
                .font(AppFont.stamp).tracking(1.4)
                .foregroundStyle(palette.ink3)

            HStack(spacing: 28) {
                casualStepButton(systemName: "minus", action: decCasual)
                    .disabled(score == 0)
                    .opacity(score == 0 ? 0.3 : 1)
                VStack(spacing: 0) {
                    Text("\(score)")
                        .font(.custom(AppFont.serifName, size: 60).weight(.bold))
                        .foregroundStyle(palette.ink)
                        .contentTransition(.numericText())
                    Text(par.map { "PAR \($0)" } ?? "PAR —")
                        .font(AppFont.stamp).tracking(1.4)
                        .foregroundStyle(palette.ink3)
                }
                .frame(minWidth: 96)
                casualStepButton(systemName: "plus", action: incCasual)
            }
            .padding(.top, 10)

            errorBanner
                .padding(.horizontal, 20)
                .padding(.top, 12)

            casualNextButton
                .padding(.horizontal, 20)
                .padding(.top, 16)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 40)
        .background(palette.paper)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .shadow(color: Color.black.opacity(0.5), radius: 40, x: 0, y: -8)
    }

    // Casual hole-out: reconstruct the strokes from the GPS track (Path B), then
    // open the same review sheet (card + draggable pins) to confirm/adjust.
    private var casualNextButton: some View {
        Button {
            controller.placeCurrentHoleFromTrack()
            reviewingHole = controller.currentHole
        } label: {
            HStack(spacing: 6) {
                Text("Next")
                    .font(.custom(AppFont.serifName, size: 18).italic().weight(.regular))
                Text("›")
                    .font(.custom(AppFont.serifName, size: 20).weight(.bold))
            }
            .foregroundStyle(palette.paper)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(palette.ink)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: Color.black.opacity(0.25), radius: 0, x: 0, y: 3)
        }
        .buttonStyle(.plain)
    }

    private func casualStepButton(systemName: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(palette.ink)
                .frame(width: 64, height: 64)
                .overlay(
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(palette.ink, lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func incCasual() {
        actionError = nil
        Task {
            do { try await controller.addCasualStroke() }
            catch { actionError = "Failed: \(error.localizedDescription)" }
        }
    }

    private func decCasual() {
        actionError = nil
        do { try controller.undoLastAction() }
        catch { actionError = "Failed: \(error.localizedDescription)" }
    }

    private var penaltyStampButton: some View {
        Button {
            showPenaltySheet = true
        } label: {
            Text("⚠ PENALTY")
                .font(AppFont.stamp)
                .tracking(1.2)
                .foregroundStyle(palette.flag)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(palette.flag, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var missingShotStampButton: some View {
        Button {
            // Snapshot the center NOW (MainActor, on user tap) so the sheet
            // never has to recompute it from a SwiftUI diff context.
            pendingMissingShotCenter = missingShotInitialCenter
            showMissingShotSheet = true
        } label: {
            Text("+ MISS")
                .font(AppFont.stamp)
                .tracking(1.2)
                .foregroundStyle(palette.ink)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(palette.ink, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }

    private var nextHoleButton: some View {
        Button {
            reviewingHole = controller.currentHole
        } label: {
            HStack(spacing: 3) {
                Text("Next")
                    .font(.custom(AppFont.serifName, size: 14).italic().weight(.regular))
                    .foregroundStyle(palette.ink)
                Text("›")
                    .font(.custom(AppFont.serifName, size: 18).weight(.bold))
                    .foregroundStyle(palette.ink)
            }
            .frame(width: 76, height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(palette.ink, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
    }

    private var clubRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 0) {
                ForEach(bag) { club in
                    clubCell(club)
                }
            }
        }
        .mask(
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black, location: 0.06),
                    .init(color: .black, location: 0.94),
                    .init(color: .clear, location: 1.0),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private func clubCell(_ club: ClubID) -> some View {
        let isSelected = controller.currentClub == club
        let avg = ClubAverages.shared.average(for: club)
        return Button {
            controller.setCurrentClub(club)
        } label: {
            VStack(spacing: 1) {
                Text(club.shortName)
                    .font(.custom(AppFont.serifName, size: 16).italic().weight(.bold))
                    .foregroundStyle(isSelected ? palette.paper : palette.ink)
                if let avg, avg > 0 {
                    let f = units.format(yards: avg)
                    Text("\(f.value)")
                        .font(.custom(AppFont.monoName, size: 9).weight(.bold))
                        .foregroundStyle(isSelected ? palette.paper.opacity(0.7) : palette.ink3)
                        .tabularNumerals()
                } else {
                    Text(" ")
                        .font(.custom(AppFont.monoName, size: 9).weight(.bold))
                }
            }
            .frame(minWidth: 50)
            .padding(.horizontal, 4)
            .padding(.vertical, 8)
            .background(isSelected ? palette.ink : Color.clear)
            .overlay(alignment: .trailing) {
                Rectangle().fill(palette.rule).frame(width: 1)
            }
        }
        .buttonStyle(.plain)
    }

    private func actionIconButton(systemName: String, iconColor: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(iconColor ?? palette.ink)
                .frame(width: 50, height: 50)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(palette.ink, lineWidth: 1.2)
                )
        }
        .buttonStyle(.plain)
    }

    private var puttButton: some View {
        Button(action: markPutt) {
            VStack(spacing: 1) {
                Image(systemName: "circle.fill").font(.system(size: 9, weight: .bold))
                Text("PUTT").font(AppFont.stamp).tracking(0.8)
            }
            .foregroundStyle(palette.ink)
            .frame(width: 58, height: 50)
            .overlay(
                RoundedRectangle(cornerRadius: 2)
                    .stroke(palette.ink, lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
        .disabled(isMarkingShot)
    }
    private var logShotCTA: some View {
        Button(action: markShot) {
            HStack(spacing: 4) {
                if isMarkingShot {
                    ProgressView()
                        .tint(palette.paper)
                } else {
                    Text("Log")
                        .font(.custom(AppFont.serifName, size: 20).italic().weight(.regular))
                        .foregroundStyle(palette.paper.opacity(0.85))
                    Text("shot")
                        .font(.custom(AppFont.serifName, size: 20).weight(.bold))
                        .foregroundStyle(palette.paper)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 50)
            .background(palette.flag)
            .clipShape(RoundedRectangle(cornerRadius: 4))
            .shadow(color: Color.black.opacity(0.25), radius: 0, x: 0, y: 3)
        }
        .buttonStyle(.plain)
        .disabled(isMarkingShot)
    }

    @ViewBuilder
    private var errorBanner: some View {
        if let actionError {
            Text(actionError)
                .font(AppFont.micro)
                .tracking(1.2)
                .foregroundStyle(palette.red)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    // MARK: - GPS helpers (compact paper-card indicator)

    private var gpsColor: Color {
        if isFixStale { return palette.ink3 }
        switch location.fixQuality {
        case .none:       return palette.ink3
        case .degraded:   return palette.flag
        case .acceptable: return palette.ink2
        case .good:       return palette.ink
        }
    }

    private var isFixStale: Bool {
        guard let timestamp = location.latestLocation?.timestamp else { return true }
        return Date().timeIntervalSince(timestamp) > 10
    }

    private var gpsAccuracyText: String {
        guard let loc = location.latestLocation, loc.horizontalAccuracy > 0 else {
            return "GPS NO FIX"
        }
        if isFixStale { return "GPS STALE" }
        return "GPS ±\(Int(loc.horizontalAccuracy.rounded()))M"
    }

    // MARK: - Computed accessors

    private var units: Units { Units(rawValue: unitsRaw) ?? .yards }

    private var currentHoleNumber: Int {
        controller.currentHole?.holeNumber ?? 1
    }

    /// Yards reading from the curated course (if linked) for the current hole.
    private var curatedYardsForCurrentHole: Int? {
        guard let courseId = controller.curatedCourseId,
              let course = try? CourseDataRepository.course(byId: courseId),
              let h = course.holes.first(where: { $0.number == currentHoleNumber }),
              let y = h.yards
        else { return nil }
        return Int(y.rounded())
    }

    /// Map heading for the current hole — bearing from tee → green so the
    /// hitting direction faces "up". Resolution order:
    ///   1. Tee anchor (local override > curated) → green anchor
    ///   2. First shot → green anchor
    ///   3. First shot → last shot (when there are at least two shots)
    /// Returns nil when there's nothing to orient by; the map falls back to
    /// north up.
    private var holeBearing: Double? {
        let shots = controller.currentHoleShots
        let firstShotCoord = shots.first.flatMap(coord)
        let lastShotCoord = shots.count >= 2 ? shots.last.flatMap(coord) : nil

        var tee: CLLocationCoordinate2D?
        var green: CLLocationCoordinate2D?

        if let courseId = controller.curatedCourseId,
           let hole = controller.currentHole {
            let local = try? LocalAnchorRepository.anchor(courseId: courseId, holeNumber: hole.holeNumber)
            let curated = (try? CourseDataRepository.course(byId: courseId))?
                .holes.first(where: { $0.number == hole.holeNumber })
            if let p = local?.tee ?? curated?.teeAnchor {
                tee = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)
            }
            if let p = local?.green ?? curated?.greenAnchor {
                green = CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)
            }
        }

        let start = tee ?? firstShotCoord
        let end = green ?? lastShotCoord
        guard let start, let end else { return nil }
        guard Distance.meters(from: start, to: end) > 5 else { return nil }
        return Distance.bearingDegrees(from: start, to: end)
    }

    private func coord(of shot: Shot) -> CLLocationCoordinate2D? {
        guard let lat = shot.latitude, let lng = shot.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    /// Green anchor for the current hole (local capture wins over curated), used
    /// by the map to frame ball → green. Nil for non-curated rounds.
    private var holeGreenCoordinate: CLLocationCoordinate2D? {
        guard let hole = controller.currentHole else { return nil }
        return GlassesStateMapper.greenCoordinate(courseId: controller.curatedCourseId, holeNumber: hole.holeNumber)
    }

    /// Distance-to-green for the current hole. Requires a curated course link
    /// and a green anchor (curated or locally captured). Returns yards.
    ///
    /// Measured from the LIVE GPS fix — the same coordinate the watch
    /// (`WatchStatePublisher`) and glasses (`GlassesStateMapper`) use — so all
    /// three surfaces always show the same number. (It used to measure from the
    /// last logged shot's position, which froze while walking up to the ball and
    /// disagreed with the glasses — field test 2026-06-18.)
    private var distanceToGreenYards: Int? {
        guard let courseId = controller.curatedCourseId,
              let hole = controller.currentHole,
              let loc = location.latestLocation, loc.horizontalAccuracy > 0
        else { return nil }
        return GlassesStateMapper.yardsToGreen(
            from: loc.coordinate, courseId: courseId, holeNumber: hole.holeNumber)
    }

    /// `navigationDestination(isPresented:)` wants a `Binding<Bool>`. Bridge
    /// from the `Round?` optional so any non-nil round triggers the push,
    /// and dismissing the destination clears the optional.
    private var endedRoundBinding: Binding<Bool> {
        Binding(
            get: { endedRoundForReview != nil },
            set: { isShown in
                if !isShown {
                    endedRoundForReview = nil
                    controller.clearMostRecentlyEndedRound()
                }
            }
        )
    }

    private func startRound(startingHole: Int) {
        actionError = nil
        do {
            try controller.startRound(startingHole: startingHole)
            mapFollowMode = true
        } catch {
            actionError = "Couldn't start round: \(error.localizedDescription)"
        }
    }

    private func performEndRound() {
        actionError = nil
        let toReview = controller.currentRound
        do {
            try controller.endRound()
            endedRoundForReview = toReview
        } catch {
            actionError = "Couldn't end round: \(error.localizedDescription)"
        }
    }

    private func performUndoLastAction() {
        actionError = nil
        do {
            try controller.undoLastAction()
        } catch {
            actionError = "Couldn't undo: \(error.localizedDescription)"
        }
    }

    /// Mirrors `RoundController.undoLastAction`'s tiebreak (newer timestamp
    /// wins) so the confirm sentence names exactly what will be deleted.
    private var undoConfirmMessage: String {
        let lastShot = controller.currentHoleShots.last
        let lastPenalty = controller.currentHolePenalties.last
        switch (lastShot, lastPenalty) {
        case (nil, nil):
            return "Removes the most recent shot or penalty."
        case let (shot?, nil):
            let label = shot.club?.longName ?? "no club"
            return "Removes Shot \(shot.sequenceNumber) (\(label)) from this hole."
        case let (nil, penalty?):
            return "Removes the \(penalty.type.displayName) penalty from this hole."
        case let (shot?, penalty?):
            if penalty.timestamp >= shot.timestamp {
                return "Removes the \(penalty.type.displayName) penalty from this hole."
            }
            let label = shot.club?.longName ?? "no club"
            return "Removes Shot \(shot.sequenceNumber) (\(label)) from this hole."
        }
    }

    private func resumeRound(_ round: Round) {
        actionError = nil
        do {
            try controller.resumeRound(round)
            endedRoundForReview = nil
            mapFollowMode = true
        } catch {
            actionError = "Couldn't resume: \(error.localizedDescription)"
        }
    }

    private func markPutt() {
        actionError = nil
        Task {
            isMarkingShot = true
            do {
                try await controller.markPutt()
            } catch {
                actionError = "Putt failed: \(error.localizedDescription)"
            }
            isMarkingShot = false
        }
    }
    private func markShot() {
        actionError = nil
        Task {
            isMarkingShot = true
            var succeeded = false
            do {
                try await controller.markShot()
                succeeded = true
            } catch {
                actionError = "Mark failed: \(error.localizedDescription)"
            }
            // Release the button immediately so the user isn't stuck waiting
            // on the animation. The pulse runs as fire-and-forget below.
            isMarkingShot = false
            guard succeeded else { return }
            withAnimation(.spring(response: 0.18, dampingFraction: 0.5)) {
                lyingPulse = true
            }
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 180_000_000)
                withAnimation(.easeOut(duration: 0.12)) {
                    lyingPulse = false
                }
            }
        }
    }

    private func confirmHole(par: Int?) {
        actionError = nil
        do {
            try controller.confirmHoleAndAdvance(par: par)
            reviewingHole = nil
        } catch {
            actionError = "Couldn't advance hole: \(error.localizedDescription)"
        }
    }

    /// Best starting map center for the missing-shot pin. Preferred order:
    /// live GPS fix → last logged shot's coordinate → curated/local green
    /// anchor for the current hole → curated tee anchor → (0, 0). The user
    /// pans from there, so being roughly on the hole is what matters.
    private var missingShotInitialCenter: CLLocationCoordinate2D {
        if let loc = location.latestLocation, loc.horizontalAccuracy > 0 {
            return loc.coordinate
        }
        if let last = controller.currentHoleShots.last,
           let lat = last.latitude, let lng = last.longitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        if let courseId = controller.curatedCourseId,
           let hole = controller.currentHole {
            let local = try? LocalAnchorRepository.anchor(courseId: courseId, holeNumber: hole.holeNumber)
            let curated = (try? CourseDataRepository.course(byId: courseId))?
                .holes.first(where: { $0.number == hole.holeNumber })
            if let p = local?.green ?? curated?.greenAnchor {
                return CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)
            }
            if let p = local?.tee ?? curated?.teeAnchor {
                return CLLocationCoordinate2D(latitude: p.lat, longitude: p.lng)
            }
        }
        return CLLocationCoordinate2D(latitude: 0, longitude: 0)
    }

    /// Bridges `controller.mostRecentlyConfirmedHoleFromGlasses` (a stored
    /// `Hole?`) into the `Binding<Hole?>` `.sheet(item:)` needs. Set-to-nil
    /// (which the sheet does on swipe-down) clears the controller pointer.
    private var glassesRetroHoleBinding: Binding<Hole?> {
        Binding(
            get: { controller.mostRecentlyConfirmedHoleFromGlasses },
            set: { newValue in
                if newValue == nil {
                    controller.clearMostRecentlyConfirmedHoleFromGlasses()
                }
            }
        )
    }

    /// "Done" tap in the retro summary sheet — saves par to the already-
    /// confirmed hole (deliberately bypassing `controller.setPar` since
    /// the hole is no longer the live one; `HoleRepository.setPar` is the
    /// right primitive). Clears the retro pointer so the sheet dismisses.
    private func saveRetroPar(hole: Hole, par: Int?) {
        do {
            try HoleRepository.setPar(holeID: hole.id, par: par)
        } catch {
            actionError = "Couldn't update par: \(error.localizedDescription)"
        }
        controller.clearMostRecentlyConfirmedHoleFromGlasses()
    }

    private func insertMissingShot(at coord: CLLocationCoordinate2D, club: ClubID?) {
        actionError = nil
        do {
            try controller.insertMissingShot(at: coord, club: club)
            showMissingShotSheet = false
        } catch {
            actionError = "Add missing shot failed: \(error.localizedDescription)"
        }
    }

    private func addPenaltyToCurrentHole(type: PenaltyType) {
        actionError = nil
        do {
            // Routes through the controller so `currentHolePenalties`
            // refreshes — the lie stamp and Undo enable state read it.
            try controller.addPenaltyToCurrentHole(type: type)
            showPenaltySheet = false
        } catch {
            actionError = "Add penalty failed: \(error.localizedDescription)"
        }
    }
}
