import Foundation

/// Watch ⇄ phone wire contract for live shot logging. Compiled into BOTH the
/// iOS and watchOS targets (the watch target's `sources` in project.yml lists
/// `GolfCaddie/Shared`). Foundation-only — no UIKit/WatchKit — so it builds on
/// both platforms and in the iOS test target.
///
/// Transport mapping:
///   - watch → phone  : `WatchToPhoneMessage` JSON via `WCSession.transferUserInfo`
///     (queued, FIFO, survives disconnects — swing events / commands must never drop).
///   - phone → watch  : `PhoneStateUpdate` JSON via `WCSession.updateApplicationContext`
///     (latest-wins, cheap — distance/hole/club for the glance UI).

enum ShotContract {
    /// Contract version, bumped on any breaking shape change (mirrors the
    /// glasses `contractVersion` discipline).
    static let version = 1
    /// transferUserInfo dictionary key carrying the JSON-encoded message.
    static let payloadKey = "payload"
}

/// One auto-detected (or watch-manually-added) swing. Timestamped on the watch
/// clock; the phone fuses it to a coordinate via the breadcrumb trail.
struct SwingEvent: Codable, Equatable {
    enum Source: String, Codable {
        case auto // detector fired
        case manualAdd // user tapped "add shot here now" on the watch
    }

    var id: UUID
    /// Unix epoch seconds, watch wall-clock — the fusion key.
    var watchWallClock: Double
    /// ProcessInfo.systemUptime at detection (boot-relative). Free hedge that
    /// matches the spike's ClockAnchor precedent; lets a future field test
    /// estimate watch↔phone drift without a contract change.
    var watchUptime: Double
    /// Currently-selected club on the watch (ClubID.shortName, e.g. "7i"); nil
    /// if the watch has no club selected yet.
    var club: String?
    /// 0…1, detector confidence (impact strength proxy); informational.
    var confidence: Double
    var source: Source
    /// Diagnostics carried through for tuning/triage (not used by fusion).
    var impactPeakG: Double
    var arcGyro: Double
}

/// Discrete user actions from the watch glance UI. Like swing events, these are
/// must-not-lose and ride `transferUserInfo`.
enum WatchCommand: Codable, Equatable {
    /// Manual add (the Strokes-page "+ ADD STROKE" sheet). nil club → the
    /// round's current club.
    case addShot(clubShortName: String?)
    /// Remove a stroke by its shot id (the per-row tap-to-delete); nil → undo
    /// the most recent action.
    case removeStroke(id: String?)
    case puttPlusOne
    case clubChange(shortName: String, epoch: Int)
    /// Confirm the current hole and advance to the next (the watch "Next Hole").
    case advanceHole
    /// Step back one hole without confirming (recovery for an accidental advance).
    case previousHole
}

/// The single `transferUserInfo` payload type — a tagged union so one decode
/// path handles both event and command traffic.
struct WatchToPhoneMessage: Codable, Equatable {
    enum Kind: String, Codable { case swing, command }

    var kind: Kind
    var swing: SwingEvent?
    var command: WatchCommand?

    static func swing(_ event: SwingEvent) -> WatchToPhoneMessage {
        WatchToPhoneMessage(kind: .swing, swing: event, command: nil)
    }

    static func command(_ command: WatchCommand) -> WatchToPhoneMessage {
        WatchToPhoneMessage(kind: .command, swing: nil, command: command)
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> WatchToPhoneMessage {
        try JSONDecoder().decode(WatchToPhoneMessage.self, from: data)
    }
}

/// One club in the bag, with average carry — the watch club selector shows the
/// avg yards and picks the "suggested" club nearest the distance-to-green.
struct WatchClub: Codable, Equatable, Identifiable {
    var short: String // ClubID.shortName, e.g. "7i"
    var name: String // ClubID.longName, e.g. "7 Iron"
    var avgYards: Int
    var id: String { short }
}

/// One logged stroke on the current hole, for the watch Strokes page.
struct WatchStroke: Codable, Equatable, Identifiable {
    var id: String // shot UUID string (for tap-to-delete)
    var clubShort: String?
    var clubName: String
    var lie: String // "Tee" / "Fairway" / "Approach" / "Green" / "Manual"
    var fromYards: Int? // distance to green at the shot, nil if unknown
    var time: String // "2:48"
    var manual: Bool
}

/// One row of the watch Score-page mini scorecard.
struct WatchScoreRow: Codable, Equatable, Identifiable {
    var hole: Int
    var par: Int?
    var strokes: Int
    var id: Int { hole }
}

/// Phone → watch state for the glance UI. Latest-wins via application context.
struct PhoneStateUpdate: Codable, Equatable {
    var isActive: Bool
    var courseName: String?
    var holeNumber: Int
    var par: Int?
    var distanceToGreenYards: Int?
    var currentClubShortName: String?
    /// Monotonic counter resolving the three-way (watch/phone/glasses) club race
    /// without comparing wall-clocks across devices — higher epoch wins.
    var clubEpoch: Int
    /// The bag in order with avg carry, so the watch Crown never hardcodes it.
    var clubs: [WatchClub]
    /// Current hole's strokes (for the Strokes page).
    var strokes: [WatchStroke]
    /// Confirmed holes so far (for the Score-page scorecard).
    var scorecard: [WatchScoreRow]

    var holeShotCount: Int { strokes.count }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> PhoneStateUpdate {
        try JSONDecoder().decode(PhoneStateUpdate.self, from: data)
    }

    static let inactive = PhoneStateUpdate(
        isActive: false, courseName: nil, holeNumber: 0, par: nil,
        distanceToGreenYards: nil, currentClubShortName: nil, clubEpoch: 0,
        clubs: [], strokes: [], scorecard: []
    )
}
