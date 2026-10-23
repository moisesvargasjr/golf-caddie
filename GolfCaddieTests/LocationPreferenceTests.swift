@testable import GolfCaddie
import XCTest

/// B35: the watch's own GPS fix always wins over the phone's when usable, even
/// when the phone reports a better accuracy (the phone is often in the cart).
final class LocationPreferenceTests: XCTestCase {
    private let t = Date(timeIntervalSince1970: 1_800_000_000)
    // ~111 m per 0.001 degree of latitude.
    private let lat = 33.0
    private let lon = -117.0

    private func watch(lat: Double? = nil, acc: Double = 5, age: TimeInterval = 0) -> WatchFix {
        WatchFix(latitude: lat ?? self.lat, longitude: lon, horizontalAccuracy: acc,
                 timestamp: t.timeIntervalSince1970 - age)
    }

    private func phone(lat: Double? = nil, acc: Double = 5, age: TimeInterval = 0) -> GeoFix {
        GeoFix(latitude: lat ?? self.lat, longitude: lon, horizontalAccuracy: acc,
               timestamp: t.timeIntervalSince1970 - age)
    }

    func testUsableWatchFixWinsEvenWhenPhoneIsMoreAccurate() {
        let choice = LocationPreference.choose(
            watch: watch(lat: 33.0, acc: 12), phone: phone(lat: 33.001, acc: 3), at: t)
        XCTAssertEqual(choice.source, .watch)
        XCTAssertEqual(choice.fix?.latitude, 33.0)
        XCTAssertEqual(choice.fix?.horizontalAccuracy, 12)
    }

    func testDisagreementIsMetersBetweenTheTwoFixes() throws {
        let choice = LocationPreference.choose(
            watch: watch(lat: 33.0), phone: phone(lat: 33.001), at: t)
        let meters = try XCTUnwrap(choice.disagreementMeters)
        XCTAssertEqual(meters, 111.2, accuracy: 1.0)
    }

    func testAgreeingFixesReportZeroDisagreement() throws {
        let choice = LocationPreference.choose(watch: watch(), phone: phone(), at: t)
        XCTAssertEqual(try XCTUnwrap(choice.disagreementMeters), 0, accuracy: 0.01)
    }

    func testWatchAloneHasNoDisagreement() {
        let choice = LocationPreference.choose(watch: watch(), phone: nil, at: t)
        XCTAssertEqual(choice.source, .watch)
        XCTAssertNil(choice.disagreementMeters)
    }

    func testStaleWatchFallsBackToPhoneWithoutDisagreement() {
        let choice = LocationPreference.choose(watch: watch(age: 6), phone: phone(lat: 33.001), at: t)
        XCTAssertEqual(choice.source, .phone)
        XCTAssertEqual(choice.fix?.latitude, 33.001)
        XCTAssertNil(choice.disagreementMeters)
    }

    func testFutureDatedWatchFixBeyondWindowIsRejected() {
        let choice = LocationPreference.choose(watch: watch(age: -6), phone: phone(), at: t)
        XCTAssertEqual(choice.source, .phone)
    }

    func testInaccurateWatchFallsBackToPhone() {
        XCTAssertEqual(LocationPreference.choose(watch: watch(acc: 16), phone: phone(), at: t).source, .phone)
        XCTAssertEqual(LocationPreference.choose(watch: watch(acc: 0), phone: phone(), at: t).source, .phone)
        XCTAssertEqual(LocationPreference.choose(watch: watch(acc: -1), phone: phone(), at: t).source, .phone)
    }

    func testBoundariesAreInclusive() {
        XCTAssertEqual(LocationPreference.choose(watch: watch(acc: 15, age: 5), phone: nil, at: t).source, .watch)
        XCTAssertEqual(LocationPreference.choose(watch: watch(acc: 15.01), phone: nil, at: t).source, .none)
        XCTAssertEqual(LocationPreference.choose(watch: watch(age: 5.01), phone: nil, at: t).source, .none)
    }

    func testPhoneWithInvalidAccuracyIsNotUsed() {
        let choice = LocationPreference.choose(watch: nil, phone: phone(acc: -1), at: t)
        XCTAssertEqual(choice.source, .none)
        XCTAssertNil(choice.fix)
        XCTAssertEqual(LocationPreference.choose(watch: nil, phone: phone(acc: 0), at: t).source, .none)
    }

    func testInvalidPhoneDoesNotBlockWatchAndYieldsNoDisagreement() {
        let choice = LocationPreference.choose(watch: watch(), phone: phone(acc: -1), at: t)
        XCTAssertEqual(choice.source, .watch)
        XCTAssertNil(choice.disagreementMeters)
    }

    func testNothingUsableIsNone() {
        let choice = LocationPreference.choose(watch: nil, phone: nil, at: t)
        XCTAssertEqual(choice, LocationChoice(fix: nil, source: .none, disagreementMeters: nil))
    }

    func testPhoneFixIsNotAgeGated() {
        // Callers pre-select the phone fix (nearest breadcrumb / live); the
        // policy only requires a valid accuracy.
        XCTAssertEqual(LocationPreference.choose(watch: nil, phone: phone(age: 60), at: t).source, .phone)
    }

    func testStreamedFixesGetALooserAgeGateThanTimestampMatchedOnes() {
        XCTAssertEqual(LocationPreference.watchFixMaxAge, 5)
        XCTAssertEqual(LocationPreference.streamedWatchFixMaxAge, 10)
        let streamed = LocationPreference.streamedWatchFixMaxAge
        // 8 s old: stale for a swing/tap, still good for a phone-originated read.
        XCTAssertEqual(LocationPreference.choose(watch: watch(age: 8), phone: phone(), at: t).source, .phone)
        XCTAssertEqual(
            LocationPreference.choose(watch: watch(age: 8), phone: phone(), at: t, watchMaxAge: streamed).source,
            .watch)
        XCTAssertEqual(
            LocationPreference.choose(watch: watch(age: 10), phone: nil, at: t, watchMaxAge: streamed).source,
            .watch)
        XCTAssertEqual(
            LocationPreference.choose(watch: watch(age: 10.5), phone: phone(), at: t, watchMaxAge: streamed).source,
            .phone)
    }

    func testLooserAgeStillRequiresAccuracy() {
        let streamed = LocationPreference.streamedWatchFixMaxAge
        XCTAssertEqual(
            LocationPreference.choose(watch: watch(acc: 20, age: 8), phone: phone(), at: t,
                                      watchMaxAge: streamed).source, .phone)
    }

    func testUsableWatchFixGate() {
        XCTAssertNotNil(LocationPreference.usableWatchFix(watch(age: 4), at: t))
        XCTAssertNil(LocationPreference.usableWatchFix(watch(age: 6), at: t))
        XCTAssertNil(LocationPreference.usableWatchFix(nil, at: t))
    }
}

/// The `fix` message added to the watch → phone wire contract (B35).
final class WatchFixMessageTests: XCTestCase {
    func testFixMessageRoundTrips() throws {
        let fix = WatchFix(latitude: 33, longitude: -117, horizontalAccuracy: 6, timestamp: 100)
        let decoded = try WatchToPhoneMessage.decode(WatchToPhoneMessage.fix(fix).encoded())
        XCTAssertEqual(decoded.kind, .fix)
        XCTAssertEqual(decoded.watchFix, fix)
        XCTAssertNil(decoded.swing)
        XCTAssertNil(decoded.command)
    }

    func testOldPayloadsWithoutFixKeyStillDecode() throws {
        let old = Data(#"{"kind":"command","command":{"id":"\#(UUID().uuidString)","command":{"puttPlusOne":{}}}}"#.utf8)
        let decoded = try WatchToPhoneMessage.decode(old)
        XCTAssertEqual(decoded.kind, .command)
        XCTAssertNil(decoded.watchFix)
    }

    func testExistingSwingMessageStillRoundTrips() throws {
        let event = SwingEvent(id: UUID(), watchWallClock: 1, watchUptime: 2, club: "7i", confidence: 1,
                               source: .auto, impactPeakG: 10, arcGyro: 5)
        let decoded = try WatchToPhoneMessage.decode(WatchToPhoneMessage.swing(event).encoded())
        XCTAssertEqual(decoded.swing, event)
        XCTAssertNil(decoded.watchFix)
    }
}

/// What the watch streams to the phone, and when it stays silent (B35).
final class WatchFixStreamTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fix(age: TimeInterval = 1, acc: Double = 5) -> WatchFix {
        WatchFix(latitude: 33, longitude: -117, horizontalAccuracy: acc, timestamp: now.timeIntervalSince1970 - age)
    }

    func testSendsTheLatestFixWhenReachable() throws {
        let data = try XCTUnwrap(WatchFixStream.payload(latest: fix(), reachable: true, now: now))
        let decoded = try WatchToPhoneMessage.decode(data)
        XCTAssertEqual(decoded.kind, .fix)
        XCTAssertEqual(decoded.watchFix, fix())
    }

    func testDropsWhenThePhoneIsNotReachable() {
        XCTAssertNil(WatchFixStream.payload(latest: fix(), reachable: false, now: now))
    }

    func testDropsWithoutAFix() {
        XCTAssertNil(WatchFixStream.payload(latest: nil, reachable: true, now: now))
    }

    func testNeverSendsAStaleOrInvalidFix() {
        XCTAssertNil(WatchFixStream.payload(latest: fix(age: 30), reachable: true, now: now))
        XCTAssertNil(WatchFixStream.payload(latest: fix(acc: -1), reachable: true, now: now))
        XCTAssertNil(WatchFixStream.payload(latest: fix(acc: 0), reachable: true, now: now))
    }

    func testIntervalIsTwoSeconds() {
        XCTAssertEqual(ShotContract.fixStreamInterval, 2)
    }

    func testSendTimeFreshnessGateIsTwoSeconds() {
        XCTAssertEqual(ShotContract.fixStreamMaxSendAge, 2)
        XCTAssertNotNil(WatchFixStream.payload(latest: fix(age: 2), reachable: true, now: now))
        XCTAssertNil(WatchFixStream.payload(latest: fix(age: 2.5), reachable: true, now: now))
        XCTAssertNil(WatchFixStream.payload(latest: fix(age: 4), reachable: true, now: now))
    }

    func testInaccurateFixIsNotSent() {
        XCTAssertNil(WatchFixStream.payload(latest: fix(acc: 16), reachable: true, now: now))
    }
}
