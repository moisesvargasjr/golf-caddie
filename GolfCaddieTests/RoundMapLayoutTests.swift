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

    func testOnlyFoldedPutsPenaltyInTheOverflowMenu() {
        for layout in RoundMapLayout.allCases {
            XCTAssertEqual(layout.penaltyInOverflow, layout == .folded, "\(layout)")
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

    func testNoWindowNoFraming() {
        XCTAssertNil(ChromeFrames.unobstructedRect(display: DisplayContext(), frames: ["a": .zero]))
    }

    // MARK: Mode traits

    func testModeTraits() {
        XCTAssertTrue(RoundMapMode.tracking.tracksShots)
        XCTAssertTrue(RoundMapMode.tracking.finishAsksPutts)
        XCTAssertTrue(RoundMapMode.tracking.allowsHoldToAdd)
        XCTAssertFalse(RoundMapMode.tracking.liveHoleIsHandEntry)
        XCTAssertFalse(RoundMapMode.casual.tracksShots)
        XCTAssertTrue(RoundMapMode.casual.liveHoleIsHandEntry)
        XCTAssertFalse(RoundMapMode.casual.allowsHoldToAdd)
    }
}
