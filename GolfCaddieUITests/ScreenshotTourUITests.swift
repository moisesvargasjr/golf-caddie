import XCTest

/// Screenshot tour for PR review: launches the app once per shot with that
/// shot's DEBUG launch flags, sets the orientation, and attaches a screenshot
/// named after the shot. Skipped unless the runner passes a tour, so a plain
/// `xcodebuild test` doesn't pay for it.
///
/// Pass the tour through xcodebuild's runner environment:
///   TEST_RUNNER_TOUR='open-wide|landscape|-DebugOpen round -DebugLayoutClass expanded;…'
/// Each shot is `name|portrait|landscape|launch args`, shots separated by `;`.
/// Pull the PNGs out with `xcrun xcresulttool export attachments`.
final class ScreenshotTourUITests: XCTestCase {
    private struct Shot {
        let name: String
        let orientation: UIDeviceOrientation
        let arguments: [String]

        init?(_ spec: Substring) {
            let parts = spec.split(separator: "|", maxSplits: 2, omittingEmptySubsequences: false)
            guard parts.count == 3, !parts[0].isEmpty else { return nil }
            name = String(parts[0])
            orientation = parts[1] == "landscape" ? .landscapeLeft : .portrait
            arguments = parts[2].split(separator: " ").map(String.init)
        }
    }

    /// Time for the map tiles and the first layout pass to settle.
    private static let settle: TimeInterval = 7

    @MainActor
    func testScreenshotTour() throws {
        let spec = ProcessInfo.processInfo.environment["TOUR"] ?? ""
        let shots = spec.split(separator: ";").compactMap(Shot.init)
        try XCTSkipIf(shots.isEmpty, "no TOUR given")

        for shot in shots {
            XCUIDevice.shared.orientation = shot.orientation
            let app = XCUIApplication()
            app.launchArguments = shot.arguments
            app.launch()
            dismissLocationPromptIfShown()
            Thread.sleep(forTimeInterval: Self.settle)
            let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            attachment.name = shot.name
            attachment.lifetime = .keepAlways
            add(attachment)
            app.terminate()
        }
        XCUIDevice.shared.orientation = .portrait
    }

    @MainActor
    private func dismissLocationPromptIfShown() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for label in ["Allow While Using App", "Allow Once", "Allow"] {
            let button = springboard.buttons[label]
            if button.waitForExistence(timeout: 2) {
                button.tap()
                return
            }
        }
    }
}
