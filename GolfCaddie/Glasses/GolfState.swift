import Foundation

// Wire transport for the glasses integration. Plain Encodable, no domain or
// GRDB types: dates/UUIDs are pre-converted to String in GlassesStateMapper so
// a default JSONEncoder yields the contract's "no JSON null" rule for free
// (synthesized Codable omits nil optionals). Mirrors
// golf-caddie-glasses/docs/IOS_INTEGRATION_CONTRACT.md and that repo's
// src/shared/types.ts — keep in lockstep.

struct GolfState: Encodable {
    var contractVersion: Int
    var active: Bool
    var round: RoundDTO?
    var hole: HoleDTO?
    var currentClub: String?
    var clubs: [String]?
    var lastShot: LastShotDTO?
    var scoring: ScoringDTO?
    var gps: GPSDTO?
    var battery: Int?
    var holes: [HoleSummaryDTO]?
    /// True when the user has flipped on "Glasses input" (Settings → Glasses) —
    /// the watch-died fallback. The glasses stay output-only when false/absent
    /// and re-enable tap-to-log/club/undo when true. Omitted when idle.
    var glassesInputEnabled: Bool?

    static let idle = GolfState(contractVersion: 1, active: false)

    init(
        contractVersion: Int,
        active: Bool,
        round: RoundDTO? = nil,
        hole: HoleDTO? = nil,
        currentClub: String? = nil,
        clubs: [String]? = nil,
        lastShot: LastShotDTO? = nil,
        scoring: ScoringDTO? = nil,
        gps: GPSDTO? = nil,
        battery: Int? = nil,
        holes: [HoleSummaryDTO]? = nil,
        glassesInputEnabled: Bool? = nil
    ) {
        self.contractVersion = contractVersion
        self.active = active
        self.round = round
        self.hole = hole
        self.currentClub = currentClub
        self.clubs = clubs
        self.lastShot = lastShot
        self.scoring = scoring
        self.gps = gps
        self.battery = battery
        self.holes = holes
        self.glassesInputEnabled = glassesInputEnabled
    }
}

struct RoundDTO: Encodable {
    var id: String
    var startedAt: String
    var courseName: String?
}

struct HoleDTO: Encodable {
    var number: Int
    var par: Int?
    var shotCount: Int
    var penalties: Int
    var score: Int
    /// Live yards from the current GPS position to this hole's green anchor.
    /// Omitted when the round didn't match a curated course, no green anchor
    /// is captured yet, or there's no fix — graceful degradation, contract's
    /// "no JSON null" rule (default nil keeps the memberwise init source-compatible).
    var distanceToGreenYards: Int? = nil
}

struct LastShotDTO: Encodable {
    /// The most recently swung club — "what you last hit". Nil only if the hole
    /// has no shots. Deliberately carries NO distance: a club's carry isn't
    /// knowable until the NEXT shot is logged (it's the GPS gap to the following
    /// position), so any distance shown here would describe the club BEFORE this
    /// one — which read as confusing on the HUD (field-test follow-up 2026-06-19).
    /// `currentClub` is the upcoming selection; this is the last actual swing.
    var club: String?
    var sequenceNumber: Int
}

struct ScoringDTO: Encodable {
    var totalStrokes: Int
    var totalPar: Int?
    var toPar: Int?
    var holesCompleted: Int
}

struct GPSDTO: Encodable {
    var accuracyMeters: Double?
    var stale: Bool
}

struct HoleSummaryDTO: Encodable {
    var number: Int
    var par: Int?
    var score: Int
    var confirmedAt: String?
    var shots: [ShotSummaryDTO]
}

struct ShotSummaryDTO: Encodable {
    var sequenceNumber: Int
    var club: String?
    var distanceYards: Int?
}
