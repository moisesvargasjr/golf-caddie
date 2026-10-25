import SwiftUI
import XCTest
@testable import GolfCaddie

final class SafeChromeTests: XCTestCase {
    // MARK: Fixtures

    private func chrome(_ w: CGFloat, _ h: CGFloat, _ cls: LayoutClass,
                        _ posture: HingePosture) -> SafeChrome {
        SafeChrome(display: DisplayContext(layoutClass: cls, posture: posture,
                                           windowSize: CGSize(width: w, height: h)))
    }

    private var folded: SafeChrome { chrome(466, 678, .compact, .closed) }
    private var openWide: SafeChrome { chrome(951, 669, .expanded, .open) }
    private var openPortrait: SafeChrome { chrome(669, 951, .expanded, .open) }
    private var book: SafeChrome { chrome(951, 669, .expanded, .halfOpen) }
    private var iPhonePortrait: SafeChrome { chrome(402, 874, .compact, .unknown) }
    private var iPhoneLandscape: SafeChrome { chrome(874, 402, .compact, .unknown) }

    // MARK: Constants

    func testConstants() {
        XCTAssertEqual(SafeChrome.edgeInset, 24)
        XCTAssertGreaterThan(SafeChrome.cornerInset, SafeChrome.edgeInset)
        XCTAssertEqual(SafeChrome.cornerInset, 36)
        XCTAssertEqual(SafeChrome.minTapTarget, 44)
        XCTAssertEqual(SafeChrome.minTapTarget, InRoundMetrics.minTouch)
        // The band is the hinge gutter on each side.
        XCTAssertEqual(SafeChrome.hingeBandWidth, SafeChrome.hingeGutter * 2)
    }

    // MARK: Hinge exclusion

    func testNoHingeOnCompactScreens() {
        XCTAssertNil(folded.hingeExclusion)
        XCTAssertNil(iPhonePortrait.hingeExclusion)
        XCTAssertNil(iPhoneLandscape.hingeExclusion)
        // A compact window never has a hinge, whatever the posture says.
        XCTAssertNil(chrome(466, 678, .compact, .open).hingeExclusion)
    }

    func testOpenWideHasVerticalBandAtCentre() {
        XCTAssertEqual(openWide.hingeExclusion, CGRect(x: 459.5, y: 0, width: 32, height: 669))
    }

    func testBookPoseHasVerticalBandAtCentre() {
        XCTAssertEqual(book.hingeExclusion, CGRect(x: 459.5, y: 0, width: 32, height: 669))
    }

    func testOpenPortraitHasHorizontalBandAtCentre() {
        XCTAssertEqual(openPortrait.hingeExclusion, CGRect(x: 0, y: 459.5, width: 669, height: 32))
    }

    func testZeroWindowHasNoHingeOrRegions() {
        let empty = chrome(0, 0, .expanded, .open)
        XCTAssertNil(empty.hingeExclusion)
        XCTAssertEqual(empty.controlRegions(), [])
    }

    // MARK: Control regions

    func testFoldedHasOneRegionInsetFromEveryEdge() {
        XCTAssertEqual(folded.controlRegions(), [CGRect(x: 24, y: 24, width: 418, height: 630)])
    }

    func testIPhoneRegionsInBothOrientations() {
        XCTAssertEqual(iPhonePortrait.controlRegions(), [CGRect(x: 24, y: 24, width: 354, height: 826)])
        XCTAssertEqual(iPhoneLandscape.controlRegions(), [CGRect(x: 24, y: 24, width: 826, height: 354)])
    }

    func testOpenWideSplitsIntoTwoPagesAroundTheHinge() {
        XCTAssertEqual(openWide.controlRegions(), [
            CGRect(x: 24, y: 24, width: 435.5, height: 621),
            CGRect(x: 491.5, y: 24, width: 435.5, height: 621),
        ])
    }

    func testBookMatchesOpenWideRegions() {
        XCTAssertEqual(book.controlRegions(), openWide.controlRegions())
    }

    func testOpenPortraitSplitsIntoTopAndBottomPages() {
        XCTAssertEqual(openPortrait.controlRegions(), [
            CGRect(x: 24, y: 24, width: 621, height: 435.5),
            CGRect(x: 24, y: 491.5, width: 621, height: 435.5),
        ])
    }

    func testRegionsNeverTouchTheHingeBand() {
        for safe in [openWide, openPortrait, book] {
            guard let band = safe.hingeExclusion else {
                XCTFail("expected a hinge band")
                continue
            }
            for region in safe.controlRegions() {
                let clear = region.maxX <= band.minX || region.minX >= band.maxX
                    || region.maxY <= band.minY || region.minY >= band.maxY
                XCTAssertTrue(clear, "\(region) overlaps hinge \(band)")
            }
        }
    }

    func testControlRegionsForAnExplicitSize() {
        // Same context, smaller stage: the hinge is located from the size given.
        let regions = openWide.controlRegions(in: CGSize(width: 800, height: 600))
        XCTAssertEqual(regions, [
            CGRect(x: 24, y: 24, width: 360, height: 552),
            CGRect(x: 416, y: 24, width: 360, height: 552),
        ])
    }

    // MARK: Permits

    func testPermitsRespectsEdgeInset() {
        XCTAssertTrue(folded.permits(CGRect(x: 100, y: 100, width: 44, height: 44)))
        XCTAssertFalse(folded.permits(CGRect(x: 10, y: 100, width: 44, height: 44)))
        XCTAssertFalse(folded.permits(CGRect(x: 100, y: 640, width: 44, height: 44)))
    }

    func testPermitsKeepsCornersClear() {
        // 24 pt from both edges is inside the 36 pt corner square.
        XCTAssertFalse(folded.permits(CGRect(x: 24, y: 24, width: 44, height: 44)))
        XCTAssertFalse(folded.permits(CGRect(x: 398, y: 610, width: 44, height: 44)))
        // Far enough along one axis clears the corner.
        XCTAssertTrue(folded.permits(CGRect(x: 24, y: 36, width: 44, height: 44)))
        XCTAssertTrue(folded.permits(CGRect(x: 36, y: 24, width: 44, height: 44)))
    }

    func testPermitsRejectsAnythingOnTheHinge() {
        XCTAssertFalse(openWide.permits(CGRect(x: 440, y: 300, width: 44, height: 44)))
        XCTAssertTrue(openWide.permits(CGRect(x: 491.5, y: 300, width: 44, height: 44)))
        XCTAssertFalse(openPortrait.permits(CGRect(x: 300, y: 450, width: 44, height: 44)))
        // The iPhone has no hinge: the centre is fine.
        XCTAssertTrue(iPhonePortrait.permits(CGRect(x: 179, y: 415, width: 44, height: 44)))
    }

    func testCornerExclusionsAreFourSquares() {
        let corners = folded.cornerExclusions()
        XCTAssertEqual(corners.count, 4)
        XCTAssertTrue(corners.contains(CGRect(x: 0, y: 0, width: 36, height: 36)))
        XCTAssertTrue(corners.contains(CGRect(x: 430, y: 642, width: 36, height: 36)))
    }

    // MARK: Unobstructed rect

    func testUnobstructedWithNothingIsTheWholeWindow() {
        let size = CGSize(width: 402, height: 874)
        XCTAssertEqual(iPhonePortrait.unobstructedRect(windowSize: size, occupied: []),
                       CGRect(origin: .zero, size: size))
    }

    func testUnobstructedLeftOfARightPanel() {
        let panel = CGRect(x: 603, y: 24, width: 324, height: 621)
        XCTAssertEqual(openWide.unobstructedRect(windowSize: CGSize(width: 951, height: 669),
                                                 occupied: [panel]),
                       CGRect(x: 0, y: 0, width: 603, height: 669))
    }

    func testUnobstructedAboveABottomPanel() {
        let panel = CGRect(x: 24, y: 674, width: 354, height: 176)
        XCTAssertEqual(iPhonePortrait.unobstructedRect(windowSize: CGSize(width: 402, height: 874),
                                                       occupied: [panel]),
                       CGRect(x: 0, y: 0, width: 402, height: 674))
    }

    func testUnobstructedPicksTheLargestAreaAmongSeveralObstacles() {
        // Folded: yardage card bottom-left, stacked boxes on the right.
        let card = CGRect(x: 24, y: 520, width: 200, height: 134)
        let boxes = CGRect(x: 290, y: 300, width: 152, height: 354)
        XCTAssertEqual(folded.unobstructedRect(windowSize: CGSize(width: 466, height: 678),
                                               occupied: [card, boxes]),
                       CGRect(x: 0, y: 0, width: 290, height: 520))
    }

    func testUnobstructedIgnoresObstaclesOutsideAndEmpty() {
        let size = CGSize(width: 466, height: 678)
        let outside = CGRect(x: 600, y: 0, width: 50, height: 50)
        XCTAssertEqual(folded.unobstructedRect(windowSize: size, occupied: [outside, .zero, .null]),
                       CGRect(origin: .zero, size: size))
    }

    func testUnobstructedFullyCoveredIsZero() {
        let size = CGSize(width: 100, height: 100)
        XCTAssertEqual(folded.unobstructedRect(windowSize: size,
                                               occupied: [CGRect(x: -10, y: -10, width: 200, height: 200)]),
                       .zero)
        XCTAssertEqual(folded.unobstructedRect(windowSize: .zero, occupied: []), .zero)
    }

    // MARK: Safe-area merge

    func testInsetsTakeTheLargerOfSafeAreaAndEdgeInset() {
        let merged = iPhonePortrait.insets(including: EdgeInsets(top: 62, leading: 0, bottom: 34, trailing: 0))
        XCTAssertEqual(merged.top, 62)
        XCTAssertEqual(merged.leading, 24)
        XCTAssertEqual(merged.bottom, 34)
        XCTAssertEqual(merged.trailing, 24)
    }
}
