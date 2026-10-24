import SwiftUI
import XCTest
@testable import GolfCaddie

@MainActor
final class AdaptiveLayoutTests: XCTestCase {
    // MARK: LayoutClass

    func testDuoCoverIsCompact() {
        XCTAssertEqual(LayoutClass.resolve(windowSize: CGSize(width: 466, height: 678),
                                           horizontal: .compact, vertical: .regular), .compact)
    }

    func testDuoInnerIsExpandedInBothOrientations() {
        XCTAssertEqual(LayoutClass.resolve(windowSize: CGSize(width: 951, height: 669),
                                           horizontal: .regular, vertical: .compact), .expanded)
        XCTAssertEqual(LayoutClass.resolve(windowSize: CGSize(width: 669, height: 951),
                                           horizontal: .regular, vertical: .regular), .expanded)
    }

    func testProMaxLandscapeStaysCompact() {
        // Regular width alone (Pro Max landscape) must not flip to expanded.
        XCTAssertEqual(LayoutClass.resolve(windowSize: CGSize(width: 956, height: 440),
                                           horizontal: .regular, vertical: .compact), .compact)
    }

    func testZeroSizeIsCompact() {
        XCTAssertEqual(LayoutClass.resolve(windowSize: .zero, horizontal: nil, vertical: nil), .compact)
    }

    // MARK: Yardage source stamp (B35 watch-first)

    func testYardageStampWatchWhenStreamedFixIsFresh() {
        let now = Date()
        let watch = WatchFix(latitude: 33.03, longitude: -117.06, horizontalAccuracy: 5,
                             timestamp: now.timeIntervalSince1970 - 8)
        let phone = GeoFix(latitude: 33.031, longitude: -117.061, horizontalAccuracy: 4,
                           timestamp: now.timeIntervalSince1970)
        let choice = LocationPreference.choose(watch: watch, phone: phone, at: now,
                                               watchMaxAge: LocationPreference.streamedWatchFixMaxAge)
        let fix = YardageFixAdapter.current(choice: choice)
        XCTAssertEqual(fix?.sourceLabel, "WATCH GPS")
        XCTAssertEqual(fix?.coordinate.latitude, 33.03)
    }

    func testYardageStampPhoneWhenWatchStale() {
        let now = Date()
        let watch = WatchFix(latitude: 33.03, longitude: -117.06, horizontalAccuracy: 5,
                             timestamp: now.timeIntervalSince1970 - 30)
        let phone = GeoFix(latitude: 33.031, longitude: -117.061, horizontalAccuracy: 4,
                           timestamp: now.timeIntervalSince1970)
        let choice = LocationPreference.choose(watch: watch, phone: phone, at: now,
                                               watchMaxAge: LocationPreference.streamedWatchFixMaxAge)
        XCTAssertEqual(YardageFixAdapter.current(choice: choice)?.sourceLabel, "PHONE GPS")
    }

    func testYardageNilWithoutAnyFix() {
        let choice = LocationPreference.choose(watch: nil, phone: nil, at: Date())
        XCTAssertNil(YardageFixAdapter.current(choice: choice))
    }
}
