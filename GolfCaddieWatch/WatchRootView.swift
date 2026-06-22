import SwiftUI
import WatchKit

/// Top level: a Start screen until the detection session is running, then the
/// three glance pages (Yardage / Strokes / Score) with the DetectCard overlay.
/// Round data is read from the phone (WatchSession.phoneState); detection +
/// session control live on LiveSessionController.
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

/// Persistent "the watch is sensing motion" meter while a session is running:
/// a pulsing dot + a thin bar that fills toward the ball-strike threshold, so
/// you can see motion register and how hard a real hit needs to be.
private struct ListeningBar: View {
    @EnvironmentObject private var controller: LiveSessionController
    @State private var pulse = false

    var body: some View {
        let level = min(1.0, controller.liveImpact / max(0.1, controller.impactThreshold))
        HStack(spacing: 6) {
            Circle()
                .fill(WT.green)
                .frame(width: 6, height: 6)
                .opacity(pulse ? 1 : 0.3)
                .animation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true), value: pulse)
            Text("LISTENING").font(WT.mono(9)).tracking(1).foregroundStyle(WT.ink3)
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(WT.ink.opacity(0.12)).frame(height: 4)
                    Capsule().fill(level >= 1 ? WT.accent : WT.green)
                        .frame(width: geo.size.width * level, height: 4)
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
        }
        .padding(.horizontal, 10)
        .frame(height: 14)
        .onAppear { pulse = true }
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

/// Watch→phone delivery backlog (B4). Shown on the play screen only while
/// messages are still queued for an unreachable phone, so a silent backlog is
/// never mistaken for "delivered". Drains itself as the link recovers. A pulsing
/// amber dot keeps it glanceable without competing with the LISTENING meter.
private struct SyncChip: View {
    let count: Int
    @State private var pulse = false
    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(WT.accent)
                .frame(width: 5, height: 5)
                .opacity(pulse ? 1 : 0.35)
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
            Text("SYNCING \(count)").font(WT.mono(9)).tracking(1).foregroundStyle(WT.ink2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(WT.accent.opacity(0.12), in: Capsule())
        .onAppear { pulse = true }
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
                .font(WT.serif(26)).foregroundStyle(WT.ink)
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
            if let err = controller.lastError {
                Text(err).font(WT.mono(10)).foregroundStyle(.red).padding(.top, 4)
            }
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
            Text(value).font(WT.serif(28)).foregroundStyle(WT.ink)
        }
    }
}

// MARK: - Play (paged)

private struct WatchPlayView: View {
    @EnvironmentObject private var controller: LiveSessionController
    @ObservedObject private var session = WatchSession.shared
    @State private var page: Int = {
        #if DEBUG
        return WatchPreviewDebug.initialPage
        #else
        return 0
        #endif
    }()
    var body: some View {
        // Stack the listening meter, the paged content, and the dots so none of
        // them overlap the page content (they used to, as ZStack overlays).
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                ListeningBar().padding(.top, 1)
                // Delivery backlog (B4) — only present when something is queued,
                // so it costs no space on a healthy link. Outside the TabView so
                // it's visible on every page.
                if session.outstandingMessages > 0 {
                    SyncChip(count: session.outstandingMessages).padding(.bottom, 1)
                }
                TabView(selection: $page) {
                    YardageScreen().tag(0)
                    StrokesScreen().tag(1)
                    ScoreScreen().tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)
                PageDots(page: page).frame(height: 10).padding(.vertical, 3)
            }
            #if DEBUG
            // Validation ground-truth MARK (M8 only) — top-right corner tap (B20).
            if controller.validationMode {
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
    }
}

private struct PageDots: View {
    let page: Int
    var body: some View {
        HStack(spacing: 7) {
            ForEach(0..<3, id: \.self) { i in
                Capsule()
                    .fill(i == page ? WT.accent : WT.ink.opacity(0.28))
                    .frame(width: i == page ? 16 : 6, height: 6)
            }
        }
    }
}

// MARK: - Yardage hero

private struct YardageScreen: View {
    @EnvironmentObject private var controller: LiveSessionController
    @ObservedObject private var session = WatchSession.shared

    var body: some View {
        let s = session.phoneState
        let yards = s.distanceToGreenYards
        VStack(spacing: 2) {
            // Compact single info line (saves two rows on a 40mm screen).
            Text("HOLE \(s.holeNumber) · PAR \(s.par.map(String.init) ?? "–") · TO GREEN")
                .font(WT.mono(9)).tracking(1.4).foregroundStyle(WT.ink2)
                .lineLimit(1).minimumScaleFactor(0.7)
            Text(yards.map(String.init) ?? "–––")
                .font(WT.serif(38)).foregroundStyle(WT.ink)
                .minimumScaleFactor(0.5).lineLimit(1)
                .shadow(color: .black.opacity(0.8), radius: 8, y: 2)
            // Front/back folded into one compact line (was a full row) so the
            // club card + MARK button both fit the 40mm screen.
            if let y = yards {
                HStack(spacing: 10) {
                    Text("FRONT \(max(0, y - 7))").font(WT.mono(11)).foregroundStyle(WT.ink2)
                    Text("BACK \(y + 9)").font(WT.mono(11)).foregroundStyle(WT.ink2)
                }
                .lineLimit(1).minimumScaleFactor(0.7)
            }
            ClubSelector()
            // Quick log — for putts/chips the detector doesn't catch, so they're
            // one tap instead of pulling the phone out (field test 2026-06-18).
            Button {
                WatchSession.shared.send(.command(.addShot(clubShortName: nil)))
                WKInterfaceDevice.current().play(.success)
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle.fill").font(.system(size: 14))
                    Text("MARK SHOT").font(WT.mono(12)).tracking(1.2)
                }
                .frame(maxWidth: .infinity, minHeight: 26)
            }
            .buttonStyle(.borderedProminent).tint(WT.accent)
        }
        .padding(.horizontal, 6)
    }
}

/// Crown-driven club selector (list style). The selected club is bound to the
/// Digital Crown; changing it tells the controller (→ phone).
private struct ClubSelector: View {
    @EnvironmentObject private var controller: LiveSessionController
    @ObservedObject private var session = WatchSession.shared
    @State private var crown = 0.0
    @FocusState private var focused: Bool
    // Default LOCKED: the crown is inert until the card is tapped to ARM it, so a
    // wrist bend can't scroll clubs mid-round (field test 2026-06-18). Tap again
    // to lock. Only an armed selector drives selection.
    @State private var armed = false

    var body: some View {
        let clubs = session.phoneState.clubs
        let idx = currentIndex(clubs)
        let club = clubs.indices.contains(idx) ? clubs[idx] : nil
        let suggested = suggestedClubIndex(clubs, yards: session.phoneState.distanceToGreenYards ?? 0)

        HStack(spacing: 9) {
            Text(club?.short ?? "—").font(WT.serif(28)).foregroundStyle(WT.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(club?.name ?? "No clubs").font(WT.serif(15)).foregroundStyle(WT.ink)
                    .lineLimit(1).minimumScaleFactor(0.7)
                HStack(spacing: 5) {
                    if armed {
                        Text("TAP TO LOCK").font(WT.mono(9)).tracking(0.6)
                            .foregroundStyle(WT.accent)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    } else if let club {
                        Text("avg \(club.avgYards)y").font(WT.mono(10)).foregroundStyle(WT.ink2)
                    }
                    if !armed, suggested == idx {
                        Text("SUGGESTED").font(WT.mono(8)).tracking(0.8)
                            .foregroundStyle(WT.onAccent)
                            .padding(.horizontal, 4).padding(.vertical, 1)
                            .background(WT.green, in: RoundedRectangle(cornerRadius: 3))
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
        .padding(.horizontal, 11).padding(.vertical, 5)
        .background(WT.surface, in: RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16)
            .stroke(armed ? WT.accent : WT.line, lineWidth: armed ? 2 : 1))
        .contentShape(Rectangle())
        .onTapGesture { toggleArmed(idx: idx) }
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
                    StrokeRow(n: i + 1, stroke: s) {
                        WatchSession.shared.send(.command(.removeStroke(id: s.id)))
                    }
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
    }
}

private struct StrokeRow: View {
    let n: Int
    let stroke: WatchStroke
    let onRemove: () -> Void
    @State private var armed = false

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
                Text("\(stroke.lie) · \(stroke.fromYards.map { "\($0) yd" } ?? "—") · \(stroke.time)")
                    .font(WT.mono(11)).foregroundStyle(WT.ink3).lineLimit(1)
            }
            Spacer(minLength: 0)
            Button {
                if armed { onRemove() } else { armed = true }
            } label: {
                Text(armed ? "DEL" : "−")
                    .font(WT.mono(armed ? 11 : 18))
                    .foregroundStyle(armed ? WT.onAccent : WT.ink3)
                    .padding(.horizontal, armed ? 8 : 0)
                    .frame(minWidth: 30, minHeight: 28)
                    .background(armed ? WT.accent : .clear, in: Capsule())
            }
            .buttonStyle(.plain)
        }
    }
}

private struct AddSheet: View {
    @EnvironmentObject private var controller: LiveSessionController
    @ObservedObject private var session = WatchSession.shared
    @Environment(\.dismiss) private var dismiss

    private let cols = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        ScrollView {
            Text("TAP A CLUB TO ADD")
                .font(WT.mono(11)).tracking(1.4).foregroundStyle(WT.ink2)
                .padding(.vertical, 8)
            LazyVGrid(columns: cols, spacing: 8) {
                ForEach(session.phoneState.clubs) { club in
                    Button {
                        WatchSession.shared.send(.command(.addShot(clubShortName: club.short)))
                        dismiss()
                    } label: {
                        VStack(spacing: 2) {
                            Text(club.short).font(WT.serif(20)).foregroundStyle(WT.accent)
                            Text("\(club.avgYards)y").font(WT.mono(9)).foregroundStyle(WT.ink3)
                        }
                        .frame(maxWidth: .infinity).padding(.vertical, 10)
                        .background(WT.surface2, in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 4)
        }
        .background(WT.bg)
    }
}

// MARK: - Score

private struct ScoreScreen: View {
    @EnvironmentObject private var controller: LiveSessionController
    @ObservedObject private var session = WatchSession.shared

    var body: some View {
        let s = session.phoneState
        let shots = s.holeShotCount
        let rel = s.par.map { shots - $0 }
        ScrollView {
          VStack(alignment: .leading, spacing: 4) {
            WatchHeader(left: {
                Text("SCORE").font(WT.mono(12)).tracking(1.6).foregroundStyle(WT.ink2)
            })
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(shots)").font(WT.serif(56)).foregroundStyle(WT.ink)
                    Text("STROKES · HOLE \(s.holeNumber)")
                        .font(WT.mono(10)).tracking(1.2).foregroundStyle(WT.ink3)
                }
                Spacer()
                if let rel {
                    VStack(alignment: .trailing, spacing: 0) {
                        Text(rel == 0 ? "EVEN" : rel > 0 ? "+\(rel)" : "\(rel)")
                            .font(WT.serif(30))
                            .foregroundStyle(rel > 0 ? WT.accent : rel < 0 ? WT.green : WT.ink2)
                        Text("TO PAR").font(WT.mono(10)).tracking(1).foregroundStyle(WT.ink3)
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
                    WKInterfaceDevice.current().play(.click)
                } label: {
                    Text("‹").font(WT.serif(20)).frame(width: 40, height: 40)
                }
                .buttonStyle(.bordered).tint(WT.ink2)
                Button {
                    WatchSession.shared.send(.command(.advanceHole))
                    WKInterfaceDevice.current().play(.success)
                } label: {
                    Text("Next Hole ›").font(WT.serif(16)).frame(maxWidth: .infinity, minHeight: 40)
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
                            Text(club?.name ?? "Stroke").font(WT.serif(26)).foregroundStyle(WT.ink)
                                .lineLimit(1).minimumScaleFactor(0.6)
                            Text("\(club?.short ?? "—") · from \(session.phoneState.distanceToGreenYards.map(String.init) ?? "—") yd")
                                .font(WT.mono(11)).foregroundStyle(WT.ink2)
                            Text("↻ crown to change").font(WT.mono(9)).foregroundStyle(WT.ink3)
                        }
                        Spacer(minLength: 0)
                        ZStack {
                            Circle().stroke(WT.ink.opacity(0.14), lineWidth: 5).frame(width: 58, height: 58)
                            Circle().trim(from: 0, to: pct)
                                .stroke(WT.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                                .rotationEffect(.degrees(-90))
                                .frame(width: 58, height: 58)
                            Text("\(Int(ceil(remaining)))").font(WT.serif(24)).foregroundStyle(WT.ink)
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
                .padding(14)
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
