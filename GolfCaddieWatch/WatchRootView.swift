import SwiftUI
import WatchKit

/// Top level: a Start screen until the detection session is running, then the
/// three pages (Yardage / Strokes / Score) with the DetectCard overlay — or,
/// wrist-down, the yardage-only GlanceScreen.
/// Round data is read from the phone (WatchSession.phoneState); detection +
/// session control live on LiveSessionController; the yardage is computed on the
/// wrist (WatchCaddie) with the phone's pushed value as the fallback.
struct WatchRootView: View {
    @EnvironmentObject private var controller: LiveSessionController

    var body: some View {
        ZStack {
            WT.bg.ignoresSafeArea()
            if controller.running {
                WatchPlayView()
            } else {
                WatchStartScreen()
            }
            if controller.pending != nil {
                DetectCard()
            }
        }
        .foregroundStyle(WT.ink)
        #if DEBUG
        .onAppear { WatchPreviewDebug.apply(controller: controller) }
        #endif
    }
}

// MARK: - Shared header

private struct WatchHeader<Left: View>: View {
    @ViewBuilder var left: Left
    var body: some View {
        HStack {
            left
            Spacer(minLength: 0)
        }
    }
}

private struct GpsDot: View {
    let hasFix: Bool
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(hasFix ? WT.green : WT.ink3)
                .frame(width: 7, height: 7)
                .shadow(color: hasFix ? WT.green : .clear, radius: 3)
            Text(hasFix ? "GPS" : "NO GPS")
                .font(WT.mono(11)).foregroundStyle(WT.ink2)
        }
    }
}

// MARK: - Start

private struct WatchStartScreen: View {
    @EnvironmentObject private var controller: LiveSessionController
    @ObservedObject private var session = WatchSession.shared

    var body: some View {
        let s = session.phoneState
        VStack(alignment: .leading, spacing: 0) {
            WatchHeader(left: { GpsDot(hasFix: s.distanceToGreenYards != nil) })
            Spacer()
            Text(s.isActive ? "ROUND IN PROGRESS" : "NO ACTIVE ROUND")
                .font(WT.mono(11)).tracking(2).foregroundStyle(WT.ink3)
            Text(s.courseName ?? "Golf Caddie")
                .font(WT.serif(WT.s(26))).foregroundStyle(WT.ink)
                .lineLimit(2).minimumScaleFactor(0.6)
                .padding(.top, 4)
            HStack(spacing: 18) {
                stat("HOLE", s.isActive ? "\(s.holeNumber)" : "–")
                stat("PAR", s.par.map(String.init) ?? "–")
                stat("SHOTS", "\(s.holeShotCount)")
            }
            .padding(.top, 14)
            Spacer()
            Button {
                Task { await controller.start() }
            } label: {
                Text(s.isActive ? "Resume Hole \(s.holeNumber)" : "Start Tracking")
                    .font(WT.serif(18)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WT.accent)
            if !s.isActive {
                Text("WATCH ONLY · YARDAGE + WORKOUT")
                    .font(WT.mono(9)).tracking(1).foregroundStyle(WT.ink3)
                    .frame(maxWidth: .infinity).padding(.top, 3)
            }
            if let err = controller.lastError {
                Text(err).font(WT.mono(10)).foregroundStyle(.red).padding(.top, 4)
            }
            TelemetryToggle(telemetry: controller.telemetry)
            #if DEBUG
            // Debug footer: validation mode (raw logging + MARK) for M8 testing (B20).
            HStack(spacing: 8) {
                Button { controller.validationMode.toggle() } label: {
                    Text("VALIDATION \(controller.validationMode ? "ON" : "OFF")")
                        .font(WT.mono(9)).tracking(0.8)
                }
                .buttonStyle(.plain)
                .foregroundStyle(controller.validationMode ? WT.accent : WT.ink3)
                Spacer()
                if session.outstanding > 0 {
                    Button("RESEND \(session.outstanding)") { session.resendAll() }
                        .font(WT.mono(9)).buttonStyle(.plain).foregroundStyle(WT.ink2)
                }
            }
            .padding(.top, 6)
            #endif
        }
        .padding(.horizontal, 4)
    }

    private func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(WT.mono(10)).tracking(1.2).foregroundStyle(WT.ink3)
            Text(value).font(WT.serif(WT.s(28))).foregroundStyle(WT.ink)
        }
    }
}

/// Standalone-spike GPS/battery log (step 6): on/off, plus how many finished
/// files are still waiting for confirmed delivery to the phone.
private struct TelemetryToggle: View {
    @ObservedObject var telemetry: WatchTelemetryRecorder
    @ObservedObject private var session = WatchSession.shared

    var body: some View {
        HStack(spacing: 8) {
            Button { telemetry.enabled.toggle() } label: {
                Text("GPS LOG \(telemetry.enabled ? "ON" : "OFF")").font(WT.mono(9)).tracking(0.8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(telemetry.enabled ? WT.accent : WT.ink3)
            Spacer()
            if session.telemetryPending > 0 {
                Text("\(session.telemetryPending) TO SEND").font(WT.mono(9)).foregroundStyle(WT.ink2)
            }
        }
        .padding(.top, 4)
    }
}

// MARK: - Play (paged)

private struct WatchPlayView: View {
    @EnvironmentObject private var controller: LiveSessionController
    @ObservedObject private var session = WatchSession.shared
    @Environment(\.isLuminanceReduced) private var luminanceReduced
    @State private var page: Int = {
        #if DEBUG
        return WatchPreviewDebug.initialPage
        #else
        return 0
        #endif
    }()

    private var dimmed: Bool {
        #if DEBUG
        if WatchPreviewDebug.dim { return true }
        #endif
        return luminanceReduced
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            WT.bg.ignoresSafeArea() // keeps the ZStack (and so the status corner) full-screen in both modes
            if dimmed {
                // Wrist down: whatever page was open, the glance is the yardage.
                GlanceScreen()
            } else {
                // Full-screen pages with the system page dots — the old
                // VStack(meter / TabView / dots) squeezed the pages into the
                // middle of the Ultra's screen and clipped the action row.
                TabView(selection: $page) {
                    YardageScreen().tag(0)
                    StrokesScreen().tag(1)
                    ScoreScreen().tag(2)
                }
                .tabViewStyle(.page)
            }
            #if DEBUG
            // Validation ground-truth MARK (M8 only) — top-right corner tap (B20).
            if controller.validationMode, !dimmed {
                Button { controller.mark() } label: {
                    Text("MARK").font(WT.mono(10)).padding(.horizontal, 8).padding(.vertical, 4)
                        .background(WT.accent.opacity(0.85), in: Capsule())
                        .foregroundStyle(WT.onAccent)
                }
                .buttonStyle(.plain)
                .padding(.trailing, 4)
            }
            #endif
        }
        // Sensing + delivery status live in the clock row (top-left), not in a
        // row of their own.
        .overlay(alignment: .topLeading) {
            StatusCorner(dimmed: dimmed)
                .padding(.leading, WT.s(18))
                .padding(.top, WT.s(24)) // level with the clock
                .ignoresSafeArea(edges: .top)
        }
    }
}

/// Clock-row status: the "watch is sensing" dot (brightens toward a ball-strike
/// — replaces the full-width LISTENING meter) and, only while something is
/// queued for an unreachable phone, the delivery backlog count (B4).
private struct StatusCorner: View {
    let dimmed: Bool
    @EnvironmentObject private var controller: LiveSessionController
    @ObservedObject private var session = WatchSession.shared

    var body: some View {
        let level = min(1.0, controller.liveImpact / max(0.1, controller.impactThreshold))
        HStack(spacing: 6) {
            Circle()
                .fill(level >= 1 ? WT.accent : WT.green)
                .frame(width: 8, height: 8)
                .opacity(dimmed ? 0.5 : 0.45 + 0.55 * level)
            if session.outstandingMessages > 0 {
                Text("SYNC \(session.outstandingMessages)")
                    .font(WT.mono(10)).tracking(0.8).foregroundStyle(WT.accent)
            }
        }
        .accessibilityLabel(session.outstandingMessages > 0
            ? "Listening, \(session.outstandingMessages) waiting to sync" : "Listening")
    }
}

// MARK: - Yardage hero

/// What the yardage UI needs, resolved once: the wrist's own yardage wins; the
/// phone's pushed value is the fallback (no fix yet / fix aged out / course not
/// cached).
private struct YardageReadout {
    let yards: Int?
    /// WHERE THE YARDAGE WAS COMPUTED (W = watch, P = phone) — not which
    /// device's GPS receiver produced the fix; the system doesn't say.
    let source: String?
    let hole: Int
    let par: Int?

    @MainActor
    init(caddie: WatchCaddie, phone: PhoneStateUpdate) {
        let local = caddie.localYards
        yards = local ?? (phone.isActive ? phone.distanceToGreenYards : nil)
        source = local != nil ? "W" : (yards != nil ? "P" : nil)
        hole = caddie.holeNumber
        // The phone's par is for ITS hole; when the watch has stepped ahead, use the catalog's.
        par = (phone.isActive && !caddie.holeIsAheadOfPhone) ? phone.par : caddie.hole?.par
    }

    var holeLine: String { "HOLE \(hole) · PAR \(par.map(String.init) ?? "–")" }
}

private struct YardageScreen: View {
    @EnvironmentObject private var controller: LiveSessionController
    @EnvironmentObject private var caddie: WatchCaddie
    @ObservedObject private var session = WatchSession.shared

    var body: some View {
        let s = session.phoneState
        let r = YardageReadout(caddie: caddie, phone: s)
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Text(r.holeLine)
                    .font(WT.mono(12)).tracking(1.2).foregroundStyle(WT.ink2)
                    .lineLimit(1).minimumScaleFactor(0.8)
                if let source = r.source {
                    Text(source).font(WT.mono(9)).foregroundStyle(WT.ink3)
                        .padding(.horizontal, 3)
                        .overlay(RoundedRectangle(cornerRadius: 3).stroke(WT.line, lineWidth: 1))
                }
            }
            // The hero: yards to the green, the one number this screen exists
            // for — no caption needed. (No FRONT/BACK either: the catalog has a
            // single green point, so those were invented numbers.)
            Text(r.yards.map(String.init) ?? "–––")
                .font(WT.serif(WT.s(84))).foregroundStyle(WT.ink)
                .minimumScaleFactor(0.5).lineLimit(1)
                .frame(maxHeight: .infinity)
                .accessibilityLabel(r.yards.map { "\($0) yards to green" } ?? "No yardage")
            if s.isActive {
                ClubSelector().padding(.bottom, WT.s(4))
                actionRow
            } else {
                WatchOnlyHoleStepper()
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, WT.s(16)) // clear the system page dots
        .ignoresSafeArea(edges: .bottom)
    }

    private var actionRow: some View {
        // The detector auto-logs full swings but not putts, so putts are the
        // dominant manual entry — PUTT is the big primary key; MARK is the
        // smaller fallback for a missed full-swing detection. PUTT →
        // `.puttPlusOne` (phone logs a real putt); MARK → `.addShot(nil)` (logs
        // with the current club). Putter is no longer a scroll club — this key
        // replaces it (field 2026-06-27).
        HStack(spacing: 6) {
            Button {
                WatchSession.shared.send(.command(.addShot(clubShortName: nil)))
                WKInterfaceDevice.current().play(.success)
            } label: {
                Text("MARK").font(WT.mono(12)).tracking(1.0)
            }
            .buttonStyle(WatchKeyStyle(fill: WT.surface2, ink: WT.ink))
            .frame(width: WT.s(64))

            Button {
                controller.sendPutt()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "flag.fill").font(.system(size: 13))
                    Text("PUTT +1").font(WT.mono(15)).tracking(0.8)
                        .lineLimit(1).minimumScaleFactor(0.75)
                }
            }
            .buttonStyle(WatchKeyStyle(fill: WT.accent, ink: WT.onAccent))
        }
    }
}

/// A fixed-height key for the yardage page's action row. The system bordered
/// styles grow to ~55 pt on the Ultra, which starved the hero yardage of room;
/// 40 pt is still a comfortable gloved-thumb target.
private struct WatchKeyStyle: ButtonStyle {
    let fill: Color
    let ink: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(ink)
            .frame(maxWidth: .infinity)
            .frame(height: WT.s(40))
            .background(fill, in: Capsule())
            .opacity(configuration.isPressed ? 0.6 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
    }
}

/// Wrist-down (always-on) glance: yardage, hole, club — nothing tappable,
/// nothing animating. Most looks at the watch during a round are this view.
private struct GlanceScreen: View {
    @EnvironmentObject private var controller: LiveSessionController
    @EnvironmentObject private var caddie: WatchCaddie
    @ObservedObject private var session = WatchSession.shared

    var body: some View {
        let s = session.phoneState
        let r = YardageReadout(caddie: caddie, phone: s)
        VStack(spacing: 0) {
            Text(r.holeLine)
                .font(WT.mono(13)).tracking(1.2).foregroundStyle(WT.ink2)
            Text(r.yards.map(String.init) ?? "–––")
                .font(WT.serif(WT.s(104))).foregroundStyle(WT.ink)
                .minimumScaleFactor(0.4).lineLimit(1)
                .frame(maxHeight: .infinity)
            if s.isActive, let club = controller.effectiveClubShort {
                HStack(spacing: 8) {
                    Text(club).font(WT.serif(WT.s(26))).foregroundStyle(WT.accent)
                    Text("\(s.holeShotCount) SHOT\(s.holeShotCount == 1 ? "" : "S")")
                        .font(WT.mono(12)).tracking(1).foregroundStyle(WT.ink3)
                }
            } else if let name = caddie.course?.name {
                Text(name).font(WT.serif(WT.s(15))).foregroundStyle(WT.ink3).lineLimit(1)
            }
        }
        .padding(.horizontal, 6)
        .padding(.bottom, WT.s(8))
    }
}

/// Watch-only round (no phone round to follow): the course the wrist resolved
/// and a manual hole stepper. Auto hole-advance comes with the round engine.
private struct WatchOnlyHoleStepper: View {
    @EnvironmentObject private var caddie: WatchCaddie
    @ObservedObject private var store = WatchCourseStore.shared

    var body: some View {
        VStack(spacing: 4) {
            Text(caddie.course?.name ?? (store.courses.isEmpty ? "No course data yet" : "Finding course…"))
                .font(WT.serif(WT.s(15))).foregroundStyle(WT.ink2)
                .lineLimit(1).minimumScaleFactor(0.6)
            HStack(spacing: 6) {
                stepButton("minus") { caddie.stepHole(by: -1) }
                Text("HOLE \(caddie.holeNumber)")
                    .font(WT.mono(14)).tracking(0.8)
                    .frame(maxWidth: .infinity)
                stepButton("plus") { caddie.stepHole(by: 1) }
            }
        }
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            WKInterfaceDevice.current().play(.click)
        } label: {
            Image(systemName: symbol).font(.system(size: 14, weight: .semibold))
                .frame(minHeight: WT.s(26))
        }
        .buttonStyle(.bordered).tint(WT.ink2)
        .frame(width: WT.s(52))
    }
}

/// Crown-driven club selector (list style). The selected club is bound to the
/// Digital Crown; changing it tells the controller (→ phone).
private struct ClubSelector: View {
    @EnvironmentObject private var controller: LiveSessionController
    @EnvironmentObject private var caddie: WatchCaddie
    @ObservedObject private var session = WatchSession.shared
    @State private var crown = 0.0
    @FocusState private var focused: Bool
    // Default LOCKED: the crown is inert until the card is tapped to ARM it, so a
    // wrist bend can't scroll clubs mid-round (field test 2026-06-18). Tap again
    // to lock. Only an armed selector drives selection.
    @State private var armed = false

    var body: some View {
        // Putter is button-driven now (the dedicated PUTT key), so it's no
        // longer a scrollable club. Semantic isPutter flag when the phone
        // sends it (B33 — renamed/custom putters excluded too); the literal
        // "Pt" match is the fallback for old-phone payloads.
        let clubs = session.phoneState.clubs.filter { !($0.isPutter ?? ($0.short == "Pt")) }
        let idx = currentIndex(clubs)
        let club = clubs.indices.contains(idx) ? clubs[idx] : nil

        HStack(spacing: 9) {
            Text(club?.short ?? "—").font(WT.serif(WT.s(28))).foregroundStyle(WT.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(club?.name ?? "No clubs").font(WT.serif(15)).foregroundStyle(WT.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 5) {
                    if armed {
                        Text("TAP TO LOCK").font(WT.mono(9)).tracking(0.6)
                            .foregroundStyle(WT.accent)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    } else if let club {
                        Text("\(club.avgYards)y").font(WT.mono(10)).foregroundStyle(WT.ink2)
                    }
                    if !armed {
                        // AUTO: the club follows the distance (ClubAutoPilot).
                        // HELD: a manual pick, kept until this shot is logged —
                        // long-press hands it back to auto.
                        Text(controller.clubIsAuto ? "AUTO" : "HELD").font(WT.mono(8)).tracking(0.8)
                            .foregroundStyle(controller.clubIsAuto ? WT.onAccent : WT.ink2)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(controller.clubIsAuto ? WT.green : WT.surface2,
                                        in: RoundedRectangle(cornerRadius: 3))
                    }
                }
            }
            Spacer(minLength: 0)
            // Affordance reflects the lock state: a lock glyph when inert, the
            // crown chevrons (lit) when armed.
            if armed {
                VStack(spacing: 0) {
                    Image(systemName: "chevron.up").font(.system(size: 8, weight: .bold))
                    Image(systemName: "digitalcrown.press").font(.system(size: 11))
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold))
                }
                .foregroundStyle(WT.accent)
            } else {
                Image(systemName: "lock.fill").font(.system(size: 12))
                    .foregroundStyle(WT.ink3)
            }
        }
        .padding(.horizontal, 11).padding(.vertical, 3)
        .background(WT.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(armed ? WT.accent : WT.line, lineWidth: armed ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { toggleArmed(idx: idx) }
        .onLongPressGesture {
            guard !controller.clubIsAuto else { return }
            if armed { toggleArmed(idx: idx) }
            controller.resumeAutoClub()
            WKInterfaceDevice.current().play(.success)
        }
        .focusable(armed)
        .focused($focused)
        .digitalCrownRotation($crown, from: 0, through: Double(max(0, clubs.count - 1)),
                              by: 1, sensitivity: .medium, isContinuous: false)
        .onChange(of: crown) { _, newValue in
            guard armed else { return }
            let newIdx = Int(newValue.rounded())
            guard clubs.indices.contains(newIdx), newIdx != idx else { return }
            controller.selectClub(short: clubs[newIdx].short)
            WKInterfaceDevice.current().play(.click)
        }
        #if DEBUG
        .onAppear { if WatchPreviewDebug.armClub { armed = true } }
        #endif
    }

    /// Tap toggles arm/lock. Arming syncs the crown to the current club and takes
    /// focus; locking releases focus so the crown goes inert.
    private func toggleArmed(idx: Int) {
        armed.toggle()
        if armed {
            crown = Double(idx)
            focused = true
            WKInterfaceDevice.current().play(.start)
        } else {
            focused = false
            WKInterfaceDevice.current().play(.stop)
        }
    }

    /// Effective selected index: the controller's local pick, else the phone's
    /// current club, else the suggested club.
    private func currentIndex(_ clubs: [WatchClub]) -> Int {
        let short = controller.effectiveClubShort ?? session.phoneState.currentClubShortName
        if let short, let i = clubs.firstIndex(where: { $0.short == short }) { return i }
        return suggestedClubIndex(clubs, yards: session.phoneState.distanceToGreenYards ?? 0) ?? 0
    }
}

// MARK: - Strokes

private struct StrokesScreen: View {
    @EnvironmentObject private var controller: LiveSessionController
    @ObservedObject private var session = WatchSession.shared
    @State private var adding = false
    @State private var editing: WatchStroke?

    var body: some View {
        let strokes = session.phoneState.strokes
        VStack(spacing: 0) {
            WatchHeader(left: {
                Text("STROKES · H\(session.phoneState.holeNumber)")
                    .font(WT.mono(12)).tracking(1.4).foregroundStyle(WT.ink2)
            })
            .padding(.horizontal, 8).padding(.bottom, 2)

            List {
                if strokes.isEmpty {
                    Text("No strokes logged yet")
                        .font(WT.mono(13)).foregroundStyle(WT.ink3)
                        .listRowBackground(Color.clear)
                }
                ForEach(Array(strokes.enumerated()), id: \.element.id) { i, s in
                    // Tap → edit sheet (change club / delete). Replaced the
                    // in-row two-tap delete (B25); delete is still two taps
                    // total, and club edit is the same two taps.
                    Button { editing = s } label: {
                        StrokeRow(n: i + 1, stroke: s)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets(top: 4, leading: 8, bottom: 4, trailing: 8))
                }
                Button { adding = true } label: {
                    HStack(spacing: 8) {
                        Text("+").font(WT.serif(20, italic: false)).foregroundStyle(WT.accent)
                        Text("ADD STROKE").font(WT.mono(13)).tracking(1)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered).tint(WT.ink2)
                .listRowBackground(Color.clear)
            }
            .listStyle(.carousel)
            .padding(.bottom, 14)
        }
        .sheet(isPresented: $adding) { AddSheet() }
        .sheet(item: $editing) { EditStrokeSheet(stroke: $0) }
    }
}

private struct StrokeRow: View {
    let n: Int
    let stroke: WatchStroke

    var body: some View {
        HStack(spacing: 10) {
            Text("\(n)")
                .font(WT.serif(15)).foregroundStyle(WT.ink)
                .frame(width: 28, height: 28)
                .overlay(Circle().stroke(WT.lineStrong, lineWidth: 1.4))
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stroke.clubName).font(WT.serif(17)).foregroundStyle(WT.ink)
                        .lineLimit(1).minimumScaleFactor(0.7)
                    if stroke.manual {
                        Text("MANUAL").font(WT.mono(8)).tracking(1).foregroundStyle(WT.ink3)
                            .padding(.horizontal, 3).padding(.vertical, 1)
                            .overlay(RoundedRectangle(cornerRadius: 3).stroke(WT.line, lineWidth: 1))
                    }
                }
                Text("\(stroke.lie) · \(stroke.fromYards.map { "\($0) yd" } ?? "—")")
                    .font(WT.mono(11)).foregroundStyle(WT.ink3).lineLimit(1)
            }
            Spacer(minLength: 0)
            Text("›")
                .font(WT.serif(15)).foregroundStyle(WT.ink3)
        }
    }
}

/// The 3-col club grid shared by "+ ADD STROKE" and the stroke edit sheet
/// (B25) — same cells, same data (`phoneState.clubs`, putter included).
/// `highlightShort` rings the stroke's current club in the edit flow.
private struct ClubGridPicker: View {
    var highlightShort: String? = nil
    let onPick: (WatchClub) -> Void
    @ObservedObject private var session = WatchSession.shared

    private let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        LazyVGrid(columns: cols, spacing: 8) {
            ForEach(session.phoneState.clubs) { club in
                Button {
                    onPick(club)
                } label: {
                    VStack(spacing: 2) {
                        Text(club.short).font(WT.serif(20)).foregroundStyle(WT.accent)
                        Text("\(club.avgYards)y").font(WT.mono(9)).foregroundStyle(WT.ink3)
                    }
                    .frame(maxWidth: .infinity).padding(.vertical, 10)
                    .background(WT.surface2, in: RoundedRectangle(cornerRadius: 12))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(club.short == highlightShort ? WT.accent : .clear, lineWidth: 1.6)
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 4)
    }
}

private struct AddSheet: View {
    @EnvironmentObject private var controller: LiveSessionController
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            Text("TAP A CLUB TO ADD")
                .font(WT.mono(11)).tracking(1.4).foregroundStyle(WT.ink2)
                .padding(.vertical, 8)
            ClubGridPicker { club in
                WatchSession.shared.send(.command(.addShot(clubShortName: club.short)))
                dismiss()
            }
        }
        .background(WT.bg)
    }
}

/// Tap-a-stroke edit sheet (B25): pick a club to change the logged stroke's
/// club (isPutt re-derives on the phone, B31), or DELETE it. No optimistic
/// local state — dismiss and let the ~4 s phone-state tick catch the row up.
private struct EditStrokeSheet: View {
    let stroke: WatchStroke
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(spacing: 2) {
                Text("EDIT STROKE")
                    .font(WT.mono(11)).tracking(1.4).foregroundStyle(WT.ink2)
                Text(stroke.clubName)
                    .font(WT.serif(17)).foregroundStyle(WT.ink)
            }
            .padding(.vertical, 8)

            ClubGridPicker(highlightShort: stroke.clubShort) { club in
                WatchSession.shared.send(.command(.editStrokeClub(id: stroke.id, clubShortName: club.short)))
                dismiss()
            }

            Button {
                WatchSession.shared.send(.command(.removeStroke(id: stroke.id)))
                dismiss()
            } label: {
                Text("✕ DELETE")
                    .font(WT.mono(13)).tracking(1)
                    .foregroundStyle(WT.onAccent)
                    .frame(maxWidth: .infinity, minHeight: 32)
                    .background(WT.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 4)
            .padding(.top, 10)
        }
        .background(WT.bg)
    }
}

// MARK: - Score

private struct ScoreScreen: View {
    @EnvironmentObject private var controller: LiveSessionController
    @EnvironmentObject private var caddie: WatchCaddie
    @ObservedObject private var session = WatchSession.shared

    var body: some View {
        let s = session.phoneState
        let shots = s.holeShotCount
        // To-par only means something for finished holes: the round total over
        // confirmed holes. (The hole in progress used to show e.g. "-2 TO PAR"
        // in green after two strokes on a par 4.)
        let scored = s.scorecard.filter { $0.par != nil }
        let rel: Int? = scored.isEmpty ? nil : scored.reduce(0) { $0 + $1.strokes - ($1.par ?? 0) }
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            WatchHeader(left: {
                Text("SCORE").font(WT.mono(12)).tracking(1.6).foregroundStyle(WT.ink2)
            })
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(shots)").font(WT.serif(WT.s(56))).foregroundStyle(WT.ink)
                    Text("STROKES · HOLE \(s.holeNumber)")
                        .font(WT.mono(10)).tracking(1.2).foregroundStyle(WT.ink3)
                }
                Spacer()
                if let rel {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(rel == 0 ? "EVEN" : rel > 0 ? "+\(rel)" : "\(rel)")
                            .font(WT.serif(WT.s(30)))
                            .foregroundStyle(rel > 0 ? WT.accent : rel < 0 ? WT.green : WT.ink2)
                        Text("THRU \(scored.count)").font(WT.mono(10)).tracking(1).foregroundStyle(WT.ink3)
                    }
                } else if let par = s.par {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text("\(par)").font(WT.serif(WT.s(30))).foregroundStyle(WT.ink2)
                        Text("PAR").font(WT.mono(10)).tracking(1).foregroundStyle(WT.ink3)
                    }
                }
            }

            Divider().overlay(WT.line)
            ForEach(s.scorecard) { row in
                HStack {
                    Text("Hole \(row.hole)").font(WT.mono(13)).foregroundStyle(WT.ink2).frame(width: 56, alignment: .leading)
                    Text("par \(row.par.map(String.init) ?? "–")").font(WT.mono(11)).foregroundStyle(WT.ink3)
                    Spacer()
                    let d = row.par.map { row.strokes - $0 }
                    Text("\(row.strokes)")
                        .font(WT.mono(14))
                        .foregroundStyle(d.map { $0 > 0 ? WT.accent : $0 < 0 ? WT.green : WT.ink } ?? WT.ink)
                }
                .padding(.vertical, 5)
                Divider().overlay(WT.line)
            }

            // Hole navigation: back (recover an accidental advance) + Next Hole
            // (confirms this hole and advances). Goes to the phone over WC.
            HStack(spacing: 6) {
                Button {
                    WatchSession.shared.send(.command(.previousHole))
                    caddie.holeStepRequested(by: -1)
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    Text("‹").font(WT.serif(20)).frame(width: WT.s(40), height: WT.s(40))
                }
                .buttonStyle(.bordered).tint(WT.ink2)
                Button {
                    WatchSession.shared.send(.command(.advanceHole))
                    caddie.holeStepRequested(by: 1)
                    WKInterfaceDevice.current().play(.success)
                } label: {
                    Text("Next Hole ›").font(WT.serif(16)).frame(maxWidth: .infinity, minHeight: WT.s(40))
                }
                .buttonStyle(.borderedProminent).tint(WT.accent)
            }
            .padding(.top, 2)

            Button {
                controller.stop()
            } label: {
                Text("END TRACKING").font(WT.mono(11)).tracking(1.2).frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered).tint(WT.ink2)
            .padding(.bottom, 4)
          }
          .padding(.horizontal, 8)
        }
    }
}

// MARK: - Detect card

private struct DetectCard: View {
    @EnvironmentObject private var controller: LiveSessionController
    @ObservedObject private var session = WatchSession.shared
    private static let seconds = 5.0
    @State private var remaining = 5.0
    @State private var timer: Timer?

    var body: some View {
        let club = controller.effectiveClubShort
            .flatMap { sh in session.phoneState.clubs.first { $0.short == sh } }
        let pct = remaining / Self.seconds

        ZStack {
            Color.black.opacity(0.82).ignoresSafeArea()
            VStack {
                Spacer()
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Circle().fill(WT.accent).frame(width: 8, height: 8)
                            .shadow(color: WT.accent, radius: 4)
                        Text("STROKE DETECTED").font(WT.mono(11)).tracking(1.4).foregroundStyle(WT.accent)
                    }
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(club?.name ?? "Stroke").font(WT.serif(WT.s(26))).foregroundStyle(WT.ink)
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Text("\(club?.short ?? "—") · from \(session.phoneState.distanceToGreenYards.map(String.init) ?? "—") yd")
                                .font(WT.mono(11)).foregroundStyle(WT.ink2)
                            Text("↻ crown to change").font(WT.mono(9)).foregroundStyle(WT.ink3)
                        }
                        Spacer(minLength: 0)
                        ZStack {
                            Circle().stroke(WT.ink.opacity(0.14), lineWidth: 5).frame(width: WT.s(58), height: WT.s(58))
                            Circle().trim(from: 0, to: pct)
                                .stroke(WT.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: WT.s(58), height: WT.s(58))
                            Text("\(Int(ceil(remaining)))").font(WT.serif(WT.s(24))).foregroundStyle(WT.ink)
                        }
                    }
                    HStack(spacing: 8) {
                        Button { stop(); controller.dismissPending() } label: {
                            Text("Not a shot").font(WT.mono(11)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered).tint(WT.ink2)
                        Button { stop(); controller.confirmPending() } label: {
                            Text("✓ Log it").font(WT.serif(17)).frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent).tint(WT.accent)
                    }
                }
                .padding(WT.s(14))
                .background(WT.surface, in: RoundedRectangle(cornerRadius: 22))
                .overlay(RoundedRectangle(cornerRadius: 22).stroke(WT.lineStrong, lineWidth: 1))
                .padding(.horizontal, 6)
            }
        }
        .onAppear(perform: startCountdown)
        .onDisappear { stop() }
    }

    private func startCountdown() {
        remaining = Self.seconds
        let start = Date()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { _ in
            let rem = max(0, Self.seconds - Date().timeIntervalSince(start))
            remaining = rem
            if rem <= 0 { stop(); controller.confirmPending() }
        }
    }

    private func stop() {
        timer?.invalidate()
        timer = nil
    }
}
