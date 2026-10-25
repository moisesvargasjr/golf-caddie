#if DEBUG
import SwiftUI
import XCTest
@testable import GolfCaddie

/// Thread-safe log of requested sleeps; throws after `limit` calls so a looping
/// script ends deterministically.
private final class SleepRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var durations: [TimeInterval] = []
    private let limit: Int

    init(limit: Int = .max) { self.limit = limit }

    var recorded: [TimeInterval] { lock.withLock { durations } }

    func sleep(_ seconds: TimeInterval) async throws {
        let count = lock.withLock { () -> Int in
            durations = durations + [seconds]
            return durations.count
        }
        if count >= limit { throw CancellationError() }
    }
}

@MainActor
final class DebugPostureSwitchTests: XCTestCase {
    /// A private, empty defaults suite per test (XCTest makes a new instance
    /// per test method), removed when the test ends.
    private lazy var defaults: UserDefaults = {
        let name = "DebugPostureSwitchTests.\(UUID().uuidString)"
        self.addTeardownBlock { UserDefaults.standard.removePersistentDomain(forName: name) }
        return UserDefaults(suiteName: name)!
    }()

    private let live = DisplayContext(layoutClass: .expanded, posture: .open,
                                      windowSize: CGSize(width: 951, height: 669))

    // MARK: Poses

    func testPoseMapping() {
        XCTAssertEqual(DebugPose.closed.layoutClass, .compact)
        XCTAssertEqual(DebugPose.closed.posture, .closed)
        XCTAssertEqual(DebugPose.open.layoutClass, .expanded)
        XCTAssertEqual(DebugPose.open.posture, .open)
        XCTAssertEqual(DebugPose.halfOpen.layoutClass, .expanded)
        XCTAssertEqual(DebugPose.halfOpen.posture, .halfOpen)
    }

    func testPoseAliases() {
        XCTAssertEqual(DebugPose(name: "fold"), .closed)
        XCTAssertEqual(DebugPose(name: "unfold"), .open)
        XCTAssertEqual(DebugPose(name: "book"), .halfOpen)
        XCTAssertEqual(DebugPose(name: "halfOpen"), .halfOpen)
        XCTAssertNil(DebugPose(name: "sideways"))
    }

    // MARK: Script parsing

    func testParsesASequence() {
        XCTAssertEqual(DebugPostureScript.parse("closed:3,open:3,halfOpen:3"), [
            DebugPostureStep(pose: .closed, seconds: 3),
            DebugPostureStep(pose: .open, seconds: 3),
            DebugPostureStep(pose: .halfOpen, seconds: 3),
        ])
    }

    func testParseToleratesWhitespaceAndFractions() {
        XCTAssertEqual(DebugPostureScript.parse(" fold : 1.5 , book:2 ,"), [
            DebugPostureStep(pose: .closed, seconds: 1.5),
            DebugPostureStep(pose: .halfOpen, seconds: 2),
        ])
    }

    func testParseRejectsMalformedScripts() {
        XCTAssertNil(DebugPostureScript.parse(""))
        XCTAssertNil(DebugPostureScript.parse("closed"))
        XCTAssertNil(DebugPostureScript.parse("closed:3,sideways:3"))
        XCTAssertNil(DebugPostureScript.parse("closed:-1"))
        XCTAssertNil(DebugPostureScript.parse("closed:0"))
        XCTAssertNil(DebugPostureScript.parse("closed:abc"))
        XCTAssertNil(DebugPostureScript.parse("closed:3:4"))
    }

    // MARK: Store

    func testNoOverrideLeavesContextAlone() {
        let store = DebugPostureSwitch(defaults: defaults)
        XCTAssertNil(store.layoutClass)
        XCTAssertNil(store.posture)
        XCTAssertEqual(store.apply(to: live), live)
    }

    func testInitialisesFromLaunchArguments() {
        defaults.set("compact", forKey: DebugPostureSwitch.Key.layoutClass)
        defaults.set("closed", forKey: DebugPostureSwitch.Key.posture)
        defaults.set(true, forKey: DebugPostureSwitch.Key.controls)
        let store = DebugPostureSwitch(defaults: defaults)
        XCTAssertEqual(store.layoutClass, .compact)
        XCTAssertEqual(store.posture, .closed)
        XCTAssertTrue(store.controlsEnabled)
    }

    func testIgnoresUnknownLaunchValues() {
        defaults.set("huge", forKey: DebugPostureSwitch.Key.layoutClass)
        defaults.set("upsideDown", forKey: DebugPostureSwitch.Key.posture)
        let store = DebugPostureSwitch(defaults: defaults)
        XCTAssertNil(store.layoutClass)
        XCTAssertNil(store.posture)
        XCTAssertFalse(store.controlsEnabled)
    }

    func testSetPoseOverridesClassAndPostureButKeepsWindowSize() {
        let store = DebugPostureSwitch(defaults: defaults)
        store.set(.closed)
        let folded = store.apply(to: live)
        XCTAssertEqual(folded.layoutClass, .compact)
        XCTAssertEqual(folded.posture, .closed)
        // Forcing compact on the expanded window only forces the class.
        XCTAssertEqual(folded.windowSize, live.windowSize)

        store.set(.halfOpen)
        XCTAssertEqual(store.apply(to: live).posture, .halfOpen)
        XCTAssertEqual(store.apply(to: live).layoutClass, .expanded)
    }

    func testPartialOverrideOnlyTouchesItsField() {
        defaults.set("halfOpen", forKey: DebugPostureSwitch.Key.posture)
        let store = DebugPostureSwitch(defaults: defaults)
        let context = store.apply(to: live)
        XCTAssertEqual(context.layoutClass, .expanded)
        XCTAssertEqual(context.posture, .halfOpen)
    }

    func testClearRemovesOverrides() {
        let store = DebugPostureSwitch(defaults: defaults)
        store.set(.closed)
        store.clear()
        XCTAssertEqual(store.apply(to: live), live)
    }

    // MARK: Darwin notification names

    func testDarwinNamesRoundTrip() {
        for pose in DebugPose.allCases {
            let name = DebugPostureSwitch.darwinName(for: pose)
            XCTAssertTrue(name.hasPrefix(DebugPostureSwitch.darwinPrefix))
            XCTAssertEqual(DebugPostureSwitch.pose(fromDarwinName: name), pose)
        }
        XCTAssertEqual(DebugPostureSwitch.darwinName(for: .halfOpen),
                       "com.moisesvargasjr.golfcaddie.debug.posture.halfOpen")
        XCTAssertNil(DebugPostureSwitch.pose(fromDarwinName: "com.example.other.closed"))
    }

    func testDarwinNotificationAppliesThePose() {
        let store = DebugPostureSwitch(defaults: defaults)
        store.handleDarwinNotification(named: DebugPostureSwitch.darwinName(for: .open))
        XCTAssertEqual(store.posture, .open)
        XCTAssertEqual(store.layoutClass, .expanded)
        store.handleDarwinNotification(named: "unrelated")
        XCTAssertEqual(store.posture, .open)
    }

    // MARK: Sequence runner

    func testSequenceAppliesEachPoseInOrder() async {
        let store = DebugPostureSwitch(defaults: defaults)
        let recorder = SleepRecorder()
        let steps = DebugPostureScript.parse("closed:3,open:2,halfOpen:1") ?? []
        await store.runSequence(steps, loop: false, sleep: { try await recorder.sleep($0) }).value
        XCTAssertEqual(recorder.recorded, [3, 2, 1])
        XCTAssertEqual(store.posture, .halfOpen)
        XCTAssertEqual(store.layoutClass, .expanded)
    }

    func testLoopingSequenceRepeatsUntilCancelled() async {
        let store = DebugPostureSwitch(defaults: defaults)
        let recorder = SleepRecorder(limit: 5)
        let steps = DebugPostureScript.parse("closed:1,open:2") ?? []
        await store.runSequence(steps, loop: true, sleep: { try await recorder.sleep($0) }).value
        XCTAssertEqual(recorder.recorded, [1, 2, 1, 2, 1])
        // The fifth step (closed) was applied before its sleep was cut short.
        XCTAssertEqual(store.posture, .closed)
    }

    // MARK: Round probe

    func testRoundProbeValue() {
        let id = UUID()
        let value = DebugRoundProbe.value(holeNumber: 4, roundID: id, stage: .wide, display: live)
        XCTAssertEqual(value, "hole=4;round=\(id.uuidString);stage=wide;layout=expanded;posture=open")
        let none = DebugRoundProbe.value(holeNumber: 1, roundID: nil, stage: .overlay,
                                         display: DebugPostureSwitch(defaults: defaults).apply(to: live))
        XCTAssertTrue(none.contains("round=none"))
    }

    func testEmptySequenceFinishesImmediately() async {
        let store = DebugPostureSwitch(defaults: defaults)
        await store.runSequence([], loop: true).value
        XCTAssertNil(store.posture)
    }
}
#endif
