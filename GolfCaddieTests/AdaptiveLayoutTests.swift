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

    // MARK: RoundStageMode

    private func context(_ w: CGFloat, _ h: CGFloat, _ posture: HingePosture,
                         _ cls: LayoutClass = .expanded) -> DisplayContext {
        DisplayContext(layoutClass: cls, posture: posture, windowSize: CGSize(width: w, height: h))
    }

    func testModeResolution() {
        XCTAssertEqual(RoundStageMode.resolve(context(466, 678, .closed, .compact), isCasualMode: false), .overlay)
        XCTAssertEqual(RoundStageMode.resolve(context(951, 669, .open), isCasualMode: false), .wide)
        XCTAssertEqual(RoundStageMode.resolve(context(951, 669, .unknown), isCasualMode: false), .wide)
        XCTAssertEqual(RoundStageMode.resolve(context(951, 669, .halfOpen), isCasualMode: false), .twoPage)
        XCTAssertEqual(RoundStageMode.resolve(context(669, 951, .open), isCasualMode: false), .commandPortrait)
        XCTAssertEqual(RoundStageMode.resolve(context(669, 951, .halfOpen), isCasualMode: false), .tabletop)
    }

    func testCasualModeAlwaysOverlay() {
        XCTAssertEqual(RoundStageMode.resolve(context(951, 669, .open), isCasualMode: true), .overlay)
    }

    // MARK: RoundStageGeometry

    func testOverlayGivesEveryoneFullBounds() {
        let size = CGSize(width: 375, height: 640)
        let g = RoundStageGeometry.make(mode: .overlay, size: size)
        let full = CGRect(origin: .zero, size: size)
        XCTAssertEqual(g.map, full)
        XCTAssertEqual(g.panel, full)
        XCTAssertEqual(g.actions, full)
    }

    func testTwoPageKeepsControlsOffTheHinge() {
        let g = RoundStageGeometry.make(mode: .twoPage, size: CGSize(width: 867, height: 635), hinge: 475.5)
        XCTAssertEqual(g.map.maxX, 475.5, accuracy: 0.01)
        for rect in [g.header, g.panel, g.actions] {
            XCTAssertGreaterThanOrEqual(rect.minX, 475.5 + RoundStageGeometry.hingeGutter)
        }
    }

    func testTabletopKeepsEverythingOffTheHingeBand() {
        let hinge: CGFloat = 475
        let g = RoundStageGeometry.make(mode: .tabletop, size: CGSize(width: 669, height: 951), hinge: hinge)
        XCTAssertLessThanOrEqual(g.header.maxY, hinge - RoundStageGeometry.hingeGutter)
        XCTAssertLessThanOrEqual(g.map.maxY, hinge - RoundStageGeometry.hingeGutter)
        XCTAssertGreaterThanOrEqual(g.panel.minY, hinge + RoundStageGeometry.hingeGutter)
        XCTAssertEqual(g.map.width, RoundStageGeometry.tabletopMapWidth)
    }

    func testWideRailGeometry() {
        let size = CGSize(width: 867, height: 635)
        let g = RoundStageGeometry.make(mode: .wide, size: size)
        XCTAssertEqual(g.panel.width, RoundStageGeometry.wideRailWidth)
        XCTAssertEqual(g.panel.maxX, size.width - RoundStageGeometry.margin, accuracy: 0.01)
        XCTAssertLessThan(g.map.maxX, g.panel.minX)
    }

    func testCommandPortraitSplitsMapAndPanel() {
        let g = RoundStageGeometry.make(mode: .commandPortrait, size: CGSize(width: 626, height: 890))
        XCTAssertEqual(g.map.width, 316, accuracy: 1)
        XCTAssertGreaterThan(g.panel.minX, g.map.maxX)
        XCTAssertLessThan(g.panel.maxY, g.actions.minY)
        XCTAssertGreaterThan(g.map.minY, g.header.maxY)
    }

    // MARK: InRoundFormat

    func testScoreText() {
        XCTAssertNil(InRoundFormat.scoreText(holes: [(par: 4, strokes: 3, confirmed: false)]))
        XCTAssertEqual(InRoundFormat.scoreText(holes: [
            (par: 4, strokes: 5, confirmed: true),
            (par: 3, strokes: 4, confirmed: true),
            (par: 5, strokes: 2, confirmed: false),
        ]), "+2 THRU 2")
        XCTAssertEqual(InRoundFormat.scoreText(holes: [(par: 4, strokes: 4, confirmed: true)]), "E THRU 1")
        XCTAssertEqual(InRoundFormat.scoreText(holes: [(par: 5, strokes: 4, confirmed: true)]), "-1 THRU 1")
        // No par: counts toward THRU only.
        XCTAssertEqual(InRoundFormat.scoreText(holes: [(par: nil, strokes: 6, confirmed: true)]), "E THRU 1")
    }

    func testSourceText() {
        XCTAssertEqual(InRoundFormat.sourceText(.watchAuto), "WATCH AUTO")
        XCTAssertEqual(InRoundFormat.sourceText(.button), "PHONE")
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

    // MARK: Control consistency

    /// Manual logging is only the small "+ SHOT" secondary: no view may compose
    /// a big Log/Mark shot button. Scans the app's view sources (the simulator
    /// can read the host checkout through #filePath).
    func testNoBigLogShotControlInViews() throws {
        let views = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("GolfCaddie/Views")
        let enumerator = try XCTUnwrap(FileManager.default.enumerator(at: views, includingPropertiesForKeys: nil))
        let files = enumerator.compactMap { $0 as? URL }.filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty)
        let banned = ["LogShotButton", "logShotCTA", "Text(\"Log\")", "\"Log shot\""]
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            for term in banned {
                XCTAssertFalse(text.contains(term), "\(file.lastPathComponent) contains \(term)")
            }
        }
    }

    func testSecondaryShotLabelIsShort() {
        let actions = InRoundActions(
            logShot: {}, markMissed: {}, putt: {}, undo: {}, finishHole: {}, selectClub: { _ in },
            openBag: {}, openCard: {}, endRound: {}, stepHole: { _ in }, openHoleGrid: {},
            linkCourse: {}, recenterMap: {})
        let snapshot = InRoundSnapshot(
            holeNumber: 1, par: 4, holeLengthText: nil, courseName: nil, scoreText: nil, pin: nil,
            needsCourseLink: true, pinSourceText: nil, gpsText: "", gpsColor: .clear, clubs: [],
            bagText: "", strokes: [], selectedClubShort: nil, shots: 0, penalties: 0,
            isMarking: false, canUndo: false, errorText: nil, isFollowingMap: true, watchDetecting: false)
        XCTAssertEqual(SecondaryActionRow(snapshot: snapshot, actions: actions).shotTitle, "+ SHOT")
    }
}
