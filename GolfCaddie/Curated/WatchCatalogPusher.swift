import CryptoKit
import Foundation
import WatchConnectivity

/// Pushes the cached course catalog to the watch so the wrist can compute its
/// own yardages with the phone away (docs/WATCH_STANDALONE_SPIKE.md). In-app
/// captured local anchors ride along as separate overrides — they win over
/// curated on the phone (`GlassesStateMapper.greenCoordinate`), so the watch
/// must see the same greens, and keeping them apart lets the watch refresh the
/// public catalog directly without losing them.
///
/// Delivery is tracked, not assumed: a hash counts as delivered only when
/// `didFinish fileTransfer` reports success. A queued transfer is recognised
/// via `outstandingFileTransfers` (which survives relaunch), a failed one is
/// retried with backoff, and a watch that has never received a push (fresh
/// install / reinstall) asks for one — which INVALIDATES the delivered hash, so
/// the resend intent survives a failed transfer, every retry path and a phone
/// relaunch until a delivery is actually confirmed.
enum WatchCatalogPusher {
    private static let deliveredHashKey = "watchCatalogPusher.deliveredHash"
    private static let maxRetries = 5
    private static var retryAttempt = 0

    enum Decision: Equatable { case send, skip }

    /// What the phone believes the watch holds. Pure (unit-tested); persisted
    /// in UserDefaults by the accessors below.
    struct DeliveryState: Equatable {
        var deliveredHash: String?

        /// The watch says it has no phone push (fresh install / reinstall):
        /// whatever we delivered before is gone. Forgetting it — rather than
        /// forcing one send — keeps the resend pending across failures/retries.
        mutating func watchRequestedResend() { deliveredHash = nil }

        /// Only a confirmed delivery records the hash; a failure changes nothing.
        mutating func transferFinished(hash: String?, succeeded: Bool) {
            if succeeded, let hash { deliveredHash = hash }
        }

        func decide(hash: String, outstandingHashes: [String]) -> Decision {
            if outstandingHashes.contains(hash) { return .skip } // already queued
            if hash == deliveredHash { return .skip } // watch has it
            return .send
        }
    }

    private static var state: DeliveryState {
        get { DeliveryState(deliveredHash: UserDefaults.standard.string(forKey: deliveredHashKey)) }
        set { UserDefaults.standard.set(newValue.deliveredHash, forKey: deliveredHashKey) }
    }

    /// Safe from any context: hops through a plain GCD main-queue block so the
    /// synchronous GRDB reads are legal (see `allCoursesFromAsyncContext`).
    static func pushIfChanged() {
        DispatchQueue.main.async { push() }
    }

    /// The watch asked for the catalog (it has never received a push).
    static func watchRequestedResend() {
        DispatchQueue.main.async {
            state.watchRequestedResend()
            retryAttempt = 0
            push()
        }
    }

    /// `didFinish fileTransfer` for a catalog transfer.
    static func transferFinished(hash: String?, error: Error?) {
        DispatchQueue.main.async {
            state.transferFinished(hash: hash, succeeded: error == nil)
            if error == nil {
                retryAttempt = 0
                return
            }
            guard retryAttempt < maxRetries else { return } // next sync / activation / reachability retries
            retryAttempt += 1
            let delay = min(30 * pow(2, Double(retryAttempt - 1)), 600)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { push() }
        }
    }

    static func overrides(from anchors: [LocalCourseAnchor]) -> [CourseAnchorOverride] {
        anchors.compactMap { a in
            guard a.tee != nil || a.green != nil else { return nil }
            return CourseAnchorOverride(courseId: a.courseId, holeNumber: a.holeNumber, tee: a.tee, green: a.green)
        }
    }

    private static func push() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isWatchAppInstalled else { return }
        guard let courses = try? CourseDataRepository.allCourses(), !courses.isEmpty else { return }

        let sorted = courses.sorted { $0.id < $1.id }
        let anchors = sorted.flatMap { (try? LocalAnchorRepository.anchorsForCourse($0.id)) ?? [] }
        let payload = WatchCatalogPayload(
            catalog: CourseDataFile(schemaVersion: CuratedSchema.supportedVersion, courses: sorted),
            overrides: overrides(from: anchors)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys // stable bytes → stable hash
        guard let data = try? encoder.encode(payload) else { return }
        let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()

        let catalogTransfers = session.outstandingFileTransfers.filter {
            $0.file.metadata?[ShotContract.fileKindKey] as? String == ShotContract.courseCatalogKind
        }
        let outstandingHashes = catalogTransfers.compactMap { $0.file.metadata?[ShotContract.catalogHashKey] as? String }
        guard state.decide(hash: hash, outstandingHashes: outstandingHashes) == .send else { return }

        // Anything still queued is now superseded.
        catalogTransfers.forEach { $0.cancel() }

        let url = FileManager.default.temporaryDirectory.appendingPathComponent("watch-catalog-\(hash.prefix(12)).json")
        guard (try? data.write(to: url, options: .atomic)) != nil else { return }
        session.transferFile(url, metadata: [
            ShotContract.fileKindKey: ShotContract.courseCatalogKind,
            ShotContract.catalogHashKey: hash,
        ])
    }
}
