import CoreLocation
import UIKit
import XCTest
@testable import GolfCaddie

/// `HoleFraming`: tee and green land inside the unobstructed rect that the
/// layout reports (SafeChrome.unobstructedRect), on every window the Duo v2
/// layouts use, at any heading.
final class HoleFramingTests: XCTestCase {
    // MARK: Fixtures (0.0001 deg of latitude is about 11 m)

    private struct HoleFixture {
        let name: String
        let tee: CLLocationCoordinate2D
        let green: CLLocationCoordinate2D
        let shots: [CLLocationCoordinate2D]
    }

    private let holes: [HoleFixture] = [
        HoleFixture(name: "north par 4", tee: .init(latitude: 33.0000, longitude: -117.0),
                    green: .init(latitude: 33.0036, longitude: -117.0), shots: []),
        HoleFixture(name: "east par 5", tee: .init(latitude: 33.0, longitude: -117.0),
                    green: .init(latitude: 33.0, longitude: -116.9948),
                    shots: [.init(latitude: 33.0003, longitude: -116.9975)]),
        HoleFixture(name: "dogleg", tee: .init(latitude: 33.0, longitude: -117.0),
                    green: .init(latitude: 33.0030, longitude: -116.9990),
                    shots: [.init(latitude: 33.0020, longitude: -117.0015)]),
        HoleFixture(name: "par 3", tee: .init(latitude: 33.0, longitude: -117.0),
                    green: .init(latitude: 33.0012, longitude: -117.0003), shots: []),
    ]

    private func chrome(_ size: CGSize, _ cls: LayoutClass, _ posture: HingePosture) -> SafeChrome {
        SafeChrome(display: DisplayContext(layoutClass: cls, posture: posture, windowSize: size))
    }

    /// (name, window, unobstructed rect) for each layout the plan names.
    private var layouts: [(String, CGSize, CGRect)] {
        let folded = CGSize(width: 466, height: 678)
        let foldedRect = chrome(folded, .compact, .closed).unobstructedRect(windowSize: folded, occupied: [
            CGRect(x: 24, y: 678 - 24 - 132, width: 190, height: 132), // yardage card, bottom-left
            CGRect(x: 466 - 24 - 150, y: 678 - 24 - 300, width: 150, height: 300), // stacked boxes
        ])
        let open = CGSize(width: 951, height: 669)
        let openRect = chrome(open, .expanded, .open).unobstructedRect(windowSize: open, occupied: [
            CGRect(x: 951 - 24 - 300, y: 24, width: 300, height: 669 - 48), // command panel
        ])
        let phone = CGSize(width: 402, height: 874)
        let phoneRect = chrome(phone, .compact, .unknown).unobstructedRect(windowSize: phone, occupied: [
            CGRect(x: 0, y: 874 - 300, width: 402, height: 300), // bottom panel
        ])
        return [
            ("folded 466x678", folded, foldedRect),
            ("open 951x669", open, openRect),
            ("iPhone 402x874 + bottom panel", phone, phoneRect),
            ("iPhone, controls hidden", phone, CGRect(origin: .zero, size: phone)),
        ]
    }

    private func assertInside(_ point: CLLocationCoordinate2D, _ frame: HoleFrame, _ rect: CGRect,
                              _ window: CGSize, _ message: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        let target = rect.insetBy(dx: HoleFraming.padding - 1, dy: HoleFraming.padding - 1)
        let screen = HoleFraming.project(point, frame: frame, windowSize: window)
        XCTAssertTrue(target.contains(screen), "\(message): \(screen) not in \(target)", file: file, line: line)
    }

    // MARK: Fit

    func testTeeGreenAndShotsLandInsideTheUnobstructedRectOnEveryLayout() throws {
        for (layoutName, window, rect) in layouts {
            XCTAssertGreaterThan(rect.width, 100, layoutName)
            for hole in holes {
                let holeUp = HoleFraming.holeUpHeading(tee: hole.tee, green: hole.green, shots: hole.shots) ?? 0
                for heading in [holeUp, 0, 37, 271] {
                    let frame = try XCTUnwrap(HoleFraming.fitHole(
                        tee: hole.tee, green: hole.green, shots: hole.shots,
                        unobstructedRect: rect, in: window, heading: heading))
                    let label = "\(layoutName) / \(hole.name) / heading \(heading)"
                    assertInside(hole.tee, frame, rect, window, "\(label) tee")
                    assertInside(hole.green, frame, rect, window, "\(label) green")
                    for shot in hole.shots { assertInside(shot, frame, rect, window, "\(label) shot") }
                }
            }
        }
    }

    func testHoleUpPutsTheGreenStraightAboveTheTee() throws {
        for (layoutName, window, rect) in layouts {
            for hole in holes {
                let heading = try XCTUnwrap(HoleFraming.holeUpHeading(tee: hole.tee, green: hole.green))
                let frame = try XCTUnwrap(HoleFraming.fitHole(
                    tee: hole.tee, green: hole.green, shots: [], unobstructedRect: rect, in: window, heading: heading))
                let tee = HoleFraming.project(hole.tee, frame: frame, windowSize: window)
                let green = HoleFraming.project(hole.green, frame: frame, windowSize: window)
                XCTAssertLessThan(green.y, tee.y, "\(layoutName) / \(hole.name): green above tee")
                XCTAssertEqual(green.x, tee.x, accuracy: 1, "\(layoutName) / \(hole.name): straight up")
            }
        }
    }

    func testTheGreenMarkerClearsTheTopOfTheRect() throws {
        // The flag balloon is ~40 pt tall above the green's coordinate.
        for (layoutName, window, rect) in layouts {
            for hole in holes {
                let heading = try XCTUnwrap(HoleFraming.holeUpHeading(tee: hole.tee, green: hole.green))
                let frame = try XCTUnwrap(HoleFraming.fitHole(
                    tee: hole.tee, green: hole.green, shots: hole.shots,
                    unobstructedRect: rect, in: window, heading: heading))
                let green = HoleFraming.project(hole.green, frame: frame, windowSize: window)
                XCTAssertGreaterThanOrEqual(green.y - 40, rect.minY + 8, "\(layoutName) / \(hole.name)")
            }
        }
    }

    func testUnprojectIsTheInverseOfProject() throws {
        let window = CGSize(width: 466, height: 678)
        let hole = holes[2]
        let frame = try XCTUnwrap(HoleFraming.fitHole(
            tee: hole.tee, green: hole.green, shots: hole.shots,
            unobstructedRect: CGRect(x: 0, y: 88, width: 278, height: 484), in: window, heading: 37))
        for point in [CGPoint(x: 10, y: 20), CGPoint(x: 233, y: 339), CGPoint(x: 400, y: 650)] {
            let coordinate = HoleFraming.coordinate(at: point, frame: frame, windowSize: window)
            let back = HoleFraming.project(coordinate, frame: frame, windowSize: window)
            XCTAssertEqual(back.x, point.x, accuracy: 0.05)
            XCTAssertEqual(back.y, point.y, accuracy: 0.05)
        }
    }

    func testRecenteringForAnOffsetCameraCentre() throws {
        // If the map draws its camera centre `offset` points away from the
        // view centre, the camera must look at what the frame puts there.
        let window = CGSize(width: 466, height: 678)
        let hole = holes[0]
        let frame = try XCTUnwrap(HoleFraming.fitHole(
            tee: hole.tee, green: hole.green, shots: [],
            unobstructedRect: CGRect(origin: .zero, size: window), in: window, heading: 0))
        let offset = CGVector(dx: 0, dy: 23)
        let shifted = frame.recentered(forCameraCentreOffset: offset, windowSize: window)
        XCTAssertEqual(shifted.metersPerPoint, frame.metersPerPoint)
        XCTAssertEqual(shifted.heading, frame.heading)
        let at = HoleFraming.project(shifted.center, frame: frame, windowSize: window)
        XCTAssertEqual(at.x, window.width / 2, accuracy: 0.05)
        XCTAssertEqual(at.y, window.height / 2 + 23, accuracy: 0.05)
        XCTAssertEqual(frame.recentered(forCameraCentreOffset: .zero, windowSize: window), frame)
    }

    func testTheHoleIsCentredInTheRectNotTheWindow() throws {
        let window = CGSize(width: 402, height: 874)
        let rect = CGRect(x: 0, y: 0, width: 402, height: 574) // bottom panel 300 tall
        let hole = holes[0]
        let frame = try XCTUnwrap(HoleFraming.fitHole(
            tee: hole.tee, green: hole.green, shots: [], unobstructedRect: rect, in: window, heading: 0))
        let tee = HoleFraming.project(hole.tee, frame: frame, windowSize: window)
        let green = HoleFraming.project(hole.green, frame: frame, windowSize: window)
        // Centred in the padded rect below the marker headroom.
        XCTAssertEqual((tee.y + green.y) / 2, rect.midY + HoleFraming.markerHeadroom / 2, accuracy: 1)
        XCTAssertEqual((tee.x + green.x) / 2, rect.midX, accuracy: 1)
        // Tight: the long axis fills the padded rect.
        XCTAssertEqual(tee.y - green.y, rect.height - 2 * HoleFraming.padding - HoleFraming.markerHeadroom,
                       accuracy: 1)
        // The camera centre itself is the window centre.
        let centre = HoleFraming.project(frame.center, frame: frame, windowSize: window)
        XCTAssertEqual(centre.x, window.width / 2, accuracy: 0.01)
        XCTAssertEqual(centre.y, window.height / 2, accuracy: 0.01)
    }

    func testTheHoleShrinksALittleWhenTheControlsShow() throws {
        let window = CGSize(width: 402, height: 874)
        let hole = holes[0]
        let hidden = try XCTUnwrap(HoleFraming.fitHole(
            tee: hole.tee, green: hole.green, shots: [],
            unobstructedRect: CGRect(origin: .zero, size: window), in: window, heading: 0))
        let shown = try XCTUnwrap(HoleFraming.fitHole(
            tee: hole.tee, green: hole.green, shots: [],
            unobstructedRect: CGRect(x: 0, y: 0, width: 402, height: 574), in: window, heading: 0))
        XCTAssertGreaterThan(shown.metersPerPoint, hidden.metersPerPoint, "more metres per point = smaller hole")
    }

    func testASinglePointUsesTheMinimumSpan() throws {
        let window = CGSize(width: 466, height: 678)
        let point = CLLocationCoordinate2D(latitude: 33, longitude: -117)
        let frame = try XCTUnwrap(HoleFraming.fitHole(
            tee: point, green: point, shots: [], unobstructedRect: CGRect(origin: .zero, size: window),
            in: window, heading: 0))
        let shortSide = Double(min(window.width, window.height) - 2 * HoleFraming.padding)
        XCTAssertEqual(frame.metersPerPoint, HoleFraming.minimumSpanMeters / shortSide, accuracy: 1e-9)
    }

    func testNothingToFrameOrNoWindowGivesNil() {
        let window = CGSize(width: 402, height: 874)
        XCTAssertNil(HoleFraming.fitHole(tee: nil, green: nil, shots: [],
                                         unobstructedRect: .zero, in: window, heading: 0))
        XCTAssertNil(HoleFraming.fitHole(tee: .init(latitude: 33, longitude: -117), green: nil, shots: [],
                                         unobstructedRect: .zero, in: .zero, heading: 0))
    }

    func testAnEmptyRectFallsBackToTheWholeWindow() throws {
        let window = CGSize(width: 402, height: 874)
        let hole = holes[0]
        let a = try XCTUnwrap(HoleFraming.fitHole(tee: hole.tee, green: hole.green, shots: [],
                                                  unobstructedRect: .zero, in: window, heading: 0))
        let b = try XCTUnwrap(HoleFraming.fitHole(tee: hole.tee, green: hole.green, shots: [],
                                                  unobstructedRect: CGRect(origin: .zero, size: window),
                                                  in: window, heading: 0))
        XCTAssertEqual(a, b)
    }

    func testASliverRectFallsBackToTheWholeWindow() throws {
        // A rect a few points wide (mismatched coordinate spaces) must not
        // zoom the map out to the whole county.
        let window = CGSize(width: 951, height: 669)
        XCTAssertEqual(HoleFraming.usableRect(CGRect(x: 400, y: 0, width: 3, height: 669), in: window),
                       CGRect(origin: .zero, size: window))
        let hole = holes[0]
        let sliver = try XCTUnwrap(HoleFraming.fitHole(tee: hole.tee, green: hole.green, shots: [],
                                                       unobstructedRect: CGRect(x: 400, y: 0, width: 3, height: 669),
                                                       in: window, heading: 0))
        let whole = try XCTUnwrap(HoleFraming.fitHole(tee: hole.tee, green: hole.green, shots: [],
                                                      unobstructedRect: CGRect(origin: .zero, size: window),
                                                      in: window, heading: 0))
        XCTAssertEqual(sliver, whole)
    }

    // MARK: Insets

    func testEdgeInsetsAreTheWindowMinusTheRect() {
        let window = CGSize(width: 402, height: 874)
        let insets = HoleFraming.edgeInsets(unobstructedRect: CGRect(x: 0, y: 0, width: 402, height: 574),
                                            in: window)
        XCTAssertEqual(insets, UIEdgeInsets(top: 0, left: 0, bottom: 300, right: 0))
        let open = HoleFraming.edgeInsets(unobstructedRect: CGRect(x: 0, y: 0, width: 603, height: 669),
                                          in: CGSize(width: 951, height: 669))
        XCTAssertEqual(open, UIEdgeInsets(top: 0, left: 0, bottom: 0, right: 348))
        XCTAssertEqual(HoleFraming.edgeInsets(unobstructedRect: .zero, in: window), .zero)
    }

    func testUsableRectClipsToTheWindow() {
        let window = CGSize(width: 100, height: 100)
        XCTAssertEqual(HoleFraming.usableRect(CGRect(x: -10, y: 50, width: 200, height: 100), in: window),
                       CGRect(x: 0, y: 50, width: 100, height: 50))
        XCTAssertEqual(HoleFraming.usableRect(CGRect(x: 500, y: 500, width: 10, height: 10), in: window),
                       CGRect(origin: .zero, size: window))
    }

    // MARK: Hole-up heading

    func testHoleUpHeadingIsTheTeeToGreenBearing() throws {
        let tee = CLLocationCoordinate2D(latitude: 33, longitude: -117)
        XCTAssertEqual(try XCTUnwrap(HoleFraming.holeUpHeading(
            tee: tee, green: .init(latitude: 33.0036, longitude: -117))), 0, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(HoleFraming.holeUpHeading(
            tee: tee, green: .init(latitude: 33, longitude: -116.9948))), 90, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(HoleFraming.holeUpHeading(
            tee: tee, green: .init(latitude: 32.9964, longitude: -117))), 180, accuracy: 0.01)
        XCTAssertEqual(try XCTUnwrap(HoleFraming.holeUpHeading(
            tee: tee, green: .init(latitude: 33, longitude: -117.0052))), 270, accuracy: 0.01)
    }

    func testHoleUpHeadingFallsBackToShotsThenNil() throws {
        let first = CLLocationCoordinate2D(latitude: 33, longitude: -117)
        let last = CLLocationCoordinate2D(latitude: 33, longitude: -116.998)
        // No tee: first shot → green.
        XCTAssertEqual(try XCTUnwrap(HoleFraming.holeUpHeading(
            tee: nil, green: .init(latitude: 33.002, longitude: -117), shots: [first])), 0, accuracy: 0.01)
        // No anchors: first → last shot.
        XCTAssertEqual(try XCTUnwrap(HoleFraming.holeUpHeading(
            tee: nil, green: nil, shots: [first, last])), 90, accuracy: 0.01)
        // Too close to orient by, or nothing at all.
        XCTAssertNil(HoleFraming.holeUpHeading(tee: first, green: .init(latitude: 33.00002, longitude: -117)))
        XCTAssertNil(HoleFraming.holeUpHeading(tee: nil, green: nil, shots: [first]))
    }

    func testAWideFreeRectLaysTheHoleLeftToRight() throws {
        // iPhone landscape: the free rect is much wider than tall, so the
        // hole runs tee-left → green-right (canvas iPhone-Landscape).
        XCTAssertEqual(HoleFraming.screenHeading(holeUp: 30, freeRect: CGSize(width: 526, height: 260)), 300)
        // Portrait or near-square rects keep the green straight up.
        XCTAssertEqual(HoleFraming.screenHeading(holeUp: 30, freeRect: CGSize(width: 218, height: 432)), 30)
        XCTAssertEqual(HoleFraming.screenHeading(holeUp: 30, freeRect: CGSize(width: 527, height: 501)), 30)
        XCTAssertEqual(HoleFraming.screenHeading(holeUp: 30, freeRect: .zero), 30)

        let window = CGSize(width: 874, height: 402)
        let rect = CGRect(x: 24, y: 80, width: 500, height: 240)
        let hole = holes[0]
        let up = try XCTUnwrap(HoleFraming.holeUpHeading(tee: hole.tee, green: hole.green))
        let heading = HoleFraming.screenHeading(holeUp: up, freeRect: rect.size)
        let frame = try XCTUnwrap(HoleFraming.fitHole(tee: hole.tee, green: hole.green, shots: [],
                                                      unobstructedRect: rect, in: window, heading: heading))
        let tee = HoleFraming.project(hole.tee, frame: frame, windowSize: window)
        let green = HoleFraming.project(hole.green, frame: frame, windowSize: window)
        XCTAssertLessThan(tee.x, green.x)
        XCTAssertEqual(tee.y, green.y, accuracy: 1)
    }

    func testRotationFromHoleUpIsSignedAndWrapped() {
        XCTAssertEqual(HoleFraming.rotation(from: 350, to: 10), 20, accuracy: 1e-9)
        XCTAssertEqual(HoleFraming.rotation(from: 10, to: 350), -20, accuracy: 1e-9)
        XCTAssertEqual(HoleFraming.rotation(from: 90, to: 90), 0, accuracy: 1e-9)
        XCTAssertEqual(HoleFraming.rotation(from: 0, to: 180), 180, accuracy: 1e-9)
        XCTAssertEqual(HoleFraming.normalizedHeading(-30), 330, accuracy: 1e-9)
        XCTAssertEqual(HoleFraming.normalizedHeading(720), 0, accuracy: 1e-9)
    }
}
