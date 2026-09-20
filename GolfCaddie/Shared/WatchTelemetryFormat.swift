import CoreLocation
import Foundation

/// File format of the watch GPS/battery telemetry (spike step 6,
/// docs/WATCH_STANDALONE_SPIKE.md). Plain CSV so the analysis script and a
/// spreadsheet both read it. Shared so the phone tests pin the format the
/// step 7 script depends on.
///
/// A session is a folder `telemetry-<yyyyMMdd-HHmmss>-<4hex>` holding:
///   - `fixes.csv`   — EVERY fix the watch received, unfiltered (the yardage
///                     and route filters don't apply here — rejected fixes are
///                     part of what we're measuring);
///   - `battery.csv` — level at start, every 5 min, and at stop;
///   - `session.json`— `WatchTelemetrySession`, written at stop.
enum WatchTelemetryFormat {
    static let sessionPrefix = "telemetry-"
    static let fixesFile = "fixes.csv"
    static let batteryFile = "battery.csv"
    static let sessionFile = "session.json"

    /// transferFile metadata (`ShotContract.fileKindKey` value + companions).
    static let fileKind = "watchTelemetry"
    static let sessionIdKey = "sessionId"
    static let filenameKey = "filename"

    static let batteryInterval: TimeInterval = 300

    /// - receivedAt: watch wall-clock when the fix was delivered (unix s)
    /// - fixTime: the fix's own timestamp (unix s) — join key vs phone breadcrumbs
    /// - reachable: 1 if the phone was WC-reachable at that moment — segments the
    ///   paired vs Bluetooth-off halves for the GPS-routing check
    /// - hole/localYards/phoneYards: what the yardage screen had, for the
    ///   watch-vs-phone yardage comparison (blank = none)
    static let fixesHeader =
        "receivedAt,fixTime,lat,lng,hAcc,vAcc,alt,speed,speedAcc,course,reachable,hole,localYards,phoneYards"

    static func fixRow(
        _ fix: CLLocation, receivedAt: Date, reachable: Bool, hole: Int, localYards: Int?, phoneYards: Int?
    ) -> String {
        [
            t(receivedAt), t(fix.timestamp),
            String(format: "%.7f", fix.coordinate.latitude), String(format: "%.7f", fix.coordinate.longitude),
            m(fix.horizontalAccuracy), m(fix.verticalAccuracy), m(fix.altitude),
            m(fix.speed), m(fix.speedAccuracy), m(fix.course),
            reachable ? "1" : "0", String(hole),
            localYards.map(String.init) ?? "", phoneYards.map(String.init) ?? "",
        ].joined(separator: ",")
    }

    /// - level: 0…100, blank if unknown; state: WKInterfaceDeviceBatteryState raw value
    static let batteryHeader = "at,level,state"

    static func batteryRow(at: Date, level: Float, state: Int) -> String {
        "\(t(at)),\(level < 0 ? "" : String(Int((level * 100).rounded()))),\(state)"
    }

    static func sessionId(startedAt: Date, suffix: String) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return "\(sessionPrefix)\(f.string(from: startedAt))-\(suffix)"
    }

    private static func t(_ date: Date) -> String { String(format: "%.3f", date.timeIntervalSince1970) }
    private static func m(_ value: Double) -> String { String(format: "%.2f", value) }
}

struct WatchTelemetrySession: Codable, Equatable {
    var sessionId: String
    var startedAt: Double
    var endedAt: Double?
    var deviceModel: String
    var systemVersion: String
    var appBuild: String
    var fixCount: Int
    var batteryStart: Int?
    var batteryEnd: Int?
}
