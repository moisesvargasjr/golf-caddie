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
            if s.isActive {
                HStack(spacing: 18) {
                    stat("HOLE", "\(s.holeNumber)")
                    stat("PAR", s.par.map(String.init) ?? "–")
                    stat("SHOTS", "\(s.holeShotCount)")
                }
                .padding(.top, 14)
            } else {
                // No phone round: a row of "– – 0" says nothing. Say what
                // starting from here does instead.
                Text("Watch only: yardage + workout.\nStart a round on the phone to log shots.")
                    .font(WT.mono(10)).foregroundStyle(WT.ink2)
                    .lineLimit(3).minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 8)
            }
            Spacer()
            Button {
                Task { await controller.start() }
            } label: {
                Text(s.isActive ? "Resume Hole \(s.holeNumber)" : "Start Tracking")
                    .font(WT.serif(18)).frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(WT.accent)
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
        // The Ultra's corners are rounder than the simulator draws them: on the
        // device, left-aligned footer text was cut off ("'PS LOG ON"). Scene
        // padding is the system's corner-safe inset; the footer is centred.
        .scenePadding(.horizontal)
        .padding(.bottom, WT.s(6))
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
        HStack(spacing: 10) {
            Button { telemetry.enabled.toggle() } label: {
                Text("GPS LOG \(telemetry.enabled ? "ON" : "OFF")").font(WT.mono(10)).tracking(0.8)
            }
            .buttonStyle(.plain)
            .foregroundStyle(telemetry.enabled ? WT.accent : WT.ink3)
            if session.telemetryPending > 0 {
                Text("\(session.telemetryPending) TO SEND").font(WT.mono(10)).foregroundStyle(WT.ink2)
            }
        }
        .frame(maxWidth: .infinity) // centred: the bottom corners clip the edges
        .padding(.top, 6)
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
                    // Actions sit LEFT of the yardage: one swipe right from the
                    // main screen. Round commands only → needs a phone round.
                    if session.phoneState.isActive {
                        ActionsScreen(done: { withAnimation { page = 0 } }).tag(-1)
                    }
                    YardageScreen().tag(0)
                    // Strokes and the club grid come from a phone round; watch-only
                    // the page read "STROKES · H0" and ADD STROKE opened an empty grid.
                    if session.phoneState.isActive {
                        StrokesScreen().tag(1)
                    }
                    ScoreScreen().tag(2)
                }
                .tabViewStyle(.page)
                .onChange(of: session.phoneState.isActive) { _, active in
                    if !active, page == 1 || page == -1 { page = 0 }
                }
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
            YardageHero(yards: r.yards, size: WT.s(84))
                .accessibilityLabel(r.yards.map { "\($0) yards to green" } ?? "No yardage")
            if s.isActive {
                ClubSelector().padding(.bottom, WT.s(4))
                actionRow
            } else {
                WatchOnlyHoleStepper()
            }
        }
        .scenePadding(.horizontal) // corner-safe: the device's corners are rounder than the simulator's
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
                controller.sendMark()
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

/// The hero number — or, with no yardage yet, a quiet placeholder (three 84 pt
/// serif dashes rendered as one heavy bar).
private struct YardageHero: View {
    let yards: Int?
    let size: CGFloat

    var body: some View {
        Group {
            if let yards {
                // String(…), not "\(yards)": Text's interpolation localizes an Int
                // with grouping, and the device showed "1,211".
                Text(String(yards)).font(WT.serif(size)).foregroundStyle(WT.ink)
                    .minimumScaleFactor(0.4).lineLimit(1)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "location.slash").font(.system(size: size * 0.3))
                    Text("NO YARDAGE YET").font(WT.mono(11)).tracking(1.2)
                }
                .foregroundStyle(WT.ink3)
            }
        }
        .frame(maxHeight: .infinity)
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
            YardageHero(yards: r.yards, size: WT.s(104))
            if s.isActive, let club = controller.effectiveClubShort {
                HStack(spacing: 8) {
                    Text(club).font(WT.serif(WT.s(26))).foregroundStyle(WT.accent)
                    Text("\(s.holeStrokeTotal) STROKE\(s.holeStrokeTotal == 1 ? "" : "S")")
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
        }
        .buttonStyle(WatchKeyStyle(fill: WT.surface2, ink: WT.ink))
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

// MARK: - Actions (swipe right from the yardage)

/// The "something happened" page, one swipe right of the yardage: add a penalty
/// stroke, undo the last thing, move to the next hole. Everything here is a
/// queued command to the phone round, so the page only exists with one.
private struct ActionsScreen: View {
    /// Return to the yardage after an action — you came here to do one thing.
    let done: () -> Void
    @EnvironmentObject private var caddie: WatchCaddie
    @ObservedObject private var session = WatchSession.shared
    @State private var confirmingUndo = false
    @State private var finishing = false
    @State private var lastAdded: WatchPenaltyKind?

    private let cols = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6)]

    var body: some View {
        let s = session.phoneState
        VStack(spacing: WT.s(6)) {
            HStack {
                Text("PENALTY +1").font(WT.mono(12)).tracking(1.4).foregroundStyle(WT.ink2)
                Spacer()
                let pens = s.holePenaltyStrokes ?? 0
                Text(lastAdded.map { "\($0.label) SENT" } ?? "H\(caddie.holeNumber) · \(pens) PEN")
                    .font(WT.mono(10)).tracking(0.8)
                    .foregroundStyle(lastAdded != nil ? WT.green : WT.ink3)
            }
            LazyVGrid(columns: cols, spacing: 6) {
                ForEach(WatchPenaltyKind.allCases) { kind in
                    Button { add(kind) } label: {
                        HStack(spacing: 5) {
                            Image(systemName: kind.symbol).font(.system(size: 13, weight: .semibold))
                            Text(kind.label).font(WT.mono(12)).lineLimit(1).minimumScaleFactor(0.7)
                        }
                        .padding(.horizontal, 8)
                    }
                    .buttonStyle(WatchKeyStyle(fill: WT.surface2, ink: WT.ink))
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: 6) {
                Button { confirmingUndo = true } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.uturn.backward").font(.system(size: 12, weight: .bold))
                        Text("UNDO").font(WT.mono(12)).tracking(0.8)
                    }
                }
                .buttonStyle(WatchKeyStyle(fill: WT.surface, ink: WT.ink2))
                .frame(width: WT.s(78))
                Button { finishing = true } label: {
                    Text("Finish Hole").font(WT.serif(17)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .buttonStyle(WatchKeyStyle(fill: WT.accent, ink: WT.onAccent))
            }
        }
        .sheet(isPresented: $finishing) { FinishHoleSheet(done: done) }
        #if DEBUG
        .onAppear { if WatchPreviewDebug.finishStep > 0 { finishing = true } }
        #endif
        .padding(.top, WT.s(4))
        .scenePadding(.horizontal)
        .padding(.bottom, WT.s(16)) // clear the system page dots
        .ignoresSafeArea(edges: .bottom)
        // Undo removes the newest shot OR penalty on the hole — say so first.
        .confirmationDialog("Undo the last stroke or penalty?", isPresented: $confirmingUndo,
                            titleVisibility: .visible) {
            Button("Undo", role: .destructive) {
                WatchSession.shared.send(.command(.removeStroke(id: nil)))
                WKInterfaceDevice.current().play(.click)
                done()
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func add(_ kind: WatchPenaltyKind) {
        WatchSession.shared.send(.command(.addPenalty(kind: kind.rawValue)))
        WKInterfaceDevice.current().play(.success)
        lastAdded = kind
        // Show "SENT" for a beat, then back to the yardage.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 900_000_000)
            lastAdded = nil
            done()
        }
    }
}

// MARK: - Finish Hole (the one check per hole)

/// Putts → confirm the score → done. The score is pre-filled from what was
/// tracked (full shots + the putts just given + penalties) and is what the
/// phone reconciles the hole to, so a wrong pre-fill costs one or two taps on
/// − / +, never a blank to fill in.
private struct FinishHoleSheet: View {
    /// Called after the hole is sent (return to the yardage).
    let done: () -> Void
    @EnvironmentObject private var controller: LiveSessionController
    @EnvironmentObject private var caddie: WatchCaddie
    @ObservedObject private var session = WatchSession.shared
    @Environment(\.dismiss) private var dismiss
    @State private var putts: Int?
    @State private var score = 0

    private let cols = [GridItem(.flexible(), spacing: 6), GridItem(.flexible(), spacing: 6),
                        GridItem(.flexible(), spacing: 6)]

    var body: some View {
        let full = controller.fullShotsForFinish
        let pens = session.phoneState.holePenaltyStrokes ?? 0
        VStack(spacing: WT.s(6)) {
            if let putts {
                Text("HOLE \(caddie.holeNumber) · CONFIRM SCORE")
                    .font(WT.mono(11)).tracking(1.2).foregroundStyle(WT.ink2)
                HStack(spacing: 10) {
                    stepKey("minus") { score = max(putts, score - 1) }
                    Text("\(score)").font(WT.serif(WT.s(58))).foregroundStyle(WT.ink)
                        .frame(minWidth: WT.s(60)).minimumScaleFactor(0.6).lineLimit(1)
                    stepKey("plus") { score += 1 }
                }
                .frame(maxHeight: .infinity)
                Text("\(full) shot\(full == 1 ? "" : "s") + \(putts) putt\(putts == 1 ? "" : "s")" + (pens > 0 ? " + \(pens) pen" : ""))
                    .font(WT.mono(10)).foregroundStyle(WT.ink3).lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 6) {
                    Button { self.putts = nil } label: {
                        Image(systemName: "chevron.left").font(.system(size: 14, weight: .bold))
                    }
                    .buttonStyle(WatchKeyStyle(fill: WT.surface2, ink: WT.ink))
                    .frame(width: WT.s(48))
                    Button { confirm(putts: putts) } label: {
                        Text("Confirm").font(WT.serif(17))
                    }
                    .buttonStyle(WatchKeyStyle(fill: WT.accent, ink: WT.onAccent))
                }
            } else {
                Text("HOLE \(caddie.holeNumber) · PUTTS?")
                    .font(WT.mono(11)).tracking(1.2).foregroundStyle(WT.ink2)
                LazyVGrid(columns: cols, spacing: 6) {
                    ForEach(0..<6, id: \.self) { n in
                        Button {
                            putts = n
                            score = full + n + pens
                            WKInterfaceDevice.current().play(.click)
                        } label: {
                            Text(n == 5 ? "5+" : "\(n)").font(WT.serif(22))
                        }
                        .buttonStyle(WatchKeyStyle(fill: WT.surface2, ink: WT.ink))
                    }
                }
                .frame(maxHeight: .infinity)
            }
        }
        .scenePadding(.horizontal)
        .padding(.bottom, WT.s(6))
        .background(WT.bg)
        #if DEBUG
        .onAppear {
            if WatchPreviewDebug.finishStep == 2 {
                putts = 2
                score = controller.fullShotsForFinish + 2 + (session.phoneState.holePenaltyStrokes ?? 0)
            }
        }
        #endif
    }

    private func stepKey(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            WKInterfaceDevice.current().play(.click)
        } label: {
            Image(systemName: symbol).font(.system(size: 16, weight: .bold))
        }
        .buttonStyle(WatchKeyStyle(fill: WT.surface2, ink: WT.ink))
        .frame(width: WT.s(46))
    }

    private func confirm(putts: Int) {
        WatchSession.shared.send(.command(.finishHole(putts: putts, score: score)))
        caddie.holeStepRequested(by: 1)
        WKInterfaceDevice.current().play(.success)
        dismiss()
        done()
    }
}

// MARK: - Strokes

private struct StrokesScreen: View {
    @EnvironmentObject private var controller: LiveSessionController
    @EnvironmentObject private var caddie: WatchCaddie
    @ObservedObject private var session = WatchSession.shared
    @State private var adding = false
    @State private var editing: WatchStroke?

    var body: some View {
        let strokes = session.phoneState.strokes
        VStack(spacing: 0) {
            WatchHeader(left: {
                Text("STROKES · H\(caddie.holeNumber)")
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

    @State private var confirmingEnd = false
    @State private var finishing = false

    var body: some View {
        let s = session.phoneState
        let shots = s.holeStrokeTotal // shots + penalty strokes: what the hole will score
        // To-par only means something for finished holes: the round total over
        // confirmed holes. (The hole in progress used to show e.g. "-2 TO PAR"
        // in green after two strokes on a par 4.)
        let scored = s.scorecard.filter { $0.par != nil }
        let rel: Int? = scored.isEmpty ? nil : scored.reduce(0) { $0 + $1.strokes - ($1.par ?? 0) }
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            WatchHeader(left: {
                Text(s.isActive ? "SCORE" : "WATCH ONLY").font(WT.mono(12)).tracking(1.6).foregroundStyle(WT.ink2)
            })
            if s.isActive {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(shots)").font(WT.serif(WT.s(56))).foregroundStyle(WT.ink)
                        Text("STROKES · HOLE \(caddie.holeNumber)" + ((s.holePenaltyStrokes ?? 0) > 0 ? " · \(s.holePenaltyStrokes ?? 0) PEN" : ""))
                            .font(WT.mono(10)).tracking(1.2).foregroundStyle(WT.ink3)
                            .lineLimit(1).minimumScaleFactor(0.7)
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
            } else {
                // No phone round → no strokes to count (it read "0 · HOLE 0").
                // This page is just the hole you're on.
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("\(caddie.holeNumber)").font(WT.serif(WT.s(40))).foregroundStyle(WT.ink)
                        Text("HOLE").font(WT.mono(10)).tracking(1.2).foregroundStyle(WT.ink3)
                    }
                    Spacer()
                    if let par = caddie.hole?.par {
                        VStack(alignment: .trailing, spacing: 0) {
                            Text("\(par)").font(WT.serif(WT.s(30))).foregroundStyle(WT.ink2)
                            Text("PAR").font(WT.mono(10)).tracking(1).foregroundStyle(WT.ink3)
                        }
                    }
                }
                Text(caddie.course?.name ?? (WatchCourseStore.shared.courses.isEmpty ? "No course data yet" : "Finding course…"))
                    .font(WT.mono(10)).foregroundStyle(WT.ink3).lineLimit(1).minimumScaleFactor(0.7)
            }

            if s.isActive { Divider().overlay(WT.line) }
            ForEach(s.isActive ? s.scorecard : []) { row in
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

            // Hole navigation. With a phone round: back (recover an accidental
            // advance) + Next Hole (confirms this hole and advances) go to the
            // phone over WC, and the watch steps its own hole at once. Watch
            // only: they just step the watch's hole.
            HStack(spacing: 6) {
                Button {
                    stepHole(by: -1, phoneCommand: .previousHole)
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    Image(systemName: "chevron.left").font(.system(size: 15, weight: .bold))
                }
                .buttonStyle(WatchKeyStyle(fill: WT.surface2, ink: WT.ink))
                .frame(width: WT.s(52))
                Button {
                    if s.isActive {
                        finishing = true
                    } else {
                        stepHole(by: 1, phoneCommand: .advanceHole)
                        WKInterfaceDevice.current().play(.success)
                    }
                } label: {
                    // One line: on the device "Next Hole ›" wrapped to two.
                    Text(s.isActive ? "Finish Hole" : "Next Hole").font(WT.serif(17)).lineLimit(1).minimumScaleFactor(0.7)
                }
                .buttonStyle(WatchKeyStyle(fill: WT.accent, ink: WT.onAccent))
            }
            .padding(.top, 4)

            Button { confirmingEnd = true } label: {
                Text("END TRACKING").font(WT.mono(11)).tracking(1.2)
            }
            .buttonStyle(WatchKeyStyle(fill: WT.surface, ink: WT.ink2))
            .padding(.top, 6)
          }
          .scenePadding(.horizontal)
          // Room to scroll the last key clear of the rounded bottom edge — on the
          // device END TRACKING sat half under the curve.
          .padding(.bottom, WT.s(28))
        }
        .sheet(isPresented: $finishing) { FinishHoleSheet(done: {}) }
        // It sits right under Next Hole: a slip shouldn't end the workout.
        .confirmationDialog("End tracking?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End", role: .destructive) { controller.stop() }
            Button("Keep Going", role: .cancel) {}
        }
    }

    private func stepHole(by delta: Int, phoneCommand: WatchCommand) {
        if session.phoneState.isActive {
            WatchSession.shared.send(.command(phoneCommand))
            caddie.holeStepRequested(by: delta)
        } else {
            caddie.stepHole(by: delta)
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
