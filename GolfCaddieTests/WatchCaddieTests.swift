import CoreLocation
@testable import GolfCaddie
import XCTest

/// The on-wrist yardage model (compiled into the watch; tested here because
/// the watch has no test target). Clock + expiry scheduler are injected.
@MainActor
final class WatchCaddieTests: XCTestCase {
    /// Hand-cranked stand-in for the sleeping-Task scheduler.
    private final class ManualScheduler {
        private(set) var pending: [(delay: TimeInterval, fire: @MainActor () -> Void)] = []
        private(set) var cancelled = 0

        func schedule(_ delay: TimeInterval, _ fire: @escaping @MainActor () -> Void) -> () -> Void {
            pending.append((delay, fire))
            return { [weak self] in self?.cancelled += 1 }
        }

        @MainActor func fireNext() {
            guard !pending.isEmpty else { return XCTFail("nothing scheduled") }
            pending.removeFirst().fire()
        }
    }

    private var clock = Date(timeIntervalSince1970: 1_000_000)
    private let scheduler = ManualScheduler()

    private let course = CuratedCourse(
        id: "c", name: "Course", aliases: [], location: GeoPoint(lat: 33.0, lng: -117.0),
        holes: [
            CuratedHole(number: 1, par: 4, yards: nil, strokeIndex: nil, teeAnchor: nil,
                        greenAnchor: GeoPoint(lat: 33.001, lng: -117.0)), // ~121 yd north
            CuratedHole(number: 2, par: 3, yards: nil, strokeIndex: nil, teeAnchor: nil,
                        greenAnchor: GeoPoint(lat: 33.002, lng: -117.0)), // ~243 yd north
        ]
    )

    private func makeCaddie() -> WatchCaddie {
        let caddie = WatchCaddie(
            staleAfter: 20,
            now: { [unowned self] in self.clock },
            scheduleExpiry: { [scheduler] delay, fire in scheduler.schedule(delay, fire) }
        )
        caddie.update(courses: [course])
        return caddie
    }

    private func fix(accuracy: CLLocationAccuracy = 5) -> CLLocation {
        CLLocation(coordinate: .init(latitude: 33.0, longitude: -117.0), altitude: 0,
                   horizontalAccuracy: accuracy, verticalAccuracy: 5, timestamp: clock)
    }

    /// The review case: a valid fix, then NOTHING — no further fixes, no phone
    /// state, no redraw. The expiry alone must clear the published yardage.
    func testYardageClearsWhenFixAgesOutWithNoFurtherFixes() throws {
        let caddie = makeCaddie()
        caddie.ingest(fix())
        XCTAssertEqual(Double(try XCTUnwrap(caddie.localYards)), 121, accuracy: 2)
        XCTAssertEqual(scheduler.pending.map(\.delay), [20])

        var published: [Int?] = []
        let sub = caddie.$localYards.dropFirst().sink { published.append($0) }
        defer { sub.cancel() }

        clock += 21
        scheduler.fireNext()

        XCTAssertNil(caddie.localYards)
        XCTAssertEqual(published.count, 1, "observers are told, so the screen falls back / clears")
        XCTAssertNil(published[0])
        XCTAssertEqual(caddie.course?.id, "c", "the resolved course stays sticky")
        XCTAssertTrue(scheduler.pending.isEmpty, "nothing left armed")
    }

    func testExpiryRearmsForTheRemainderWhenNewerFixesArrived() {
        let caddie = makeCaddie()
        caddie.ingest(fix())
        clock += 15
        caddie.ingest(fix())
        XCTAssertEqual(scheduler.pending.count, 1, "1 Hz fixes don't stack timers")

        clock += 5 // t+20: first expiry fires, but the newest fix is only 5 s old
        scheduler.fireNext()
        XCTAssertNotNil(caddie.localYards)
        XCTAssertEqual(scheduler.pending.map(\.delay), [15])

        clock += 15
        scheduler.fireNext()
        XCTAssertNil(caddie.localYards)
    }

    func testFreshFixAfterExpiryRestoresYardage() {
        let caddie = makeCaddie()
        caddie.ingest(fix())
        clock += 25
        scheduler.fireNext()
        XCTAssertNil(caddie.localYards)
        caddie.ingest(fix())
        XCTAssertNotNil(caddie.localYards)
        XCTAssertEqual(scheduler.pending.count, 1)
    }

    func testPoorFixIsIgnored() {
        let caddie = makeCaddie()
        caddie.ingest(fix(accuracy: 80))
        caddie.ingest(fix(accuracy: -1))
        XCTAssertNil(caddie.localYards)
        XCTAssertTrue(scheduler.pending.isEmpty)
    }

    func testHoleFollowsPhoneRoundElseWatchOnlyStepper() throws {
        let caddie = makeCaddie()
        caddie.ingest(fix())
        caddie.stepHole(by: 1)
        XCTAssertEqual(caddie.holeNumber, 2)
        XCTAssertEqual(Double(try XCTUnwrap(caddie.localYards)), 243, accuracy: 3)
        caddie.stepHole(by: 1)
        XCTAssertEqual(caddie.holeNumber, 1, "wraps at the course's hole count")

        var phone = PhoneStateUpdate.inactive
        phone.isActive = true
        phone.holeNumber = 2
        phone.curatedCourseId = "c"
        caddie.update(phoneState: phone)
        XCTAssertEqual(caddie.holeNumber, 2, "an active phone round owns the hole")
        XCTAssertEqual(Double(try XCTUnwrap(caddie.localYards)), 243, accuracy: 3)
    }

    func testResetCancelsExpiryAndClears() {
        let caddie = makeCaddie()
        caddie.ingest(fix())
        caddie.reset()
        XCTAssertNil(caddie.localYards)
        XCTAssertEqual(scheduler.cancelled, 1)
    }
}
