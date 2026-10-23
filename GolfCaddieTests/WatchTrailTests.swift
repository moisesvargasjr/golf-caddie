import CoreLocation
@testable import GolfCaddie
import GRDB
import XCTest

/// B38: the watch records its own GPS trail and queues it to the phone, which
/// stores it beside the phone's breadcrumbs and prefers it wherever it exists
/// (phone left in the cart).
final class WatchTrailRecorderTests: XCTestCase {
    private let t0 = 1_800_000_000.0

    private func fix(_ offset: Double, lat: Double = 33.0, acc: Double = 5) -> WatchFix {
        WatchFix(latitude: lat, longitude: -117.0, horizontalAccuracy: acc, timestamp: t0 + offset)
    }

    func testRejectsInvalidAndCoarseFixes() {
        var recorder = WatchTrailRecorder()
        XCTAssertFalse(recorder.record(fix(0, acc: 0)))
        XCTAssertFalse(recorder.record(fix(1, acc: -1)))
        XCTAssertFalse(recorder.record(fix(2, acc: 20.1)))
        XCTAssertTrue(recorder.record(fix(3, acc: 20)))
        XCTAssertEqual(recorder.count, 1)
    }

    func testThinsByTimeAndDistance() {
        var recorder = WatchTrailRecorder()
        XCTAssertTrue(recorder.record(fix(0)))
        XCTAssertFalse(recorder.record(fix(1)), "same spot, 1 s later")
        XCTAssertFalse(recorder.record(fix(1.9)), "same spot, under 2 s")
        XCTAssertTrue(recorder.record(fix(2)), "2 s since the last kept fix")
        XCTAssertFalse(recorder.record(fix(2.5, lat: 33.00002)), "2 m away, under 2 s")
        XCTAssertTrue(recorder.record(fix(3, lat: 33.00004)), "4.4 m from the last kept fix")
        XCTAssertEqual(recorder.count, 3)
    }

    func testRejectedFixDoesNotResetTheThinningClock() {
        var recorder = WatchTrailRecorder()
        XCTAssertTrue(recorder.record(fix(0)))
        XCTAssertFalse(recorder.record(fix(1.5, acc: 99)))
        XCTAssertTrue(recorder.record(fix(2.0)))
    }

    func testDrainEmitsOneBatchWithAUniqueIdAndEmptiesTheBuffer() {
        var recorder = WatchTrailRecorder()
        _ = recorder.record(fix(0)); _ = recorder.record(fix(2))
        let first = recorder.drain()
        XCTAssertEqual(first.count, 1)
        XCTAssertEqual(first[0].fixes.count, 2)
        XCTAssertEqual(recorder.count, 0)
        XCTAssertTrue(recorder.drain().isEmpty, "nothing buffered, nothing to send")
        _ = recorder.record(fix(10))
        XCTAssertNotEqual(recorder.drain()[0].batchId, first[0].batchId)
    }

    func testLargeBuffersSplitIntoBoundedBatches() {
        var recorder = WatchTrailRecorder()
        for i in 0..<130 { _ = recorder.record(fix(Double(i) * 2)) }
        let batches = recorder.drain()
        XCTAssertEqual(batches.map(\.fixes.count), [60, 60, 10])
        XCTAssertEqual(Set(batches.map(\.batchId)).count, 3)
    }

    func testThinningContinuesAcrossADrain() {
        var recorder = WatchTrailRecorder()
        _ = recorder.record(fix(0))
        _ = recorder.drain()
        XCTAssertFalse(recorder.record(fix(1)), "the last kept fix is remembered across flushes")
    }
}

final class WatchTrailWireTests: XCTestCase {
    private func batch(count: Int = 3) -> WatchTrailBatch {
        WatchTrailBatch(batchId: UUID(), fixes: (0..<count).map {
            WatchFix(latitude: 33.123456 + Double($0) * 0.00001, longitude: -117.654321,
                     horizontalAccuracy: 4.2, timestamp: 1_800_000_000.5 + Double($0) * 2)
        })
    }

    func testBatchRoundTripsThroughAMessage() throws {
        let original = batch()
        let decoded = try WatchToPhoneMessage.decode(WatchToPhoneMessage.trail(original).encoded())
        XCTAssertEqual(decoded.kind, .trail)
        XCTAssertEqual(decoded.trail, original)
        XCTAssertNil(decoded.swing)
        XCTAssertNil(decoded.command)
        XCTAssertNil(decoded.watchFix)
    }

    func testEncodingIsCompact() throws {
        let data = try WatchToPhoneMessage.trail(batch(count: 15)).encoded()
        XCTAssertLessThan(data.count, 15 * 60 + 150, "about 55 bytes per fix, not a keyed object each")
    }

    func testEncodingRoundsToUsefulPrecision() throws {
        let noisy = WatchTrailBatch(batchId: UUID(), fixes: [
            WatchFix(latitude: 33.123456789012, longitude: -117.987654321098, horizontalAccuracy: 4.2345678,
                     timestamp: 1_800_000_000.123456)])
        let decoded = try WatchToPhoneMessage.decode(WatchToPhoneMessage.trail(noisy).encoded()).trail
        let f = try XCTUnwrap(decoded?.fixes.first)
        XCTAssertEqual(f.latitude, 33.123457, accuracy: 1e-9)
        XCTAssertEqual(f.longitude, -117.987654, accuracy: 1e-9)
        XCTAssertEqual(f.horizontalAccuracy, 4.2, accuracy: 1e-9)
        XCTAssertEqual(f.timestamp, 1_800_000_000.123, accuracy: 1e-6)
    }

    func testMalformedFixRowFailsToDecodeInsteadOfCrashing() {
        let bad = Data(#"{"kind":"trail","trail":{"b":"\#(UUID().uuidString)","f":[[1,2]]}}"#.utf8)
        XCTAssertThrowsError(try WatchToPhoneMessage.decode(bad))
    }

    func testPreTrailPayloadsStillDecode() throws {
        let old = Data(#"{"kind":"command","command":{"id":"\#(UUID().uuidString)","command":{"puttPlusOne":{}}}}"#.utf8)
        XCTAssertNil(try WatchToPhoneMessage.decode(old).trail)
    }

    func testTrailTransferKeyIsNotTheRoundPayloadKey() {
        // The watch's "SYNCING N" chip counts payloadKey transfers only.
        XCTAssertNotEqual(ShotContract.trailKey, ShotContract.payloadKey)
        XCTAssertEqual(ShotContract.trailFlushInterval, 60)
    }
}

final class TrailMergeTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)
    private let round = UUID()

    private func p(_ offset: Double, _ source: TracePointSource?, lat: Double) -> TracePoint {
        TracePoint(id: UUID(), roundID: round, timestamp: t0.addingTimeInterval(offset),
                   latitude: lat, longitude: -117, accuracy: 5, source: source)
    }

    func testPhoneOnlyIsReturnedSorted() {
        let merged = TrailMerge.preferred([p(10, nil, lat: 1), p(0, .phone, lat: 2), p(5, nil, lat: 3)])
        XCTAssertEqual(merged.map(\.latitude), [2, 3, 1])
    }

    func testWatchCoverageReplacesPhonePointsInsideItsSpan() {
        let phone = (0...60).map { p(Double($0), nil, lat: 33.0) } // sitting in the cart
        let watch = stride(from: 10.0, through: 40.0, by: 2).map { p($0, .watch, lat: 34.0) }
        let merged = TrailMerge.preferred(phone + watch)
        let inside = merged.filter { $0.timestamp >= t0.addingTimeInterval(10) && $0.timestamp <= t0.addingTimeInterval(40) }
        XCTAssertTrue(inside.allSatisfy { $0.source == .watch })
        // Phone points outside the watch span remain.
        XCTAssertEqual(merged.filter { $0.source != .watch }.count, 10 + 20) // 0..9 and 41..60
        XCTAssertEqual(merged, merged.sorted { $0.timestamp < $1.timestamp })
    }

    func testGapsOverFifteenSecondsSplitTheWatchSpan() {
        let watch = [p(0, .watch, lat: 34), p(10, .watch, lat: 34), p(40, .watch, lat: 34), p(50, .watch, lat: 34)]
        let phone = [p(5, nil, lat: 34), p(25, nil, lat: 34), p(45, nil, lat: 34)]
        let merged = TrailMerge.preferred(watch + phone)
        let kept = merged.filter { $0.source != .watch }.map { $0.timestamp.timeIntervalSince(t0) }
        XCTAssertEqual(kept, [25], "only the plausible phone point in the 30 s watch gap survives")
    }

    // M1: a short watch gap is NOT back-filled with a phone trail that is nowhere near the watch.
    func testShortWatchGapIsLeftEmptyWhenThePhoneWasFarAway() {
        let watch = [p(0, .watch, lat: 34), p(10, .watch, lat: 34), p(40, .watch, lat: 34), p(50, .watch, lat: 34)]
        let cart = [p(25, nil, lat: 33)] // 111 km away
        let merged = TrailMerge.preferred(watch + cart)
        XCTAssertTrue(merged.allSatisfy(\.isWatch), "interpolating across the gap is fine; a cart point is not")
    }

    func testPhonePointNearThePathOnBothSidesFillsAShortGap() {
        let watch = [p(0, .watch, lat: 34.0000), p(10, .watch, lat: 34.0000),
                     p(40, .watch, lat: 34.0002), p(50, .watch, lat: 34.0002)] // 22 m apart
        let phone = [p(25, nil, lat: 34.0001)]
        XCTAssertEqual(TrailMerge.preferred(watch + phone).filter { !$0.isWatch }.count, 1)
    }

    func testALongWatchGapIsFilledByThePhoneWhateverItSays() {
        let watch = [p(0, .watch, lat: 34), p(10, .watch, lat: 34), p(300, .watch, lat: 34), p(310, .watch, lat: 34)]
        let phone = [p(100, nil, lat: 33), p(200, nil, lat: 33)] // watch was off for 290 s
        XCTAssertEqual(TrailMerge.preferred(watch + phone).filter { !$0.isWatch }.count, 2)
    }

    func testPhonePointsBeforeAndAfterTheWatchTrailAreKept() {
        let watch = [p(100, .watch, lat: 34), p(110, .watch, lat: 34)]
        let phone = [p(0, nil, lat: 33), p(200, nil, lat: 33)]
        XCTAssertEqual(TrailMerge.preferred(watch + phone).filter { !$0.isWatch }.count, 2)
    }

    func testGapOfExactlyFifteenSecondsStillCounts() {
        let merged = TrailMerge.preferred([p(0, .watch, lat: 34), p(15, .watch, lat: 34), p(7, nil, lat: 33)])
        XCTAssertEqual(merged.filter { $0.source != .watch }.count, 0)
    }

    func testWatchOnlyAndEmpty() {
        XCTAssertTrue(TrailMerge.preferred([]).isEmpty)
        XCTAssertEqual(TrailMerge.preferred([p(2, .watch, lat: 1), p(1, .watch, lat: 2)]).map(\.latitude), [2, 1])
    }

    func testASingleWatchPointOnlyCoversItsOwnInstant() {
        let merged = TrailMerge.preferred([p(10, .watch, lat: 34), p(10, nil, lat: 33), p(12, nil, lat: 33)])
        XCTAssertEqual(merged.filter { $0.source != .watch }.count, 1)
    }

    func testPerformanceWithLargeRounds() {
        let phone = (0..<20_000).map { p(Double($0), nil, lat: 33) }
        let watch = (0..<10_000).map { p(Double($0) * 2, .watch, lat: 34) }
        measure { _ = TrailMerge.preferred(phone + watch) }
    }
}

/// DB-backed behaviour: v9 migration, ingest, round assignment, preferred reads.
@MainActor
final class WatchTrailStoreTests: XCTestCase {
    private var queue: DatabaseQueue!
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    override func setUpWithError() throws {
        queue = try TestDatabase.makeInMemory()
        TestDatabase.install(queue)
    }

    override func tearDown() {
        TestDatabase.restore()
        queue = nil
    }

    private func batch(_ id: UUID = UUID(), from start: Double, count: Int = 5, lat: Double = 34.0) -> WatchTrailBatch {
        WatchTrailBatch(batchId: id, fixes: (0..<count).map {
            WatchFix(latitude: lat, longitude: -117, horizontalAccuracy: 4,
                     timestamp: t0.timeIntervalSince1970 + start + Double($0) * 2)
        })
    }

    private func phonePoint(_ round: UUID, _ offset: Double, lat: Double = 33.0) throws {
        try TracePointRepository.insert(TracePoint(
            id: UUID(), roundID: round, timestamp: t0.addingTimeInterval(offset),
            latitude: lat, longitude: -117, accuracy: 5))
    }

    // MARK: migration

    func testV9AddsANullableSourceColumnAndKeepsLegacyRows() throws {
        let q = try TestDatabase.makeInMemory(upTo: "v8_shot_location_source")
        let roundID = UUID().uuidString
        try q.write { db in
            try db.execute(sql: "INSERT INTO round (id, startedAt) VALUES (?, ?)", arguments: [roundID, Date()])
            try db.execute(sql: "INSERT INTO tracePoint (id, roundID, timestamp, latitude, longitude, accuracy) VALUES (?, ?, ?, 1, 2, 3)",
                           arguments: [UUID().uuidString, roundID, Date()])
        }
        try Database.migrator.migrate(q)
        let columns = try q.read { db in try Row.fetchAll(db, sql: "PRAGMA table_info(tracePoint)") }
        let source = try XCTUnwrap(columns.first { ($0["name"] as String) == "source" })
        XCTAssertEqual(source["type"] as String?, "TEXT")
        XCTAssertEqual(source["notnull"] as Int?, 0)
        let legacy = try q.read { db in try TracePoint.fetchAll(db) }
        XCTAssertEqual(legacy.count, 1)
        XCTAssertNil(legacy[0].source)
        XCTAssertFalse(legacy[0].isWatch, "NULL means phone")
    }

    func testV9IsRegisteredLast() {
        XCTAssertEqual(Database.migrator.migrations.last, "v9_trace_point_source")
    }

    func testSourceRoundTrips() throws {
        let round = try TestDatabase.seedRound(startedAt: t0)
        try TracePointRepository.insert(TracePoint(
            id: UUID(), roundID: round.id, timestamp: t0, latitude: 1, longitude: 2, accuracy: 3, source: .watch))
        XCTAssertEqual(try TracePointRepository.pointsForRound(round.id).first?.source, .watch)
    }

    // MARK: round assignment

    private func round(_ start: Double, _ end: Double?) -> Round {
        Round(id: UUID(), startedAt: t0.addingTimeInterval(start), endedAt: end.map { t0.addingTimeInterval($0) },
              courseName: nil, notes: nil)
    }

    func testFixesLandInTheRoundWhoseWindowContainsThem() {
        let early = round(0, 3_600), active = round(7_200, nil)
        let b = batch(from: 7_300)
        let assigned = TraceIngest.assign(b.fixes, rounds: [early, active])
        XCTAssertEqual(Set(assigned.keys), [active.id])
    }

    func testALateBatchAfterTheRoundEndedStillLandsInThatRound() {
        let ended = round(0, 3_600), next = round(5_000, nil)
        let b = batch(from: 3_000) // played during `ended`, delivered much later
        XCTAssertEqual(Set(TraceIngest.assign(b.fixes, rounds: [ended, next]).keys), [ended.id])
    }

    func testABatchStraddlingTwoRoundsIsSplit() {
        let a = round(0, 100), b = round(1_000, nil)
        let fixes = [batch(from: 90, count: 1), batch(from: 1_010, count: 1)].flatMap(\.fixes)
        let assigned = TraceIngest.assign(fixes, rounds: [a, b])
        XCTAssertEqual(assigned[a.id]?.count, 1)
        XCTAssertEqual(assigned[b.id]?.count, 1)
    }

    func testSmallSlackBeforeTheRoundStartIsTolerated() {
        let r = round(1_000, nil)
        XCTAssertEqual(TraceIngest.assign(batch(from: 950, count: 1).fixes, rounds: [r]).keys.count, 1)
        XCTAssertEqual(TraceIngest.assign(batch(from: 500, count: 1).fixes, rounds: [r]).keys.count, 1,
                       "a watch workout often starts well before the phone round (10 min of slack)")
        XCTAssertTrue(TraceIngest.assign(batch(from: 300, count: 1).fixes, rounds: [r]).isEmpty)
    }

    func testFixesOutsideEveryRoundAreDropped() {
        let r = round(0, 100)
        XCTAssertTrue(TraceIngest.assign(batch(from: 10_000).fixes, rounds: [r]).isEmpty)
    }

    // MARK: ingest + dedupe

    func testIngestStoresWatchPointsInTheActiveRound() throws {
        let round = try TestDatabase.seedRound(startedAt: t0)
        let result = try TraceIngest.ingest(batch(from: 10))
        XCTAssertEqual(result.inserted, 5)
        XCTAssertEqual(result.roundIDs, [round.id])
        XCTAssertEqual(result.dropped, 0)
        XCTAssertEqual(result.spans[round.id], t0.addingTimeInterval(10)...t0.addingTimeInterval(18))
        let points = try TracePointRepository.pointsForRound(round.id)
        XCTAssertEqual(points.count, 5)
        XCTAssertTrue(points.allSatisfy { $0.source == .watch })
    }

    func testReplayingTheSameBatchIsIdempotent() throws {
        let round = try TestDatabase.seedRound(startedAt: t0)
        let b = batch(from: 10)
        _ = try TraceIngest.ingest(b)
        let again = try TraceIngest.ingest(b)
        XCTAssertEqual(again.inserted, 0)
        XCTAssertEqual(try TracePointRepository.count(forRound: round.id), 5)
    }

    func testADifferentBatchIdWithTheSameTimestampsDoesNotDuplicate() throws {
        let round = try TestDatabase.seedRound(startedAt: t0)
        _ = try TraceIngest.ingest(batch(from: 10))
        let again = try TraceIngest.ingest(batch(from: 10))
        XCTAssertEqual(again.inserted, 0)
        XCTAssertEqual(try TracePointRepository.count(forRound: round.id), 5)
    }

    func testAPhonePointAtTheSameTimestampDoesNotBlockAWatchPoint() throws {
        let round = try TestDatabase.seedRound(startedAt: t0)
        try phonePoint(round.id, 10)
        _ = try TraceIngest.ingest(batch(from: 10, count: 1))
        XCTAssertEqual(try TracePointRepository.count(forRound: round.id), 2)
    }

    func testIngestWithNoMatchingRoundStoresNothing() throws {
        let result = try TraceIngest.ingest(batch(from: 10))
        XCTAssertEqual(result.inserted, 0)
        XCTAssertTrue(result.roundIDs.isEmpty)
        XCTAssertEqual(result.dropped, 5, "fixes that matched no round are counted (and logged)")
    }

    // MARK: preferred trail + nearest

    func testPreferredTrailFromTheRepositoryUsesWatchPointsOverTheCart() throws {
        let round = try TestDatabase.seedRound(startedAt: t0)
        for s in 0..<60 { try phonePoint(round.id, Double(s)) }
        _ = try TraceIngest.ingest(batch(from: 10, count: 10)) // 10...28 s
        let trail = try TracePointRepository.preferredTrail(roundID: round.id)
        let inSpan = trail.filter { $0.timestamp >= t0.addingTimeInterval(10) && $0.timestamp <= t0.addingTimeInterval(28) }
        XCTAssertEqual(inSpan.count, 10)
        XCTAssertTrue(inSpan.allSatisfy { $0.source == .watch })
    }

    func testNearestPrefersTheWatchPointOverTheCartPoint() throws {
        let round = try TestDatabase.seedRound(startedAt: t0)
        for s in 0..<60 { try phonePoint(round.id, Double(s)) }
        _ = try TraceIngest.ingest(batch(from: 10, count: 10))
        let hit = try XCTUnwrap(TracePointRepository.nearest(toTimestamp: t0.addingTimeInterval(20), inRound: round.id))
        XCTAssertEqual(hit.source, .watch)
        XCTAssertEqual(hit.latitude, 34.0, accuracy: 1e-9)
    }

    func testNearestStillWorksPhoneOnlyAndOutsideTheWatchSpan() throws {
        let round = try TestDatabase.seedRound(startedAt: t0)
        for s in 0..<60 { try phonePoint(round.id, Double(s)) }
        _ = try TraceIngest.ingest(batch(from: 10, count: 3))
        let hit = try XCTUnwrap(TracePointRepository.nearest(toTimestamp: t0.addingTimeInterval(50), inRound: round.id))
        XCTAssertNotEqual(hit.source, .watch)
        XCTAssertNil(try TracePointRepository.nearest(toTimestamp: t0, inRound: UUID()))
    }

    // MARK: coordinator intake

    private struct Walked: StepCounting {
        func steps(from: Date, to: Date) async -> Int { .max }
    }

    func testTrailBatchIsStoredEvenBeforeAControllerIsAttached() async throws {
        let round = try TestDatabase.seedRound(startedAt: t0)
        let coordinator = LiveShotCoordinator(steps: Walked())
        coordinator.ingest(.trail(batch(from: 10)))
        await coordinator.waitUntilTrailIdle() // the DB work runs off the main actor
        XCTAssertEqual(try TracePointRepository.count(forRound: round.id), 5, "must not wait behind controller == nil")
    }

    func testTrailBatchesDoNotDisturbCommandReplay() async throws {
        let location = LocationManager()
        let controller = RoundController(location: location)
        try controller.startRound()
        // Isolate from the simulator: if the test host has location permission,
        // startRound's live tracking would record phone breadcrumbs into this
        // round and skew trace-point counts.
        location.stopTracking()
        location.onLocationUpdate = nil
        let coordinator = LiveShotCoordinator(steps: Walked(), debounceInterval: 0.05)
        coordinator.attach(controller: controller, location: location)
        let now = Date()
        coordinator.ingest(.command(.addShot(clubShortName: nil), sentAt: now))
        coordinator.ingest(.trail(WatchTrailBatch(batchId: UUID(), fixes: [
            WatchFix(latitude: 34, longitude: -117, horizontalAccuracy: 4, timestamp: now.timeIntervalSince1970)])))
        coordinator.ingest(.command(.puttPlusOne, sentAt: now))
        await coordinator.waitUntilIdle()
        await coordinator.waitUntilTrailIdle()
        XCTAssertEqual(controller.currentHoleShots.count, 2)
        XCTAssertEqual(try TracePointRepository.count(forRound: XCTUnwrap(controller.currentRound).id), 1)
    }

    func testSwingFusesToTheWatchTrailAndIsTaggedWatch() async throws {
        let location = LocationManager()
        let controller = RoundController(location: location)
        controller.phoneFixProvider = { nil }
        controller.watchFixProvider = { nil }
        try controller.startRound()
        location.stopTracking()            // no live phone breadcrumbs (see above)
        location.onLocationUpdate = nil
        let round = try XCTUnwrap(controller.currentRound)
        let swingTime = Date().addingTimeInterval(-600)
        // Phone sat in the cart; the watch trail (no WatchFix on the swing) has the golfer.
        try TracePointRepository.insert(TracePoint(
            id: UUID(), roundID: round.id, timestamp: swingTime, latitude: 33.0, longitude: -117, accuracy: 5))
        for offset in [-4.0, -2.0, 0.5, 2.0, 4.0] { // the watch trail spans the swing
            try TracePointRepository.insert(TracePoint(
                id: UUID(), roundID: round.id, timestamp: swingTime.addingTimeInterval(offset), latitude: 33.0009,
                longitude: -117, accuracy: 4, source: .watch))
        }
        let coordinator = LiveShotCoordinator(steps: Walked(), debounceInterval: 0.05)
        coordinator.attach(controller: controller, location: location)
        coordinator.ingest(.swing(SwingEvent(
            id: UUID(), watchWallClock: swingTime.timeIntervalSince1970, watchUptime: 0, club: "7i",
            confidence: 1, source: .auto, impactPeakG: 12, arcGyro: 6)))
        try await Task.sleep(nanoseconds: 300_000_000)
        await coordinator.waitUntilIdle()
        let shot = try XCTUnwrap(controller.currentHoleShots.last)
        XCTAssertEqual(try XCTUnwrap(shot.latitude), 33.0009, accuracy: 1e-7)
        XCTAssertEqual(shot.locationSource, .watch)
    }
}
