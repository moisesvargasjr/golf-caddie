import SwiftUI
import WatchConnectivity

/// Home / landing screen — "The Fairway Logbook".
///
/// Shown when no round is active. Owns Home's state (the Start a round pick,
/// clubs in play, the logbook snapshot, watch status) and its sheets; the
/// arrangement comes from `HomeLayout`:
/// - open Duo held wide → `HomeOpenLayout` (two pages around the hinge);
/// - everything else → `HomeSingleLayout` (the folded design).
struct HomeView: View {
    @Binding var bag: [Club]
    /// Begin: starting hole, clubs left out, mode and course.
    let onStartRound: (HomeStartRequest) -> Void
    let actionError: String?

    /// The Settings "Casual by default" toggle (same key as `RoundController`).
    static let casualDefaultKey = "roundModeDefaultCasual"
    private static let watchPollInterval: Duration = .seconds(3)

    @Environment(\.displayContext) private var display
    @AppStorage("glassesServerEnabled") private var glassesEnabled = false
    @AppStorage(HomeView.casualDefaultKey) private var casualDefault = false

    @State private var startState = HomeStartState(
        mode: .initial(casualDefault: UserDefaults.standard.bool(forKey: HomeView.casualDefaultKey))
    )
    @State private var clubsLeftOut: [String] =
        UserDefaults.standard.stringArray(forKey: ClubsInPlay.leftOutDefaultsKey) ?? []
    @State private var snapshot = HomeData.Snapshot.empty
    @State private var loadError: String?
    @State private var courses: [CuratedCourse] = []
    @State private var courseNames: [String: String] = [:]
    @State private var watch: WatchLinkStatus = .unavailable
    @State private var bagPanelOpen = false
    @State private var showClubsInPlay = false
    @State private var showBagEditor = false
    @State private var showCoursePicker = false
    #if DEBUG
    @State private var debugShowLogbook = false
    @State private var debugShowSettings = false
    @State private var debugRoundCard: Round?
    #endif

    private var layout: HomeLayout { HomeLayout.resolve(display) }

    var body: some View {
        ZStack {
            PaperBackground().ignoresSafeArea()
            switch layout {
            case .openWide:
                HomeOpenLayout(content: content, actions: actions, bag: $bag,
                               startState: $startState, clubsLeftOut: $clubsLeftOut,
                               bagPanelOpen: $bagPanelOpen)
            case .single:
                HomeSingleLayout(content: content, actions: actions, bag: $bag,
                                 startState: $startState)
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier(HomeID.root)
        .toolbar(.hidden, for: .navigationBar)
        .sheet(isPresented: $showBagEditor) {
            BagSetupView(initialBag: bag, onCancel: { showBagEditor = false }) { saved in
                bag = saved
                showBagEditor = false
            }
        }
        .sheet(isPresented: $showClubsInPlay) {
            ClubsInPlaySheet(bag: bag, leftOut: $clubsLeftOut, onDone: { showClubsInPlay = false })
        }
        .sheet(isPresented: $showCoursePicker) { coursePicker }
        .onChange(of: clubsLeftOut) { _, new in
            UserDefaults.standard.set(new, forKey: ClubsInPlay.leftOutDefaultsKey)
        }
        // Keep the remembered pick honest against the bag: deleted clubs and
        // picks the putter / full-shot rules override drop off, so the
        // checkmarks match the "N of M" count.
        .onChange(of: bag) { _, _ in normalizeClubsLeftOut() }
        .onChange(of: casualDefault) { _, casual in
            startState = startState.with(mode: .initial(casualDefault: casual))
        }
        // The inline bag panel lives on the open Duo's left page; folding
        // carries it over to the sheet.
        .onChange(of: layout) { _, new in
            if new == .single, bagPanelOpen {
                bagPanelOpen = false
                showClubsInPlay = true
            }
        }
        .onAppear {
            refresh()
            normalizeClubsLeftOut()
            openDebugScreenIfRequested()
        }
        .task { await pollWatchStatus() }
        #if DEBUG
        .navigationDestination(isPresented: $debugShowLogbook) { RoundListView(bag: bag) }
        .navigationDestination(isPresented: $debugShowSettings) { SettingsView(bag: $bag) }
        // A finished round's card (PR 7 routes Logbook → card for real).
        .fullScreenCover(item: $debugRoundCard) { round in
            AdaptiveScorecardPresentation(
                round: round,
                currentHoleNumber: nil,
                curatedCourseId: round.curatedCourseId,
                onDismiss: { debugRoundCard = nil }
            )
        }
        #endif
    }

    // MARK: - Content and actions

    private var content: HomeContent {
        HomeContent(
            snapshot: snapshot,
            bag: bag,
            inPlayCount: ClubsInPlay.resolve(bag: bag, leftOut: clubsLeftOut).count,
            watch: watch,
            glassesEnabled: glassesEnabled,
            courseLabel: startState.courseLabel(names: courseNames),
            actionError: actionError,
            loadError: loadError
        )
    }

    private var actions: HomeActions {
        HomeActions(
            openBag: openBag,
            editBag: { showBagEditor = true },
            pickCourse: { showCoursePicker = true },
            begin: begin,
            refresh: refresh
        )
    }

    private func openBag() {
        if layout == .openWide {
            bagPanelOpen = true
        } else {
            showClubsInPlay = true
        }
    }

    private func begin() {
        let leftOut = ClubsInPlay.normalized(bag: bag, leftOut: clubsLeftOut)
        onStartRound(startState.request(clubsLeftOut: leftOut))
    }

    private var coursePicker: some View {
        CoursePickerSheet(
            courses: courses,
            current: startState.curatedCourseId,
            onPick: { id in
                startState = startState.with(courseId: id)
                showCoursePicker = false
            },
            onCancel: { showCoursePicker = false },
            onRefresh: {
                // B29: pull-to-refresh bypasses the hourly catalog throttle.
                await CourseSyncClient.shared.syncIfStale(force: true)
                let fresh = await CourseDataRepository.allCoursesFromAsyncContext()
                courses = fresh
                courseNames = Dictionary(fresh.map { ($0.id, $0.name) },
                                         uniquingKeysWith: { first, _ in first })
                return fresh
            }
        )
    }

    // MARK: - Data

    private func refresh() {
        do {
            snapshot = try HomeData.load()
            loadError = nil
        } catch {
            loadError = "Couldn't load rounds: \(error.localizedDescription)"
        }
        let catalog = HomeData.courseNames()
        courses = catalog.courses
        courseNames = catalog.names
    }

    private func normalizeClubsLeftOut() {
        // An empty bag means it hasn't loaded yet — don't wipe the pick.
        guard !bag.isEmpty else { return }
        let normalized = ClubsInPlay.normalized(bag: bag, leftOut: clubsLeftOut)
        if normalized != clubsLeftOut { clubsLeftOut = normalized }
    }

    private func pollWatchStatus() async {
        while !Task.isCancelled {
            let next = Self.readWatchStatus()
            if next != watch { watch = next }
            try? await Task.sleep(for: Self.watchPollInterval)
        }
    }

    private static func readWatchStatus() -> WatchLinkStatus {
        guard WCSession.isSupported() else { return .unavailable }
        let session = WCSession.default
        return WatchLinkStatus.resolve(isSupported: true,
                                       isActivated: session.activationState == .activated,
                                       isPaired: session.isPaired,
                                       isAppInstalled: session.isWatchAppInstalled,
                                       isReachable: session.isReachable)
    }

    /// `-DebugOpen home` lands here with nothing opened; `logbook`,
    /// `settings`, `bag` and `roundcard` (a finished round's card) open from Home.
    private func openDebugScreenIfRequested() {
        #if DEBUG
        switch DebugHarness.openScreen {
        case "logbook": debugShowLogbook = true
        case "settings": debugShowSettings = true
        case "bag": openBag()
        case "roundcard": debugRoundCard = DebugScorecardSeed.finishedRound()
        default: break
        }
        #endif
    }
}

#Preview {
    NavigationStack {
        HomeView(
            bag: .constant(ClubConfiguration.recommendedDefault.bag.compactMap { id in
                Club.seedCatalog.first { $0.id == id }
            }),
            onStartRound: { _ in },
            actionError: nil
        )
    }
    .themedRoot()
}
