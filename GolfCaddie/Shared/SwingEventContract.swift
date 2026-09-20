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
    /// transferFile metadata key + value marking a phone → watch course
    /// catalog push (a `CourseDataFile` JSON), so the watch can tell it from
    /// any other file.
    static let fileKindKey = "kind"
    static let courseCatalogKind = "courseCatalog"
    /// transferFile metadata key carrying the pushed catalog's content hash.
    static let catalogHashKey = "hash"
    /// transferUserInfo key for a watch → phone "send me the catalog" request
    /// (watch has never received a push: fresh install / reinstall). Separate
    /// from `payloadKey` — it isn't a round message.
    static let catalogRequestKey = "catalogRequest"
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
    /// Currently-selected club on the watch (club shortName, e.g. "7i"); nil
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
    /// Change a logged stroke's club by shot id (the Strokes-page edit sheet,
    /// B25). nil clubShortName reserved for "clear club" (no UI sends it yet).
    /// NOTE: an OLD phone build fails to decode this case and silently drops
    /// the message (try? in SpikeSessionReceiver) — acceptable because watch +
    /// phone ship in the same build; not a version bump (shape is additive).
    case editStrokeClub(id: String, clubShortName: String?)
    case puttPlusOne
    case clubChange(shortName: String, epoch: Int)
    /// Confirm the current hole and advance to the next (the watch "Next Hole").
    case advanceHole
    /// Step back one hole without confirming (recovery for an accidental advance).
    case previousHole
}

/// A `WatchCommand` plus a stable `id`, so the phone can apply it **at most
/// once** even when the transport delivers it more than once — a retried
/// `transferUserInfo` or a user re-tap after a flaky link. Mirrors
/// `SwingEvent.id`'s idempotency discipline (a logical command keeps its id
/// across resends; a genuinely new tap gets a fresh id and so applies again).
struct IdentifiedCommand: Codable, Equatable {
    var id: UUID
    var command: WatchCommand
}

/// The single `transferUserInfo` payload type — a tagged union so one decode
/// path handles both event and command traffic.
struct WatchToPhoneMessage: Codable, Equatable {
    enum Kind: String, Codable { case swing, command }

    var kind: Kind
    var swing: SwingEvent?
    var command: IdentifiedCommand?

    static func swing(_ event: SwingEvent) -> WatchToPhoneMessage {
        WatchToPhoneMessage(kind: .swing, swing: event, command: nil)
    }

    /// Wrap a command for transport. A fresh `id` is minted per call (one user
    /// action = one id); pass an explicit `id` to reproduce a logical command on
    /// a resend (the same envelope re-sent keeps its id, so the phone dedups it).
    static func command(_ command: WatchCommand, id: UUID = UUID()) -> WatchToPhoneMessage {
        WatchToPhoneMessage(kind: .command, swing: nil,
                            command: IdentifiedCommand(id: id, command: command))
    }

    func encoded() throws -> Data { try JSONEncoder().encode(self) }

    static func decode(_ data: Data) throws -> WatchToPhoneMessage {
        try JSONDecoder().decode(WatchToPhoneMessage.self, from: data)
    }
}

/// One club in the bag, with average carry — the watch club selector shows the
/// avg yards and picks the "suggested" club nearest the distance-to-green.
struct WatchClub: Codable, Equatable, Identifiable {
    var short: String // club shortName, e.g. "7i"
    var name: String // club name, e.g. "7 Iron"
    var avgYards: Int
    /// Kind-based putter flag (B33) so the watch selector can exclude
    /// renamed/custom putters semantically instead of matching the literal
    /// "Pt". Optional = additive: an old-phone payload decodes nil (the watch
    /// falls back to the "Pt" match) and an old watch ignores the extra key —
    /// contract stays v1.
    var isPutter: Bool? = nil
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
    /// The round's linked curated course, so the watch computes its own
    /// yardage against the same course the phone uses instead of guessing by
    /// proximity. Optional = additive (same rule as `WatchClub.isPutter`):
    /// old payloads decode nil and the watch falls back to nearest-course.
    var curatedCourseId: String? = nil

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
