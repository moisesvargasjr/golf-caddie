import Foundation
import GRDB

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
}
