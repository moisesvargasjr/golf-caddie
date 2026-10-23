import CoreLocation
import Foundation

/// A plain GPS fix (either device), decoupled from CLLocation so the policy
/// below is a pure function of values. Compiled into BOTH targets.
struct GeoFix: Equatable {
    var latitude: Double
    var longitude: Double
    /// Meters, CLLocation semantics (<= 0 = invalid).
    var horizontalAccuracy: Double
    /// Unix epoch seconds.
    var timestamp: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    init(latitude: Double, longitude: Double, horizontalAccuracy: Double, timestamp: Double) {
        self.latitude = latitude
        self.longitude = longitude
        self.horizontalAccuracy = horizontalAccuracy
        self.timestamp = timestamp
    }

    init(_ fix: WatchFix) {
        self.init(latitude: fix.latitude, longitude: fix.longitude,
                  horizontalAccuracy: fix.horizontalAccuracy, timestamp: fix.timestamp)
    }

    init(_ location: CLLocation) {
        self.init(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude,
                  horizontalAccuracy: location.horizontalAccuracy,
                  timestamp: location.timestamp.timeIntervalSince1970)
    }
}

/// Which device a location came from.
enum LocationSource: String, Equatable {
    case watch
    case phone
    case none
}

struct LocationChoice: Equatable {
    var fix: GeoFix?
    var source: LocationSource
    /// Meters between the watch and phone fixes, set whenever BOTH were usable
    /// (so a field round can show how far apart the two devices really were).
    var disagreementMeters: Double?
}

/// B35 "watch GPS first": the watch is on the golfer, the phone is often in the
/// cart or the bag. A usable watch fix therefore always wins — even when the
/// phone reports a better accuracy number, because that number says nothing
/// about where the golfer is standing.
enum LocationPreference {
    /// A watch fix older than this (vs. the moment it's judged for) is stale.
    /// The watch GPS runs at 1 Hz, so a live fix is always within a second or two.
    static let watchFixMaxAge: TimeInterval = 5
    /// A watch fix coarser than this is no better than the phone's guess.
    static let watchFixMaxAccuracy: Double = 15
    /// Looser age gate for phone-originated reads of the STREAMED fix (phone
    /// MARK, glasses, yardage): there is no swing timestamp to match, and one
    /// dropped `sendMessage` on a 2 s stream must not flip "watch first" to the
    /// phone. Swing/tap fixes are timestamp-matched and keep `watchFixMaxAge`.
    static let streamedWatchFixMaxAge: TimeInterval = 10

    /// The watch's fix if it's trustworthy for something that happened at `time`.
    static func usableWatchFix(_ fix: WatchFix?, at time: Date,
                               maxAge: TimeInterval = watchFixMaxAge) -> GeoFix? {
        guard let fix, fix.horizontalAccuracy > 0, fix.horizontalAccuracy <= watchFixMaxAccuracy,
              abs(fix.timestamp - time.timeIntervalSince1970) <= maxAge else { return nil }
        return GeoFix(fix)
    }

    /// Usable watch fix → watch. Else a phone fix with valid accuracy → phone.
    /// Else none. The caller chooses which phone fix is relevant (live fix or
    /// the breadcrumb nearest a past moment); the policy only rejects invalid
    /// accuracy.
    static func choose(watch: WatchFix?, phone: GeoFix?, at time: Date,
                       watchMaxAge: TimeInterval = watchFixMaxAge) -> LocationChoice {
        let usablePhone = phone.flatMap { $0.horizontalAccuracy > 0 ? $0 : nil }
        guard let usableWatch = usableWatchFix(watch, at: time, maxAge: watchMaxAge) else {
            return LocationChoice(fix: usablePhone, source: usablePhone == nil ? .none : .phone,
                                  disagreementMeters: nil)
        }
        let disagreement = usablePhone.map {
            Distance.meters(from: usableWatch.coordinate, to: $0.coordinate)
        }
        return LocationChoice(fix: usableWatch, source: .watch, disagreementMeters: disagreement)
    }
}

/// Watch → phone position stream (B35). The phone can only prefer the watch's
/// position for phone-originated actions if it hears it, so while a session
/// runs the watch sends its latest fix about every `fixStreamInterval` s via
/// `WCSession.sendMessage`. Live-only by design: never queued with
/// `transferUserInfo` (a delayed fix is worse than none), and dropped on failure.
enum WatchFixStream {
    /// The encoded `.fix` message, or nil when there is nothing worth sending:
    /// phone unreachable, no fix yet, or a fix too old / invalid to be useful.
    static func payload(latest: WatchFix?, reachable: Bool, now: Date) -> Data? {
        // Tight send-time gate: GPS is 1 Hz, so anything older than this means
        // the receiver stalled; don't ship a fix that is nearly stale on arrival.
        guard reachable, let latest,
              LocationPreference.usableWatchFix(latest, at: now, maxAge: ShotContract.fixStreamMaxSendAge) != nil
        else { return nil }
        return try? WatchToPhoneMessage.fix(latest).encoded()
    }
}
