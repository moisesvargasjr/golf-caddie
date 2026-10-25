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
    /// Seconds between watch → phone fix messages while a session runs (B35).
    static let fixStreamInterval: TimeInterval = 2
    /// A fix older than this at send time is not streamed (see `WatchFixStream`).
    static let fixStreamMaxSendAge: TimeInterval = 2
    /// transferUserInfo key for a watch trail batch (B38). Separate from
    /// `payloadKey` so the watch's "SYNCING N" chip, which counts round traffic,
    /// is not inflated by background trail uploads.
    static let trailKey = "trail"
    /// Seconds between queued trail flushes while a session runs (also flushed on
    /// hole change / Finish Hole and at stop). 60 s: fewer radio wakes; hole-change
    /// and stop flushes carry the timing-critical data.
    static let trailFlushInterval: TimeInterval = 60
}

/// The watch's own GPS fix at a swing / tap. The phone prefers it over its own
/// breadcrumb when fresh and accurate — the phone is often left in the cart, so
/// its trail is where the CART was, not where the ball was hit (Native Oaks,
/// 2026-10-17). Optional everywhere it rides = additive, contract stays v1.
struct WatchFix: Codable, Equatable {
    var latitude: Double
    var longitude: Double
    /// Meters, CLLocation semantics (≤ 0 = invalid).
    var horizontalAccuracy: Double
    /// Unix epoch seconds, watch wall-clock, when the fix was taken.
    var timestamp: Double
}

/// One auto-detected (or watch-manually-added) swing. Timestamped on the watch
/// clock; the phone locates it with the watch's own fix when that's usable,
/// else fuses it to its breadcrumb trail.
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
    /// Watch GPS at detection. nil = old watch build or no fix yet.
    var fix: WatchFix? = nil
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
    /// Add a 1-stroke penalty to the current hole (the watch Actions page).
    /// `kind` is a `WatchPenaltyKind` raw value. Like `editStrokeClub`, an OLD
    /// phone build can't decode this case and drops the message — acceptable
    /// because watch + phone ship in the same build.
    case addPenalty(kind: String)
    /// The one end-of-hole check (watch "Finish Hole"): the putt count the
    /// golfer gave and the score they confirmed. The phone reconciles the
    /// tracked strokes to that score, confirms the hole and advances.
    case finishHole(putts: Int, score: Int)
}

/// The penalty kinds the watch offers — raw values LOCKSTEP with the phone's
/// `PenaltyType` (pinned by a test), kept here so Shared stays free of the
/// phone's GRDB models.
enum WatchPenaltyKind: String, CaseIterable, Identifiable {
    case obOrLost, water, unplayable, wrongBall, other

    var id: String { rawValue }

    var label: String {
        switch self {
        case .obOrLost: return "OB / Lost"
        case .water: return "Water"
        case .unplayable: return "Unplay."
        case .wrongBall: return "Wrong ball"
        case .other: return "Other"
        }
    }

    var symbol: String {
        switch self {
        case .obOrLost: return "xmark.circle"
        case .water: return "drop"
        case .unplayable: return "tree"
        case .wrongBall: return "questionmark.circle"
        case .other: return "plus.circle"
        }
    }
}

/// A `WatchCommand` plus a stable `id`, so the phone can apply it **at most
/// once** even when the transport delivers it more than once — a retried
/// `transferUserInfo` or a user re-tap after a flaky link. Mirrors
/// `SwingEvent.id`'s idempotency discipline (a logical command keeps its id
/// across resends; a genuinely new tap gets a fresh id and so applies again).
struct IdentifiedCommand: Codable, Equatable {
    var id: UUID
    var command: WatchCommand
    /// Watch wall-clock (unix s) when the golfer tapped. Commands are queued, so
    /// they can arrive long after the fact (phone out of range for holes at a
    /// time): the phone uses this to timestamp + locate a late MARK/putt at the
    /// moment it happened, not at delivery. Optional = additive (an old watch
    /// sends none → the phone treats it as live, as before).
    var sentAt: Double? = nil
    /// Watch GPS at the tap (MARK / putt). nil = old watch build or no fix.
    var fix: WatchFix? = nil
}

/// The single watch → phone payload type — a tagged union so one decode path
/// handles event, command and fix traffic. Swings and commands ride the queued
/// `transferUserInfo`; `.fix` rides `sendMessage` only (see `fix(_:)`).
struct WatchToPhoneMessage: Codable, Equatable {
    enum Kind: String, Codable { case swing, command, fix, trail }

    var kind: Kind
    var swing: SwingEvent?
    var command: IdentifiedCommand?
    /// The watch's latest GPS (kind == .fix). Optional = additive: every
    /// pre-B35 payload decodes with nil, so the contract stays v1. An OLD phone
    /// fails to decode the new `fix` kind and drops it, which is harmless.
    var watchFix: WatchFix? = nil
    /// A batch of the watch's GPS trail (kind == .trail), queued via
    /// `transferUserInfo`. Optional = additive; contract stays v1.
    var trail: WatchTrailBatch? = nil

    static func swing(_ event: SwingEvent) -> WatchToPhoneMessage {
        WatchToPhoneMessage(kind: .swing, swing: event, command: nil)
    }

    /// Wrap a command for transport. A fresh `id` is minted per call (one user
    /// action = one id); pass an explicit `id` to reproduce a logical command on
    /// a resend (the same envelope re-sent keeps its id, so the phone dedups it).
    static func command(
        _ command: WatchCommand, id: UUID = UUID(), sentAt: Date? = Date(), fix: WatchFix? = nil
    ) -> WatchToPhoneMessage {
        WatchToPhoneMessage(kind: .command, swing: nil,
                            command: IdentifiedCommand(id: id, command: command,
                                                       sentAt: sentAt?.timeIntervalSince1970, fix: fix))
    }

    /// The watch's current position, streamed to the phone (B35) so phone-
    /// originated actions (MARK on the phone, glasses, yardage) can use where
    /// the golfer is. Deliberately NEVER sent via `transferUserInfo`: a queued
    /// fix is stale by the time it lands and is worse than none.
    static func fix(_ fix: WatchFix) -> WatchToPhoneMessage {
        WatchToPhoneMessage(kind: .fix, swing: nil, command: nil, watchFix: fix)
    }

    /// A trail batch for queued delivery (B38). Unlike `.fix`, trail data is
    /// historical and worth delivering late: the phone files it by timestamp.
    static func trail(_ batch: WatchTrailBatch) -> WatchToPhoneMessage {
        WatchToPhoneMessage(kind: .trail, swing: nil, command: nil, trail: batch)
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
    /// Penalty strokes on the current hole, so the wrist count matches the
    /// scorecard. Optional = additive (old phone → nil → treated as 0).
    var holePenaltyStrokes: Int? = nil
    /// Full (non-putt) strokes tracked on the current hole — pre-fills the
    /// watch's Finish Hole score. Optional = additive.
    var holeFullShots: Int? = nil

    var holeShotCount: Int { strokes.count }
    /// Shots + penalty strokes — what the hole will score.
    var holeStrokeTotal: Int { strokes.count + (holePenaltyStrokes ?? 0) }

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

/// A batch of the watch's thinned GPS trail (B38). `batchId` makes redelivery
/// idempotent. Wire format is compact on purpose (watch battery + BLE traffic):
/// each fix is a 4-number row `[lat, lon, hAcc, unixSeconds]` rounded to useful
/// precision (6 decimals is about 0.1 m, hAcc to 0.1 m, time to 1 ms), about 55
/// bytes a fix instead of ~110 as a keyed object.
struct WatchTrailBatch: Codable, Equatable {
    var batchId: UUID
    var fixes: [WatchFix]

    private enum CodingKeys: String, CodingKey { case batchId = "b", fixes = "f" }

    init(batchId: UUID, fixes: [WatchFix]) {
        self.batchId = batchId
        self.fixes = fixes
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        batchId = try c.decode(UUID.self, forKey: .batchId)
        let rows = try c.decode([[Double]].self, forKey: .fixes)
        fixes = try rows.map { row in
            guard row.count == 4 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .fixes, in: c, debugDescription: "trail fix row must have 4 numbers")
            }
            return WatchFix(latitude: row[0], longitude: row[1], horizontalAccuracy: row[2], timestamp: row[3])
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(batchId, forKey: .batchId)
        try c.encode(fixes.map { [Self.round($0.latitude, 6), Self.round($0.longitude, 6),
                                  Self.round($0.horizontalAccuracy, 1), Self.round($0.timestamp, 3)] },
                     forKey: .fixes)
    }

    private static func round(_ value: Double, _ places: Int) -> Double {
        let scale = pow(10.0, Double(places))
        return (value * scale).rounded() / scale
    }
}
