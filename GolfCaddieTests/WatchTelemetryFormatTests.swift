import CoreLocation
@testable import GolfCaddie
import XCTest

/// Pins the telemetry CSV the step 7 analysis script parses.
final class WatchTelemetryFormatTests: XCTestCase {
    private func columns(_ row: String) -> [String] {
        row.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
    }

    func testFixRowMatchesHeader() {
        let fix = CLLocation(
            coordinate: .init(latitude: 33.1234567, longitude: -117.7654321), altitude: 152.349,
            horizontalAccuracy: 4.71, verticalAccuracy: 6, course: 271.5, courseAccuracy: 3,
            speed: 1.234, speedAccuracy: 0.4, timestamp: Date(timeIntervalSince1970: 1_790_000_000.25)
        )
        let row = WatchTelemetryFormat.fixRow(
            fix, receivedAt: Date(timeIntervalSince1970: 1_790_000_000.75),
            reachable: false, hole: 7, localYards: 143, phoneYards: nil
        )
        let header = columns(WatchTelemetryFormat.fixesHeader)
        let values = columns(row)
        XCTAssertEqual(values.count, header.count)
        let byName = Dictionary(uniqueKeysWithValues: zip(header, values))
        XCTAssertEqual(byName["receivedAt"], "1790000000.750")
        XCTAssertEqual(byName["fixTime"], "1790000000.250")
        XCTAssertEqual(byName["lat"], "33.1234567")
        XCTAssertEqual(byName["lng"], "-117.7654321")
        XCTAssertEqual(byName["hAcc"], "4.71")
        XCTAssertEqual(byName["alt"], "152.35")
        XCTAssertEqual(byName["speed"], "1.23")
        XCTAssertEqual(byName["course"], "271.50")
        XCTAssertEqual(byName["reachable"], "0")
        XCTAssertEqual(byName["hole"], "7")
        XCTAssertEqual(byName["localYards"], "143")
        XCTAssertEqual(byName["phoneYards"], "", "missing yardage is blank, not 0")
    }

    func testInvalidFixIsStillLoggedVerbatim() {
        // hAcc < 0 = invalid fix: the yardage ignores it, the log must not.
        let fix = CLLocation(coordinate: .init(latitude: 0, longitude: 0), altitude: 0,
                             horizontalAccuracy: -1, verticalAccuracy: -1, timestamp: Date())
        let values = columns(WatchTelemetryFormat.fixRow(
            fix, receivedAt: Date(), reachable: true, hole: 1, localYards: nil, phoneYards: 150))
        XCTAssertEqual(values.count, columns(WatchTelemetryFormat.fixesHeader).count)
        XCTAssertEqual(values[4], "-1.00")
        XCTAssertEqual(values[10], "1")
    }

    func testBatteryRow() {
        let at = Date(timeIntervalSince1970: 1_790_000_300)
        XCTAssertEqual(WatchTelemetryFormat.batteryRow(at: at, level: 0.874, state: 1), "1790000300.000,87,1")
        XCTAssertEqual(WatchTelemetryFormat.batteryRow(at: at, level: -1, state: 0), "1790000300.000,,0",
                       "unknown level is blank")
        XCTAssertEqual(columns(WatchTelemetryFormat.batteryHeader).count, 3)
    }

    func testSessionIdIsSortableAndPrefixed() {
        let early = WatchTelemetryFormat.sessionId(startedAt: Date(timeIntervalSince1970: 1_790_000_000), suffix: "ab12")
        let late = WatchTelemetryFormat.sessionId(startedAt: Date(timeIntervalSince1970: 1_790_003_600), suffix: "0000")
        XCTAssertTrue(early.hasPrefix(WatchTelemetryFormat.sessionPrefix))
        XCTAssertTrue(early.hasSuffix("-ab12"))
        XCTAssertLessThan(early, late)
    }
}
