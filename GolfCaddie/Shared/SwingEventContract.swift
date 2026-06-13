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
    case addShotHereNow
    case removeLastShot
    case puttPlusOne
    case clubChange(shortName: String, epoch: Int)
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

/// Phone → watch state for the glance UI. Latest-wins via application context.
struct PhoneStateUpdate: Codable, Equatable {
    var isActive: Bool
    var holeNumber: Int
    var distanceToGreenYards: Int?
    var currentClubShortName: String?
    /// Monotonic counter resolving the three-way (watch/phone/glasses) club race
    /// without comparing wall-clocks across devices — higher epoch wins.
    var clubEpoch: Int
    /// The bag in order (ClubID.shortName) so the watch Crown never hardcodes it.
    var clubs: [String]
    var holeShotCount: Int

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> PhoneStateUpdate {
        try JSONDecoder().decode(PhoneStateUpdate.self, from: data)
    }

    static let inactive = PhoneStateUpdate(
        isActive: false, holeNumber: 0, distanceToGreenYards: nil,
        currentClubShortName: nil, clubEpoch: 0, clubs: [], holeShotCount: 0
    )
}
