import XCTest

/// Round state must survive folding and unfolding mid-hole. The app runs a
/// DEBUG build with the harness flags; postures are switched at runtime by
/// posting the Darwin notifications `DebugPostureSwitch` listens for
/// (`-DebugPostureControls 1`), since simctl can't fold the simulator.
final class PostureSwitchUITests: XCTestCase {
    private enum ID {
        static let holeNumber = "round.holeNumber"
        static let nextHole = "round.nextHole"
        static let probe = "debug.roundProbe"
        static let map = "round.map"
        static func putts(_ n: Int) -> String { "round.putts.\(n)" }
    }

    private enum Pose: String {
        case closed, open, halfOpen

        var expectedLayout: String { self == .closed ? "compact" : "expanded" }
    }

    private static let darwinPrefix = "com.moisesvargasjr.golfcaddie.debug.posture."
    private static let timeout: TimeInterval = 20

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func launchFolded(extra: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = extra + [
            "-DebugStartRound", "1",
            "-DebugSeedBag", "1",
            "-DebugStartHole", "3",
            // Start folded.
            "-DebugLayoutClass", "compact",
            "-DebugPosture", "closed",
            "-DebugPostureControls", "1",
            // Keep the controls up on the folded pose (auto-hide would hide
            // round.nextHole after 5 s).
            "-DebugAutoHide", "off",
        ]
        app.launch()
        dismissLocationPromptIfShown()
        return app
    }

    @MainActor
    func testRoundStateSurvivesPostureSwitchesMidHole() throws {
        let app = launchFolded()
        let probe = app.descendants(matching: .any)[ID.probe].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: Self.timeout), "round screen never appeared")
        try waitForPose(.closed, probe: probe)

        // A fresh install starts on hole 3; a round restored from an earlier
        // run may be elsewhere, so read the hole rather than assume it.
        let startHole = try currentHole(probe: probe)
        let roundID = try field("round", of: probe)
        XCTAssertNotEqual(roundID, "none")

        // Move mid-round: step to the next hole.
        let next = app.buttons[ID.nextHole].firstMatch
        XCTAssertTrue(next.waitForExistence(timeout: Self.timeout))
        next.tap()
        let expectedHole = startHole % 18 + 1
        XCTAssertTrue(waitFor(probe, valueContains: "hole=\(expectedHole);"),
                      "next hole never showed; probe=\(probe.value ?? "nil")")
        assertHoleButton(in: app, shows: expectedHole)

        // fold → open → book → fold
        for pose in [Pose.open, .halfOpen, .closed] {
            post(pose)
            try waitForPose(pose, probe: probe)
            XCTAssertEqual(try currentHole(probe: probe), expectedHole, "hole changed after \(pose)")
            XCTAssertEqual(try field("round", of: probe), roundID, "round changed after \(pose)")
            assertHoleButton(in: app, shows: expectedHole)
        }
    }

    /// A selected shot belongs to the screen, not a layout branch: it stays
    /// selected (and keeps auto-hide paused) through every pose.
    @MainActor
    func testASelectedShotSurvivesPostureSwitches() throws {
        // A fresh tracking hole: a round restored from an earlier run may be
        // on a hole where holding the map adds nothing (casual, score entry).
        let app = launchFolded(extra: ["-DebugFreshRound", "1"])
        let probe = app.descendants(matching: .any)[ID.probe].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: Self.timeout), "round screen never appeared")
        try waitForPose(.closed, probe: probe)

        // Hold the map left of the boxes: a shot drops there, selected.
        let map = app.descendants(matching: .any)[ID.map].firstMatch
        XCTAssertTrue(map.waitForExistence(timeout: Self.timeout))
        map.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.45)).press(forDuration: 1.2)
        XCTAssertTrue(waitFor(probe, valueMatches: "selected=[0-9A-F-]{36};"),
                      "hold-to-add selected nothing; probe=\(probe.value ?? "nil")")
        let selected = try field("selected", of: probe)
        XCTAssertTrue(try field("paused", of: probe).contains("selection"))

        for pose in [Pose.open, .halfOpen, .closed] {
            post(pose)
            try waitForPose(pose, probe: probe)
            XCTAssertEqual(try field("selected", of: probe), selected, "selection lost after \(pose)")
            XCTAssertTrue(try field("paused", of: probe).contains("selection"), "pause lost after \(pose)")
        }
    }

    /// An open putts question keeps a non-default choice through every pose
    /// (the folded sheet and the open panel are different views of it).
    @MainActor
    func testAnOpenPuttsQuestionKeepsItsChoiceAcrossPostures() throws {
        let app = launchFolded(extra: ["-DebugFreshRound", "1", "-DebugOpen", "putts"])
        let probe = app.descendants(matching: .any)[ID.probe].firstMatch
        XCTAssertTrue(probe.waitForExistence(timeout: Self.timeout), "round screen never appeared")
        try waitForPose(.closed, probe: probe)
        XCTAssertTrue(waitFor(probe, valueContains: "question=putts;"), "putts never opened")

        let three = app.buttons[ID.putts(3)].firstMatch
        XCTAssertTrue(three.waitForExistence(timeout: Self.timeout))
        three.tap()
        XCTAssertTrue(waitFor(probe, valueContains: "putts=3;"), "choice not taken; probe=\(probe.value ?? "nil")")

        for pose in [Pose.open, .halfOpen, .closed] {
            post(pose)
            try waitForPose(pose, probe: probe)
            XCTAssertEqual(try field("question", of: probe), "putts", "question closed after \(pose)")
            XCTAssertEqual(try field("putts", of: probe), "3", "choice reset after \(pose)")
            XCTAssertTrue(try field("paused", of: probe).contains("question"), "pause lost after \(pose)")
            XCTAssertTrue(app.buttons[ID.putts(3)].firstMatch.waitForExistence(timeout: Self.timeout),
                          "no putts question drawn after \(pose)")
        }
    }

    // MARK: Helpers

    @MainActor
    private func waitFor(_ element: XCUIElement, valueMatches pattern: String) -> Bool {
        let predicate = NSPredicate(format: "value MATCHES %@", ".*\(pattern).*")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: Self.timeout) == .completed
    }

    private func post(_ pose: Pose) {
        let name = CFNotificationName((Self.darwinPrefix + pose.rawValue) as CFString)
        CFNotificationCenterPostNotification(CFNotificationCenterGetDarwinNotifyCenter(),
                                             name, nil, nil, true)
    }

    @MainActor
    private func waitForPose(_ pose: Pose, probe: XCUIElement) throws {
        let fragment = "layout=\(pose.expectedLayout);posture=\(pose.rawValue)"
        XCTAssertTrue(waitFor(probe, valueContains: fragment),
                      "pose \(pose) never applied; probe=\(probe.value ?? "nil")")
    }

    @MainActor
    private func waitFor(_ element: XCUIElement, valueContains text: String) -> Bool {
        let predicate = NSPredicate(format: "value CONTAINS %@", text)
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter().wait(for: [expectation], timeout: Self.timeout) == .completed
    }

    @MainActor
    private func field(_ key: String, of probe: XCUIElement) throws -> String {
        let value = try XCTUnwrap(probe.value as? String, "probe has no value")
        let pair = value.split(separator: ";").first { $0.hasPrefix("\(key)=") }
        let found = try XCTUnwrap(pair, "probe has no \(key): \(value)")
        return String(found.dropFirst(key.count + 1))
    }

    @MainActor
    private func currentHole(probe: XCUIElement) throws -> Int {
        let text = try field("hole", of: probe)
        return try XCTUnwrap(Int(text), "hole is not a number: \(text)")
    }

    /// The visible hole control (whichever layout drew it) agrees.
    @MainActor
    private func assertHoleButton(in app: XCUIApplication, shows hole: Int) {
        let button = app.buttons[ID.holeNumber].firstMatch
        XCTAssertTrue(button.waitForExistence(timeout: Self.timeout), "no hole number control")
        XCTAssertTrue(waitFor(button, valueContains: "\(hole)"),
                      "hole control shows \(button.value ?? "nil"), expected \(hole)")
        XCTAssertEqual(button.value as? String, "\(hole)")
    }

    /// A fresh simulator asks for location on launch; the alert lives in
    /// SpringBoard and would block taps on the app.
    @MainActor
    private func dismissLocationPromptIfShown() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 5) else { return }
        for label in ["Allow While Using App", "Allow Once", "Allow", "OK"] {
            let button = alert.buttons[label]
            if button.exists {
                button.tap()
                return
            }
        }
    }
}
