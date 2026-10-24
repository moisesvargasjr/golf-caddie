import CoreLocation
import SwiftUI

/// What the screen asks of whoever hosts it (sheets and round-level actions
/// that live outside the map: the card, the bag, the course picker, …).
struct RoundMapHost {
    var openCard: () -> Void = {}
    var openBag: () -> Void = {}
    var openHoleGrid: () -> Void = {}
    var linkCourse: () -> Void = {}
    var unlinkCourse: () -> Void = {}
    var toggleCasual: () -> Void = {}
    var endRound: () -> Void = {}

    // Review (a finished round; PR 7). `openCard` goes back to its card.
    /// The round's date, for "OCT 23 · 79 (+7)".
    var roundDate: Date? = nil
    /// What ··· offers; nil in the live round (its own menu).
    var roundActions: RoundActionsAvailability? = nil
    var roundActionHandlers = RoundActionHandlers()
}

/// One map screen for every hole (Duo v2, Architecture C): ONE `HoleMap`,
/// full-bleed behind everything, with the controls for the current
/// `RoundMapLayout` drawn over it. The hole on screen is a `HoleSession`, so
/// the live hole and a past hole are edited the same way (drag pins, hold to
/// add, tap a shot then a club, penalties, putts, hand scores).
///
/// - `mode`: `.tracking` / `.casual` for the live round; `.review` for a
///   finished round (pass `live: nil` and drive `viewedHole`; the host's
///   `openCard` goes back to the round's card and ··· shows the round
///   actions). The layouts read only the mode's traits.
/// - `viewedHole`: the hole on screen; nil follows the live hole. The host
///   owns it so the hole grid and the card can open any hole.
/// - `question`: the open question; a binding so the host can open one
///   (DEBUG `-DebugOpen review|penalty|casual-finish`).
/// - `course`: the course pose (PR 8) — the whole course on this same map;
///   a tapped hole glides in and becomes its review.
///
/// Posture changes only swap the chrome: the map, the session and all state
/// here survive fold / unfold / book / rotate.
struct RoundMapScreen: View {
    let mode: RoundMapMode
    let roundID: UUID
    /// The live round; nil for a finished round (review).
    let live: RoundController?
    let curatedCourseId: String?
    let courseName: String?
    /// Clubs in play, in bag order.
    let clubs: [Club]
    let host: RoundMapHost
    @Binding var viewedHole: Int?
    @Binding var question: RoundMapQuestion?
    /// PR 8: a finished round's course map (nil elsewhere). While it is
    /// showing, this same map draws every hole (`RoundMapScreen+Course`).
    var course: RoundMapCourse? = nil

    @Environment(\.displayContext) var display
    @AppStorage("units") var unitsRaw: String = Units.yards.rawValue

    @State var session: HoleSession?
    @State var autoHide: AutoHideController?
    @State var mapController = HoleMapController()
    @State var selectedShotID: UUID?
    @State var isDragging = false
    @State var puttsChoice = PuttsQuestionModel.defaultPutts
    @State var entryDraft = HandScoreDraft(strokes: 4, putts: PuttsQuestionModel.defaultPutts)
    /// Casual score grid picks (Finish on the live hole, or a hole being edited).
    @State var scoreDraft = ScoreGridDraft.empty
    /// Casual "Your round": every scored hole, newest first.
    @State var roundSoFar = RoundSoFar.empty
    @State var toast: RoundToast?
    @State var trail: [CLLocationCoordinate2D] = []
    @State var chromeFrames: [String: CGRect] = [:]
    /// The map's frame in `ChromeFrames.space` (anchors `chromeFrames`);
    /// `ChromeFrames.mapFrame` of the screen's size and safe area.
    @State var mapFrame: CGRect = .zero
    /// The safe area in `ChromeFrames.space` (the screen's own frame).
    @State var safeRect: CGRect?
    @State var roundScoreText: String?
    @State var roundToPar: String?
    @State var isMarking = false
    /// Bumped every few seconds so the yardage re-reads the latest fix.
    @State var fixTick = 0

    static let slowTick = Timer.publish(every: 3, on: .main, in: .common).autoconnect()
    /// 5 × 3 s: the trail refreshes every 15 s.
    static let trailEveryNTicks = 5

    var body: some View {
        let layout = RoundMapLayout.resolve(display)
        let model = panelModel(layout: layout)
        let actions = panelActions()
        GeometryReader { proxy in
            let insets = RoundChromeInsets.make(safeArea: proxy.safeAreaInsets)
            ZStack(alignment: .topLeading) {
                holeMap
                    .ignoresSafeArea()
                chrome(layout: layout, model: model, actions: actions, insets: insets)
                    .ignoresSafeArea()
                if let toast {
                    RoundToastView(toast: toast)
                        .padding(.top, insets.top + 68 + (layout.asksInBottomSheet ? 52 : 0))
                        .padding(.leading, insets.leading)
                        .ignoresSafeArea()
                        .transition(.opacity)
                }
            }
            .coordinateSpace(.named(ChromeFrames.space))
            .onChange(of: ScreenGeometry(size: proxy.size, safeArea: proxy.safeAreaInsets), initial: true) { _, screen in
                safeRect = CGRect(origin: .zero, size: screen.size)
                mapFrame = ChromeFrames.mapFrame(size: screen.size, safeArea: screen.safeArea)
            }
        }
        .environment(\.chromeFrameSink, ChromeFrameSink { id, frame in noteChromeFrame(id, frame) })
        #if DEBUG
        .overlay(alignment: .topLeading) {
            if DebugPostureSwitch.shared.controlsEnabled {
                DebugRoundProbe(holeNumber: holeNumber, roundID: roundID, stage: layout)
            }
        }
        #endif
        .onAppear(perform: setUp)
        .onDisappear { session?.close() }
        .onChange(of: sessionKey) { _, _ in syncSession() }
        .onChange(of: display) { _, next in autoHide?.update(display: next) }
        .onChange(of: desiredPauseReasons) { _, reasons in applyPauseReasons(reasons) }
        .onChange(of: live?.mostRecentlyConfirmedHoleFromGlasses?.id) { _, id in
            guard id != nil else { return }
            noteGlassesFinish()
        }
        .onReceive(Self.slowTick) { _ in
            fixTick &+= 1
            if fixTick % Self.trailEveryNTicks == 0 { reloadTrail() }
        }
        .task(id: toast) {
            guard let current = toast else { return }
            try? await Task.sleep(for: .seconds(current.kind == .tip ? 7 : 3))
            guard !Task.isCancelled, toast == current else { return }
            withAnimation { toast = nil }
        }
    }

    // MARK: Map

    private var holeMap: some View {
        let shots = session?.shots ?? []
        let onCourse = isShowingCourse
        return HoleMap(
            mode: mapMode,
            controller: mapController,
            holeID: onCourse ? nil : session?.hole?.id,
            tee: onCourse ? nil
                : GlassesStateMapper.teeCoordinate(courseId: curatedCourseId, holeNumber: holeNumber),
            green: onCourse ? nil
                : GlassesStateMapper.greenCoordinate(courseId: curatedCourseId, holeNumber: holeNumber),
            shots: shots,
            clubLabels: Self.clubLabels(for: shots),
            selectedShotID: selectedShotID,
            trail: trail,
            courseHoles: course?.content.outlines ?? [],
            unobstructedRect: ChromeFrames.unobstructedRect(display: display, frames: chromeFrames,
                                                            mapFrame: mapFrame, safeRect: safeRect),
            onMoveShot: { id, coordinate in moveShot(id, to: coordinate) },
            onLongPress: { coordinate in holdToAdd(at: coordinate) },
            onSelectShot: { id in toggleSelection(id) },
            onTapMap: { autoHide?.tapMap() },
            onSelectHole: { number in openCourseHole(number) },
            onDragChanged: { dragging in isDragging = dragging }
        )
        .accessibilityIdentifier(InRoundAccessibilityID.map)
    }

    static func clubLabels(for shots: [Shot]) -> [UUID: String] {
        var labels: [UUID: String] = [:]
        for shot in shots {
            if let name = ClubCatalog.shared.shortName(id: shot.club) { labels[shot.id] = name }
        }
        return labels
    }

    // MARK: Chrome

    @ViewBuilder
    private func chrome(layout: RoundMapLayout, model: RoundPanelModel, actions: RoundPanelActions,
                        insets: EdgeInsets) -> some View {
        if let course, course.isShowing {
            courseChrome(course, layout: layout, insets: insets)
        } else if model.controlsVisible {
            Group {
                switch layout {
                case .openWide:
                    OpenWideLayout(model: model, actions: actions, insets: insets)
                case .openPortrait:
                    OpenPortraitLayout(model: model, actions: actions, insets: insets,
                                       windowSize: display.windowSize)
                case .book:
                    BookLayout(model: model, actions: actions, insets: insets, windowSize: display.windowSize)
                case .folded:
                    FoldedLayout(model: model, actions: actions, insets: insets)
                case .phonePortrait:
                    PhonePortraitLayout(model: model, actions: actions, insets: insets)
                case .phoneLandscape:
                    PhoneLandscapeLayout(model: model, actions: actions, insets: insets)
                }
            }
            .simultaneousGesture(TapGesture().onEnded { actions.noteInteraction() })
            .transition(.opacity)
        } else if layout.asksInBottomSheet {
            CompactHiddenChrome(model: model, actions: actions, insets: insets)
        } else {
            OpenHiddenChrome(model: model, actions: actions, insets: insets)
        }
    }

    private func noteChromeFrame(_ id: String, _ frame: CGRect?) {
        guard chromeFrames[id] != frame else { return }
        var next = chromeFrames
        next[id] = frame
        chromeFrames = next
    }

    // MARK: Hole on screen

    var liveHoleNumber: Int? { live?.currentHole?.holeNumber }

    var holeNumber: Int { viewedHole ?? liveHoleNumber ?? HoleScoring.holeRange.lowerBound }

    var isViewingLive: Bool {
        guard let live = liveHoleNumber else { return false }
        return session?.isLive ?? (holeNumber == live)
    }

    var units: Units { Units(rawValue: unitsRaw) ?? .yards }

    /// A change re-creates the session (another hole, or the live hole moved on).
    private var sessionKey: String {
        "\(roundID.uuidString)|\(holeNumber)|\(live?.currentHole?.id.uuidString ?? "-")|\(isShowingCourse)"
    }

    var desiredPauseReasons: Set<AutoHidePauseReason> {
        let state = session.map { panelState(for: $0) } ?? .live
        return AutoHideWiring.pauseReasons(questionOpen: question != nil, entryOpen: state == .entry,
                                           shotSelected: selectedShotID != nil, dragging: isDragging,
                                           modeAllowsAutoHide: mode.allowsAutoHide)
    }

    private func setUp() {
        if autoHide == nil {
            autoHide = AutoHideController(display: display, policyOverride: AutoHidePolicy.launchOverride)
        }
        autoHide?.update(display: display)
        syncSession()
        applyPauseReasons(desiredPauseReasons)
    }

    private func applyPauseReasons(_ reasons: Set<AutoHidePauseReason>) {
        guard let autoHide else { return }
        AutoHideWiring.apply(reasons, to: autoHide)
    }

    /// Opens a session for the hole on screen (closing the previous one).
    func syncSession() {
        guard !isShowingCourse else {
            // The course pose has no hole on screen.
            session?.close()
            session = nil
            selectedShotID = nil
            isDragging = false
            trail = []
            return
        }
        let isFirst = session == nil
        session?.close()
        let next = HoleSession(roundID: roundID, holeNumber: holeNumber, live: live,
                               anchors: .resolve(courseId: curatedCourseId, holeNumber: holeNumber))
        next.open()
        session = next
        selectedShotID = nil
        isDragging = false
        if !isFirst { question = nil }
        entryDraft = HandScoreDraft.initial(hole: next.hole, par: next.par)
        scoreDraft = ScoreGridDraft.initial(hole: next.hole)
        trail = []
        reloadTrail()
        refreshRoundScore()
    }

    func reloadTrail() {
        guard let holeID = session?.hole?.id else {
            trail = []
            return
        }
        HoleTrailSource.load(forHoleID: holeID) { coords in
            guard session?.hole?.id == holeID else { return } // a late result for a hole we left
            trail = coords
        }
    }

    /// "+1 · 2 SCORED" and the casual round so far, from the stored holes:
    /// finished and hand-scored holes.
    func refreshRoundScore() {
        guard let holes = try? HoleRepository.holesForRound(roundID) else {
            roundScoreText = nil
            roundToPar = nil
            roundSoFar = .empty
            return
        }
        let scored: [(hole: Hole, score: Int?, putts: Int?)] = holes.map { hole in
            let counts = hole.confirmedAt != nil || (hole.isHandScored && hole.handStrokes != nil)
            guard counts else { return (hole: hole, score: nil, putts: nil) }
            let shots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
            let penalties = (try? PenaltyRepository.penaltiesForHole(hole.id)) ?? []
            return (hole: hole,
                    score: HoleScoring.score(hole: hole, shots: shots, penaltyStrokes: penalties.totalStrokes),
                    putts: HoleScoring.putts(hole: hole, shots: shots))
        }
        let rows: [(par: Int?, score: Int?)] = scored.map { (par: $0.hole.par, score: $0.score) }
        if mode == .review, let date = host.roundDate {
            roundScoreText = ReviewText.roundText(dateText: ReviewText.dateText(date), holes: rows)
        } else {
            roundScoreText = RoundMapFormat.roundScoreText(holes: rows)
        }
        roundToPar = RoundMapFormat.roundToPar(holes: rows)
        let inputs: [RoundScoreInput] = scored.compactMap { entry in
            entry.score.map { RoundScoreInput(holeNumber: entry.hole.holeNumber, par: entry.hole.par,
                                              strokes: $0, putts: entry.putts) }
        }
        roundSoFar = RoundSoFar.build(scores: inputs, startingHole: session?.startingHole,
                                      onScreen: holeNumber, live: liveHoleNumber)
    }
}

/// The round screen's size and safe area, which place the full-bleed map.
private struct ScreenGeometry: Equatable {
    let size: CGSize
    let safeArea: EdgeInsets
}
