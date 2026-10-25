import Foundation
import GRDB

/// What kind of round this is, chosen at Begin (v10). `tracking` logs every
/// shot; `casual` is GPS + a per-hole score. Persisted on the round so a
/// finished round's review knows which it was.
enum RoundMode: String, Codable, CaseIterable {
    case tracking
    case casual
}

struct Round: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable {
    static let databaseTableName = "round"

    var id: UUID
    var startedAt: Date
    var endedAt: Date?
    var courseName: String?
    var notes: String?
    /// Curated course this round was matched to (GPS/name at round start),
    /// or nil. Persisted (v3) so the link survives relaunch/resume and drives
    /// auto-par + distance-to-green without re-matching.
    var curatedCourseId: String?
    /// Bag club ids left home for this round (v7); nil/empty = the whole bag
    /// is in play. See `ClubsInPlay`.
    var clubsLeftOut: [String]?
    /// v10. nil = pre-v10 round (mode lived only in UserDefaults).
    var mode: RoundMode? = nil
    /// v10. The hole the round began on; holes before it with no score are
    /// "not tracked" and the scorecard asks for them (ADD). nil = pre-v10.
    var startingHole: Int? = nil
}
