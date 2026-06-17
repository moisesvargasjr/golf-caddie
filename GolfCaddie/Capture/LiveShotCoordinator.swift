import CoreLocation
import Foundation

/// SwingEvent conforms to the reconciler's ordering protocol via its watch
/// wall-clock timestamp.
extension SwingEvent: TimedCandidate {
    var candidateTime: Date { Date(timeIntervalSince1970: watchWallClock) }
}

/// Bridge between the phone's WCSession delegate and the RoundController for
/// live auto-logging. Owns the debounce + reconciliation + fusion pipeline:
///
///   swing event → buffer (debounce ~3 s) → ShotReconciler (step-gated collapse)
///     → fuse each kept event to a breadcrumb coordinate → RoundController.ingestAutoShot
///
/// Commands (add/remove/putt/club) route immediately. Events that arrive before
/// the controller is attached (the WC delegate activates in GolfCaddieApp.init,
/// before RootView builds the controller) are buffered and drained on attach.
@MainActor
final class LiveShotCoordinator {
    static let shared = LiveShotCoordinator()

    private weak var controller: RoundController?
    private weak var location: LocationManager?
    private let reconciler = ShotReconciler(steps: PedometerStepCounter())

    private var pending: [SwingEvent] = []
    private var bufferedBeforeAttach: [WatchToPhoneMessage] = []
    private var debounce: Timer?
    private let debounceInterval: TimeInterval = 3.0

    /// Most recent club epoch seen from the watch — M6's StateUpdate publisher
    /// reads this so the phone never echoes a stale epoch back.
    private(set) var lastWatchClubEpoch = 0

    /// Prompt for Core Motion (step) access at round start, before the first
    /// real query needs it mid-round.
    func warmUpStepCounter() {
        reconciler.steps.requestAuthorization()
    }

    func attach(controller: RoundController, location: LocationManager) {
        self.controller = controller
        self.location = location
        let backlog = bufferedBeforeAttach
        bufferedBeforeAttach = []
        for message in backlog { ingest(message) }
    }

    /// Entry point from the WCSession delegate (any thread → hops to main).
    nonisolated func receive(_ message: WatchToPhoneMessage) {
        Task { @MainActor in self.ingest(message) }
    }

    func ingest(_ message: WatchToPhoneMessage) {
        guard controller != nil else { bufferedBeforeAttach.append(message); return }
        switch message.kind {
        case .swing:
            guard let event = message.swing else { return }
            pending.append(event)
            restartDebounce()
        case .command:
            guard let command = message.command else { return }
            handle(command)
        }
    }

    private func handle(_ command: WatchCommand) {
        switch command {
        case let .addShot(clubShortName):
            if let short = clubShortName, let club = ClubID.from(shortName: short) {
                controller?.setCurrentClub(club)
            }
            try? controller?.addShotFromWatch()
        case let .removeStroke(id):
            if let id, let uuid = UUID(uuidString: id) {
                try? controller?.removeShot(id: uuid)
            } else {
                try? controller?.undoLastAction()
            }
        case .puttPlusOne:
            try? controller?.addPuttFromWatch()
        case let .clubChange(shortName, epoch):
            lastWatchClubEpoch = max(lastWatchClubEpoch, epoch)
            try? controller?.setCurrentClubFromGlasses(shortName: shortName)
        }
    }

    private func restartDebounce() {
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.commitPending() }
        }
    }

    private func commitPending() {
        let batch = pending
        pending = []
        guard !batch.isEmpty else { return }
        Task { @MainActor in
            let kept = await reconciler.commit(batch)
            for event in kept {
                let (coordinate, accuracy) = fuse(event)
                try? controller?.ingestAutoShot(
                    at: coordinate,
                    accuracy: accuracy,
                    club: event.club.flatMap(ClubID.from(shortName:)),
                    timestamp: event.candidateTime
                )
            }
        }
    }

    /// Match the swing's timestamp to the nearest breadcrumb (the user is
    /// stationary at address, so this is the strike location even with seconds
    /// of clock drift). Fall back to the latest live fix, then to no-GPS.
    private func fuse(_ event: SwingEvent) -> (CLLocationCoordinate2D?, Double?) {
        let target = event.candidateTime
        if let roundID = controller?.currentRound?.id,
           let breadcrumb = try? TracePointRepository.nearest(toTimestamp: target, inRound: roundID),
           abs(breadcrumb.timestamp.timeIntervalSince(target)) <= 10 {
            return (CLLocationCoordinate2D(latitude: breadcrumb.latitude, longitude: breadcrumb.longitude),
                    breadcrumb.accuracy)
        }
        if let loc = location?.latestLocation, loc.horizontalAccuracy > 0 {
            return (loc.coordinate, loc.horizontalAccuracy)
        }
        return (nil, nil)
    }
}
