import CoreLocation
import Foundation

/// SwingEvent conforms to the reconciler's ordering protocol via its watch
/// wall-clock timestamp.
extension SwingEvent: TimedCandidate {
    var candidateTime: Date { Date(timeIntervalSince1970: watchWallClock) }
}

/// Bounded FIFO set of recently-seen ids — the phone's at-most-once guard for
/// watch→phone commands (B2). `insert(_:)` returns `true` the first time an id
/// is seen (apply it) and `false` on any repeat (a duplicate to ignore). Only
/// the last `capacity` ids are retained: a command older than that can't
/// realistically still be in flight for redelivery, so the set never grows
/// unbounded. Pure value type → unit-testable without the coordinator.
struct RecentIDSet: Equatable {
    private var order: [UUID] = []
    private var seen: Set<UUID> = []
    let capacity: Int

    init(capacity: Int = 64) { self.capacity = max(1, capacity) }

    /// Record `id`. Returns true if newly inserted, false if already present.
    mutating func insert(_ id: UUID) -> Bool {
        guard !seen.contains(id) else { return false }
        seen.insert(id)
        order.append(id)
        if order.count > capacity {
            seen.remove(order.removeFirst())
        }
        return true
    }

    func contains(_ id: UUID) -> Bool { seen.contains(id) }
}

/// Bridge between the phone's WCSession delegate and the RoundController for
/// live auto-logging. Owns the debounce + reconciliation + fusion pipeline:
///
///   swing event → buffer (debounce ~3 s) → ShotReconciler (step-gated collapse)
///     → fuse each kept event to a breadcrumb coordinate → RoundController.ingestAutoShot
///
/// Commands (add/remove/putt/club) route immediately when nothing is in flight,
/// and in arrival order behind it otherwise (see "Ordered intake"). Events that arrive before
/// the controller is attached (the WC delegate activates in GolfCaddieApp.init,
/// before RootView builds the controller) are buffered and drained on attach.
@MainActor
final class LiveShotCoordinator {
    static let shared = LiveShotCoordinator()

    private weak var controller: RoundController?
    private weak var location: LocationManager?
    private let reconciler: ShotReconciler

    private var pending: [SwingEvent] = []
    private var bufferedBeforeAttach: [WatchToPhoneMessage] = []
    private var debounce: Timer?
    private let debounceInterval: TimeInterval
    private let now: () -> Date

    /// A swing/tap within this of "now" is live; older means it was queued and
    /// delivered late.
    static let liveWindow: TimeInterval = 30

    init(steps: StepCounting = PedometerStepCounter(), debounceInterval: TimeInterval = 3.0,
         now: @escaping () -> Date = Date.init) {
        reconciler = ShotReconciler(steps: steps)
        self.debounceInterval = debounceInterval
        self.now = now
    }

    /// Command ids already applied — so an at-least-once redelivery (retried
    /// `transferUserInfo`) or a duplicated send applies its effect only once (B2).
    private var appliedCommandIDs = RecentIDSet()

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

    /// Entry point from the WCSession delegate (any thread → main). GCD's main
    /// queue, not a Task per message: delivery order must be preserved, and
    /// separate unstructured Tasks don't promise FIFO.
    nonisolated func receive(_ message: WatchToPhoneMessage) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.ingest(message) }
        }
    }

    // MARK: - Ordered intake
    //
    // Live, messages trickle in seconds apart and the order barely matters. But
    // `transferUserInfo` queues while the phone is unreachable, and on reconnect
    // holes' worth of traffic lands within seconds. Swings sit in the debounce
    // buffer (the reconciler needs the whole burst) while commands used to apply
    // immediately — so every queued "Next Hole" ran first and all the swings
    // were then logged to the LAST hole. Rules now:
    //   - a hole-changing command first flushes the pending swings, so they
    //     commit to the hole they were played on;
    //   - while a commit (async: pedometer step-gate) is in flight or work is
    //     queued, later commands wait their turn behind it;
    //   - with nothing pending and nothing in flight — the live case — a command
    //     still applies synchronously, exactly as before.

    private enum Work {
        case commit([SwingEvent])
        case command(IdentifiedCommand)
    }

    private var queue: [Work] = []
    private var draining = false

    func ingest(_ message: WatchToPhoneMessage) {
        guard controller != nil else { bufferedBeforeAttach.append(message); return }
        switch message.kind {
        case .swing:
            guard let event = message.swing else { return }
            pending.append(event)
            restartDebounce()
        case .command:
            guard let identified = message.command else { return }
            // Apply at most once: ignore a command id we've already handled.
            guard appliedCommandIDs.insert(identified.id) else { return }
            if identified.command.changesHole, !pending.isEmpty { flushPending() }
            if draining || !queue.isEmpty {
                queue.append(.command(identified))
                drain()
            } else {
                handle(identified)
            }
        }
    }

    /// Awaitable idle point for tests: everything received so far is applied.
    func waitUntilIdle() async {
        while draining || !queue.isEmpty {
            try? await Task.sleep(nanoseconds: 5_000_000)
        }
    }

    private func flushPending() {
        debounce?.invalidate()
        debounce = nil
        let batch = pending
        pending = []
        guard !batch.isEmpty else { return }
        queue.append(.commit(batch))
        drain()
    }

    private func drain() {
        guard !draining, !queue.isEmpty else { return }
        draining = true
        Task { @MainActor in
            while !queue.isEmpty {
                switch queue.removeFirst() {
                case let .commit(batch): await commit(batch)
                case let .command(identified): handle(identified)
                }
            }
            draining = false
        }
    }

    private func handle(_ identified: IdentifiedCommand) {
        switch identified.command {
        case let .addShot(clubShortName):
            if let short = clubShortName,
               let club = (try? ClubRepository.from(shortName: short)) ?? nil {
                controller?.setCurrentClub(club)
            }
            try? controller?.addShotFromWatch(late: lateTap(identified))
        case let .removeStroke(id):
            if let id, let uuid = UUID(uuidString: id) {
                try? controller?.removeShot(id: uuid)
            } else {
                try? controller?.undoLastAction()
            }
        case let .editStrokeClub(id, clubShortName):
            guard let uuid = UUID(uuidString: id) else { break }
            if let short = clubShortName {
                // Unknown short (mismatched builds) must NOT clear the club —
                // drop the edit, same posture as addShot's unknown-club skip.
                guard let club = (try? ClubRepository.from(shortName: short)) ?? nil else { break }
                try? controller?.updateShotClub(id: uuid, club: club)
            } else {
                try? controller?.updateShotClub(id: uuid, club: nil)
            }
        case .puttPlusOne:
            try? controller?.addPuttFromWatch(late: lateTap(identified))
        case let .clubChange(shortName, epoch):
            lastWatchClubEpoch = max(lastWatchClubEpoch, epoch)
            try? controller?.setCurrentClubFromGlasses(shortName: shortName)
        case .advanceHole:
            // Confirm the current hole (keeping its par) and advance — mirrors
            // the glasses advance and the phone "Next" button.
            if let hole = controller?.currentHole {
                try? controller?.confirmHoleAndAdvance(par: hole.par)
            }
        case .previousHole:
            controller?.stepHole(by: -1)
        case let .finishHole(putts, score):
            let tapped = identified.sentAt.map(Date.init(timeIntervalSince1970:)) ?? now()
            _ = try? controller?.finishHole(putts: putts, score: score, at: tapped)
        case let .addPenalty(kind):
            // Unknown kind (mismatched builds) still costs a stroke — "other".
            let type = PenaltyType(rawValue: kind) ?? .other
            let tapped = identified.sentAt.map(Date.init(timeIntervalSince1970:)) ?? now()
            try? controller?.addPenaltyToCurrentHole(type: type, at: tapped)
        }
    }

    /// A MARK/putt tap older than this was delivered late (queued while the phone
    /// was away): stamp it with the watch's tap time and the breadcrumb from
    /// then, not "now" and wherever the phone is holes later. nil = live.
    private func lateTap(_ identified: IdentifiedCommand) -> RoundController.LateWatchTap? {
        guard let sentAt = identified.sentAt else { return nil }
        let tapped = Date(timeIntervalSince1970: sentAt)
        guard now().timeIntervalSince(tapped) > Self.liveWindow else { return nil }
        let (coordinate, accuracy) = breadcrumb(near: tapped)
        return .init(timestamp: tapped, coordinate: coordinate, accuracy: accuracy)
    }

    private func restartDebounce() {
        debounce?.invalidate()
        debounce = Timer.scheduledTimer(withTimeInterval: debounceInterval, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.flushPending() }
        }
    }

    private func commit(_ batch: [SwingEvent]) async {
        let kept = await reconciler.commit(batch)
        for event in kept {
            let (coordinate, accuracy) = fuse(event)
            _ = try? controller?.ingestAutoShot(
                at: coordinate,
                accuracy: accuracy,
                club: event.club.flatMap { (try? ClubRepository.from(shortName: $0)) ?? nil },
                timestamp: event.candidateTime
            )
        }
    }

    /// Match the swing's timestamp to the nearest breadcrumb (the user is
    /// stationary at address, so this is the strike location even with seconds
    /// of clock drift). Fall back to the latest live fix — but only for a swing
    /// that just happened; for a late-delivered one the phone's current position
    /// is somewhere else entirely, so no-GPS is the honest answer.
    private func fuse(_ event: SwingEvent) -> (CLLocationCoordinate2D?, Double?) {
        let target = event.candidateTime
        let crumb = breadcrumb(near: target)
        if crumb.0 != nil { return crumb }
        if now().timeIntervalSince(target) <= Self.liveWindow,
           let loc = location?.latestLocation, loc.horizontalAccuracy > 0 {
            return (loc.coordinate, loc.horizontalAccuracy)
        }
        return (nil, nil)
    }

    private func breadcrumb(near target: Date) -> (CLLocationCoordinate2D?, Double?) {
        guard let roundID = controller?.currentRound?.id,
              let breadcrumb = try? TracePointRepository.nearest(toTimestamp: target, inRound: roundID),
              abs(breadcrumb.timestamp.timeIntervalSince(target)) <= 10 else { return (nil, nil) }
        return (CLLocationCoordinate2D(latitude: breadcrumb.latitude, longitude: breadcrumb.longitude),
                breadcrumb.accuracy)
    }
}

private extension WatchCommand {
    /// Commands after which a swing would land on a different hole.
    var changesHole: Bool {
        switch self {
        case .advanceHole, .previousHole, .finishHole: return true
        case .addShot, .removeStroke, .editStrokeClub, .puttPlusOne, .clubChange, .addPenalty: return false
        }
    }
}
