import Foundation
import GRDB

/// Breadcrumb trail persistence. The `tracePoint` table has existed since the
/// v1 schema but was unused until live shot logging — these are the continuous
/// GPS fixes the fusion engine matches a watch SwingEvent's timestamp against
/// to assign the shot a coordinate. Rows cascade-delete with their round
/// (FK ON DELETE CASCADE, see RoundRepository.delete).
enum TracePointRepository {
    static func insert(_ point: TracePoint) throws {
        try Database.shared.write { db in try point.insert(db) }
    }

    static func pointsForRound(_ roundID: UUID) throws -> [TracePoint] {
        try Database.shared.read { db in
            try TracePoint.filter(Column("roundID") == roundID)
                .order(Column("timestamp"))
                .fetchAll(db)
        }
    }

    static func count(forRound roundID: UUID) throws -> Int {
        try Database.shared.read { db in
            try TracePoint.filter(Column("roundID") == roundID).fetchCount(db)
        }
    }

    /// The fusion primitive: the breadcrumb closest in time to a swing event.
    /// A round is bounded (hours), and the golfer is stationary at address, so
    /// the nearest fix is a faithful stand-in for "where the shot was struck"
    /// even with seconds of watch↔phone clock drift. Returns nil if the round
    /// has no breadcrumbs yet (caller falls back to latestLocation).
    static func nearest(toTimestamp target: Date, inRound roundID: UUID) throws -> TracePoint? {
        // GRDB encodes a Date argument to the same lexicographically-ordered
        // string it stores, so a before/after bracket compares correctly
        // without depending on SQLite date parsing. Pick the nearer of the two.
        try Database.shared.read { db in
            let base = TracePoint.filter(Column("roundID") == roundID)
            let before = try base.filter(Column("timestamp") <= target)
                .order(Column("timestamp").desc).fetchOne(db)
            let after = try base.filter(Column("timestamp") >= target)
                .order(Column("timestamp").asc).fetchOne(db)
            switch (before, after) {
            case let (b?, a?):
                let db_ = abs(b.timestamp.timeIntervalSince(target))
                let da_ = abs(a.timestamp.timeIntervalSince(target))
                return db_ <= da_ ? b : a
            case let (b?, nil): return b
            case let (nil, a?): return a
            case (nil, nil): return nil
            }
        }
    }

    static func deleteForRound(_ roundID: UUID) throws {
        try Database.shared.write { db in
            _ = try TracePoint.filter(Column("roundID") == roundID).deleteAll(db)
        }
    }
}
