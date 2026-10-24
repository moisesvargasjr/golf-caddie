import SwiftUI
import XCTest
@testable import GolfCaddie

/// `RoundMapLayout.resolve` is a pure function of `DisplayContext`, and the
/// chrome insets keep every layout inside the SafeChrome rules.
@MainActor
final class RoundMapLayoutTests: XCTestCase {
    private func display(_ w: CGFloat, _ h: CGFloat, _ cls: LayoutClass,
                         _ posture: HingePosture) -> DisplayContext {
        DisplayContext(layoutClass: cls, posture: posture, windowSize: CGSize(width: w, height: h))
    }

    // MARK: Layout selection

    func testOpenDuoWideIsOpenWide() {
        XCTAssertEqual(RoundMapLayout.resolve(display(951, 669, .expanded, .open)), .openWide)
        // The simulator reports no hinge; an expanded landscape window is open.
        XCTAssertEqual(RoundMapLayout.resolve(display(951, 669, .expanded, .unknown)), .openWide)
    }

    func testOpenDuoPortraitIsOpenPortrait() {
        XCTAssertEqual(RoundMapLayout.resolve(display(669, 951, .expanded, .open)), .openPortrait)
        XCTAssertEqual(RoundMapLayout.resolve(display(669, 951, .expanded, .unknown)), .openPortrait)
    }

    func testHalfOpenLandscapeIsBook() {
        XCTAssertEqual(RoundMapLayout.resolve(display(951, 669, .expanded, .halfOpen)), .book)
    }

    func testHalfOpenPortraitFallsBackToOpenPortrait() {
        XCTAssertEqual(RoundMapLayout.resolve(display(669, 951, .expanded, .halfOpen)), .openPortrait)
    }

    func testFoldedCoverIsFolded() {
        XCTAssertEqual(RoundMapLayout.resolve(display(466, 678, .compact, .closed)), .folded)
    }

    func testFoldedCoverSidewaysUsesThePhoneLandscapePanel() {
        XCTAssertEqual(RoundMapLayout.resolve(display(678, 466, .compact, .closed)), .phoneLandscape)
    }

    func testIPhone() {
        XCTAssertEqual(RoundMapLayout.resolve(display(402, 874, .compact, .unknown)), .phonePortrait)
        XCTAssertEqual(RoundMapLayout.resolve(display(874, 402, .compact, .unknown)), .phoneLandscape)
    }

    func testZeroSizeIsPhonePortrait() {
        XCTAssertEqual(RoundMapLayout.resolve(DisplayContext()), .phonePortrait)
    }

    func testEveryLayoutShowsPenaltyBesideShot() {
        // Canvas Folded: + SHOT · + PENALTY in the action box, as everywhere.
        for layout in RoundMapLayout.allCases {
            XCTAssertFalse(layout.penaltyInOverflow, "\(layout)")
        }
    }

    func testQuestionsOpenAsBottomSheetOnlyOnFoldedAndPhonePortrait() {
        let sheets = RoundMapLayout.allCases.filter(\.asksInBottomSheet)
        XCTAssertEqual(Set(sheets), [.folded, .phonePortrait])
    }

    // MARK: Insets

    func testDuoInsetsKeepEdgesAndCorners() {
        let insets = RoundChromeInsets.make(safeArea: EdgeInsets())
        XCTAssertEqual(insets.leading, SafeChrome.edgeInset)
        XCTAssertEqual(insets.trailing, SafeChrome.edgeInset)
        XCTAssertEqual(insets.top, SafeChrome.cornerInset)
        XCTAssertEqual(insets.bottom, SafeChrome.cornerInset)
    }

    func testIPhonePortraitInsetsClearTheSystemBars() {
        let insets = RoundChromeInsets.make(safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))
        XCTAssertEqual(insets.top, 62)
        XCTAssertEqual(insets.bottom, 42) // canvas: 34 + 8
        XCTAssertEqual(insets.leading, 24)
        XCTAssertEqual(insets.trailing, 24)
    }

    func testIPhoneLandscapeInsets() {
        let insets = RoundChromeInsets.make(safeArea: EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62))
        XCTAssertEqual(insets.leading, 62)
        XCTAssertEqual(insets.trailing, 62)
        XCTAssertEqual(insets.top, 24)
        XCTAssertEqual(insets.bottom, 29)
    }

    /// A 44 pt control in each corner of the chrome area obeys SafeChrome.
    func testCornerControlsArePermittedOnEveryDisplay() {
        let cases: [(DisplayContext, EdgeInsets)] = [
            (display(466, 678, .compact, .closed), EdgeInsets()),
            (display(402, 874, .compact, .unknown), EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)),
            (display(874, 402, .compact, .unknown), EdgeInsets(top: 0, leading: 62, bottom: 21, trailing: 62)),
            (display(951, 669, .expanded, .open), EdgeInsets()),
            (display(669, 951, .expanded, .open), EdgeInsets()),
        ]
        let side = SafeChrome.minTapTarget
        for (context, safe) in cases {
            let chrome = SafeChrome(display: context)
            let insets = RoundChromeInsets.make(safeArea: safe)
            let size = context.windowSize
            let corners = [
                CGRect(x: insets.leading, y: insets.top, width: side, height: side),
                CGRect(x: size.width - insets.trailing - side, y: insets.top, width: side, height: side),
                CGRect(x: insets.leading, y: size.height - insets.bottom - side, width: side, height: side),
                CGRect(x: size.width - insets.trailing - side, y: size.height - insets.bottom - side,
                       width: side, height: side),
            ]
            for rect in corners {
                XCTAssertTrue(chrome.permits(rect), "\(rect) not permitted on \(size)")
            }
        }
    }

    // MARK: Map framing around the chrome

    func testHoleFramesLeftOfTheFoldedBoxes() throws {
        let folded = display(466, 678, .compact, .closed)
        let frames: [String: CGRect] = [
            "title": CGRect(x: 24, y: 36, width: 418, height: 52),
            "actions": CGRect(x: 278, y: 104, width: 164, height: 190),
            "clubs": CGRect(x: 278, y: 304, width: 164, height: 338),
            "card": CGRect(x: 24, y: 572, width: 244, height: 70),
        ]
        let free = try XCTUnwrap(ChromeFrames.unobstructedRect(display: folded, frames: frames))
        XCTAssertLessThanOrEqual(free.maxX, 278)
        XCTAssertGreaterThanOrEqual(free.minY, 88)
        XCTAssertLessThanOrEqual(free.maxY, 572)
    }

    func testHiddenControlsFrameTheWholeWindow() {
        let folded = display(466, 678, .compact, .closed)
        XCTAssertEqual(ChromeFrames.unobstructedRect(display: folded, frames: [:]),
                       CGRect(x: 0, y: 0, width: 466, height: 678))
    }

    func testFramesAreMadeRelativeToTheMap() throws {
        // Frames come in the screen's coordinate space; the map starts 47 pt
        // above it (it ignores the top safe area). The result is in the map's
        // own coordinates, sized to the map.
        let folded = display(466, 678, .compact, .closed)
        let mapFrame = CGRect(x: 0, y: -47, width: 466, height: 678)
        let frames: [String: CGRect] = [
            "title": CGRect(x: 24, y: 36 - 47, width: 418, height: 52),
            "card": CGRect(x: 24, y: 572 - 47, width: 244, height: 70),
        ]
        let free = try XCTUnwrap(ChromeFrames.unobstructedRect(display: folded, frames: frames, mapFrame: mapFrame))
        XCTAssertEqual(free.minY, 88)
        XCTAssertEqual(free.maxY, 572)
        XCTAssertEqual(free.width, 466)
    }

    func testTheMapSizeWinsOverTheDisplaySize() throws {
        // Under -DebugWindowSize the map is 951×669 even if the display
        // context lags; frame into the map, never past it.
        let open = display(412, 600, .expanded, .open)
        let mapFrame = CGRect(x: 0, y: 0, width: 951, height: 669)
        let free = try XCTUnwrap(ChromeFrames.unobstructedRect(
            display: open, frames: ["panel": CGRect(x: 603, y: 24, width: 324, height: 621)], mapFrame: mapFrame))
        XCTAssertEqual(free, CGRect(x: 0, y: 0, width: 603, height: 669))
    }

    func testTheFreeRectStaysInsideTheSafeArea() throws {
        // Controls hidden: no chrome, but the camera island / status bar
        // (outside `safeRect`) is not free space for the hole.
        let folded = display(466, 678, .compact, .closed)
        let mapFrame = CGRect(x: 0, y: -40, width: 466, height: 678)
        let safeRect = CGRect(x: 0, y: 0, width: 400, height: 618)
        let free = try XCTUnwrap(ChromeFrames.unobstructedRect(display: folded, frames: [:], mapFrame: mapFrame,
                                                               safeRect: safeRect))
        XCTAssertEqual(free, CGRect(x: 0, y: 40, width: 400, height: 618))
    }

    func testTheMapFrameRunsPastTheSafeArea() {
        // iPhone 17 Pro: 402×874 window, 62 pt top / 34 pt bottom insets;
        // the screen's space starts at the safe-area corner.
        let screen = CGSize(width: 402, height: 778)
        let safe = EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0)
        XCTAssertEqual(ChromeFrames.mapFrame(size: screen, safeArea: safe),
                       CGRect(x: 0, y: -62, width: 402, height: 874))
    }

    func testIPhoneChromeLandsWhereItDrawsOnTheMap() throws {
        // The 17 Pro framing bug: title, compass row and panel measured in
        // the screen's space must sit at their window positions in the map,
        // so the free rect is below the compass row and above the panel.
        let phone = display(402, 874, .compact, .unknown)
        let mapFrame = ChromeFrames.mapFrame(size: CGSize(width: 402, height: 778),
                                             safeArea: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))
        let frames: [String: CGRect] = [
            "title": CGRect(x: 24, y: 0, width: 354, height: 51),           // window 62–113
            "compass": CGRect(x: 24, y: 62, width: 44, height: 44),         // window 124–168
            "hint": CGRect(x: 76, y: 74, width: 156, height: 22),
            "panel": CGRect(x: 24, y: 547, width: 354, height: 231),        // window 609–840
        ]
        let free = try XCTUnwrap(ChromeFrames.unobstructedRect(
            display: phone, frames: frames, mapFrame: mapFrame,
            safeRect: CGRect(x: 0, y: 0, width: 402, height: 778)))
        XCTAssertEqual(free.minY, 168)
        XCTAssertEqual(free.maxY, 609)
    }

    func testEmptyMapFrameNoFraming() {
        let folded = display(466, 678, .compact, .closed)
        XCTAssertNil(ChromeFrames.unobstructedRect(display: folded, frames: [:], mapFrame: .zero))
    }

    func testNoWindowNoFraming() {
        XCTAssertNil(ChromeFrames.unobstructedRect(display: DisplayContext(), frames: ["a": .zero]))
    }

    // MARK: Mode traits

    func testModeTraits() {
        XCTAssertTrue(RoundMapMode.tracking.tracksShots)
        XCTAssertTrue(RoundMapMode.tracking.finishAsksPutts)
        XCTAssertTrue(RoundMapMode.tracking.allowsHoldToAdd)
        XCTAssertFalse(RoundMapMode.tracking.entryUsesScoreGrid)
        XCTAssertFalse(RoundMapMode.casual.tracksShots)
        XCTAssertTrue(RoundMapMode.casual.entryUsesScoreGrid)
        XCTAssertFalse(RoundMapMode.casual.allowsHoldToAdd)
    }
}
