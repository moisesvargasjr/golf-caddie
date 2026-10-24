import SwiftUI
import XCTest
@testable import GolfCaddie

final class HomeLayoutTests: XCTestCase {
    private func display(_ w: CGFloat, _ h: CGFloat, _ cls: LayoutClass,
                         _ posture: HingePosture = .unknown) -> DisplayContext {
        DisplayContext(layoutClass: cls, posture: posture, windowSize: CGSize(width: w, height: h))
    }

    // MARK: Layout choice

    func testOpenWideGetsTheTwoPageHome() {
        XCTAssertEqual(HomeLayout.resolve(display(951, 669, .expanded, .open)), .openWide)
        // Book pose and the simulator's unknown posture are the same window.
        XCTAssertEqual(HomeLayout.resolve(display(951, 669, .expanded, .halfOpen)), .openWide)
        XCTAssertEqual(HomeLayout.resolve(display(951, 669, .expanded)), .openWide)
    }

    func testEverythingElseGetsTheSingleColumn() {
        XCTAssertEqual(HomeLayout.resolve(display(466, 678, .compact, .closed)), .single)
        XCTAssertEqual(HomeLayout.resolve(display(669, 951, .expanded, .open)), .single)
        XCTAssertEqual(HomeLayout.resolve(display(402, 874, .compact)), .single)
        XCTAssertEqual(HomeLayout.resolve(display(874, 402, .compact)), .single)
        XCTAssertEqual(HomeLayout.resolve(DisplayContext()), .single)
    }

    // MARK: Pages

    func testPagesSitInsideTheEdgesAndOffTheHinge() throws {
        let size = CGSize(width: 951, height: 669)
        let pages = try XCTUnwrap(HomeLayout.pages(windowSize: size, safeArea: EdgeInsets()))
        let chrome = SafeChrome(display: display(951, 669, .expanded, .open))
        let hinge = try XCTUnwrap(chrome.hingeExclusion)

        XCTAssertEqual(pages.left.minX, SafeChrome.edgeInset)
        XCTAssertEqual(pages.left.minY, SafeChrome.edgeInset)
        XCTAssertEqual(pages.right.maxX, size.width - SafeChrome.edgeInset)
        XCTAssertEqual(pages.right.maxY, size.height - SafeChrome.edgeInset)
        XCTAssertEqual(pages.left.maxX, hinge.minX)
        XCTAssertEqual(pages.right.minX, hinge.maxX)
        XCTAssertFalse(pages.left.intersects(hinge))
        XCTAssertFalse(pages.right.intersects(hinge))
        XCTAssertTrue(chrome.permits(pages.left.insetBy(dx: 0, dy: SafeChrome.cornerInset)))
        XCTAssertTrue(chrome.permits(pages.right.insetBy(dx: 0, dy: SafeChrome.cornerInset)))
    }

    func testLargerSystemInsetsWin() throws {
        let size = CGSize(width: 951, height: 669)
        let safe = EdgeInsets(top: 32, leading: 0, bottom: 20, trailing: 50)
        let pages = try XCTUnwrap(HomeLayout.pages(windowSize: size, safeArea: safe))
        XCTAssertEqual(pages.left.minY, 32)
        XCTAssertEqual(pages.right.minY, 32)
        XCTAssertEqual(pages.left.maxY, size.height - SafeChrome.edgeInset)
        XCTAssertEqual(pages.left.minX, SafeChrome.edgeInset)
        XCTAssertEqual(pages.right.maxX, size.width - 50)
    }

    func testNoPagesWithoutAHinge() {
        XCTAssertNil(HomeLayout.pages(windowSize: CGSize(width: 669, height: 951), safeArea: EdgeInsets()))
        XCTAssertNil(HomeLayout.pages(windowSize: .zero, safeArea: EdgeInsets()))
    }
}
