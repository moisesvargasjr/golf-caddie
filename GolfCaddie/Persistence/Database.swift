import Foundation
import GRDB

enum Database {
    /// The active queue all repositories read/write through. Settable so unit
    /// tests can install an in-memory queue via `TestDatabase.install(_:)` and
    /// restore in tearDown. Production code uses `Database.shared` (the
    /// computed alias below) and is unaffected.
    static var queue: DatabaseQueue = {
        do {
            return try makeQueue()
        } catch {
            fatalError("Database initialization failed: \(error)")
        }
    }()

    /// Backward-compatible alias. Production call sites read this and get
    /// whatever `queue` currently points to.
    static var shared: DatabaseQueue { queue }

    private static func makeQueue() throws -> DatabaseQueue {
        let supportDir = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let dbURL = supportDir.appendingPathComponent("golfcaddie.sqlite")
        let queue = try DatabaseQueue(path: dbURL.path)
        try migrator.migrate(queue)
        return queue
    }

    /// Exposed (non-private) so migration tests can construct an in-memory
    /// queue and run the same migrator the app uses.
    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()

        migrator.registerMigration("v1_initial_schema") { db in
            try db.create(table: "round") { t in
                t.column("id", .text).primaryKey()
                t.column("startedAt", .datetime).notNull()
                t.column("endedAt", .datetime)
                t.column("courseName", .text)
                t.column("notes", .text)
            }

            try db.create(table: "hole") { t in
                t.column("id", .text).primaryKey()
                t.column("roundID", .text).notNull()
                    .references("round", onDelete: .cascade)
                t.column("holeNumber", .integer).notNull()
                t.column("par", .integer)
                t.column("confirmedAt", .datetime)
            }
            try db.create(index: "hole_roundID_idx", on: "hole", columns: ["roundID"])

            try db.create(table: "shot") { t in
                t.column("id", .text).primaryKey()
                t.column("holeID", .text).notNull()
                    .references("hole", onDelete: .cascade)
                t.column("sequenceNumber", .integer).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("latitude", .double)
                t.column("longitude", .double)
                t.column("gpsAccuracy", .double)
                t.column("hadGPS", .boolean).notNull()
                t.column("club", .text)
                t.column("source", .text).notNull()
                t.column("notes", .text)
            }
            try db.create(index: "shot_holeID_idx", on: "shot", columns: ["holeID"])

            try db.create(table: "penalty") { t in
                t.column("id", .text).primaryKey()
                t.column("holeID", .text).notNull()
                    .references("hole", onDelete: .cascade)
                t.column("type", .text).notNull()
                t.column("strokeCount", .integer).notNull()
                t.column("timestamp", .datetime).notNull()
                t.column("notes", .text)
            }
            try db.create(index: "penalty_holeID_idx", on: "penalty", columns: ["holeID"])

            try db.create(table: "tracePoint") { t in
                t.column("id", .text).primaryKey()
                t.column("roundID", .text).notNull()
                    .references("round", onDelete: .cascade)
                t.column("timestamp", .datetime).notNull()
                t.column("latitude", .double).notNull()
                t.column("longitude", .double).notNull()
                t.column("accuracy", .double).notNull()
            }
            try db.create(index: "tracePoint_roundID_idx", on: "tracePoint", columns: ["roundID"])

            try db.create(table: "clubConfiguration") { t in
                t.column("id", .integer).primaryKey()
                t.check(sql: "id = 1")
                t.column("bagJSON", .text).notNull()
            }
        }

        // Curated course reference data, synced from the published
        // data/courses.json (golf-caddie-coursedata). The full per-course
        // record is kept as JSON (precedent: clubConfiguration.bagJSON);
        // name/lat/lng are denormalized so proximity + name matching at round
        // start needs no JSON decode. Purely additive — existing rounds and
        // the v1 schema are untouched, so old DBs migrate cleanly.
        migrator.registerMigration("v2_curated_course") { db in
            try db.create(table: "curatedCourse") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("lat", .double).notNull()
                t.column("lng", .double).notNull()
                t.column("payloadJSON", .text).notNull()
                t.column("fetchedAt", .datetime).notNull()
            }

            try db.create(table: "curatedSyncMeta") { t in
                t.column("id", .integer).primaryKey()
                t.check(sql: "id = 1")
                t.column("lastSyncAt", .datetime)
                t.column("lastETag", .text)
                t.column("lastError", .text)
            }
        }

        // Persist the resolved curated course on the round (survives
        // relaunch/resume → drives auto-par + distance-to-green without
        // re-matching), and store locally-captured tee/green anchors. Both
        // additive: ALTER ADD COLUMN is nullable so existing rounds get NULL.
        migrator.registerMigration("v3_curated_link_and_anchors") { db in
            try db.alter(table: "round") { t in
                t.add(column: "curatedCourseId", .text)
            }

            try db.create(table: "localCourseAnchor") { t in
                // id = "<courseId>|<holeNumber>" so capture is an upsert.
                t.column("id", .text).primaryKey()
                t.column("courseId", .text).notNull()
                t.column("holeNumber", .integer).notNull()
                t.column("teeLat", .double)
                t.column("teeLng", .double)
                t.column("greenLat", .double)
                t.column("greenLng", .double)
                t.column("capturedAt", .datetime).notNull()
            }
            try db.create(
                index: "localCourseAnchor_course_idx",
                on: "localCourseAnchor",
                columns: ["courseId"]
            )
        }

        // Honest shot provenance (B3): mark putts explicitly and carry a
        // reconstruction confidence. Additive — `isPutt` defaults to 0 (false)
        // for existing rows; `confidence` is nullable (NULL = not applicable,
        // which is exactly right for every live-logged/manual shot already in
        // the DB). New `ShotSource` cases (watchManual, reconstructed) are
        // string values in the existing `source` column, so no schema change
        // there.
        migrator.registerMigration("v4_shot_putt_confidence") { db in
            try db.alter(table: "shot") { t in
                t.add(column: "isPutt", .boolean).notNull().defaults(to: false)
                t.add(column: "confidence", .double)
            }
        }

        // Data-driven clubs (B33): the fixed ClubID enum becomes a `club`
        // table so clubs are renameable/creatable/deletable. Seed ids equal
        // the old enum rawValues, so existing `shot.club` values and
        // `clubConfiguration.bagJSON` (arrays of those rawValues) keep
        // decoding with NO data migration. Active clubs must be
        // shortName-unique — the short name is the watch/glasses wire key —
        // enforced by a partial index (archived clubs may collide; they're
        // off the wire).
        migrator.registerMigration("v5_custom_clubs") { db in
            try db.create(table: "club") { t in
                t.column("id", .text).primaryKey()
                t.column("name", .text).notNull()
                t.column("shortName", .text).notNull()
                t.column("kind", .text).notNull()
                t.column("defaultYards", .integer).notNull()
                t.column("sortOrder", .integer).notNull()
                t.column("isArchived", .boolean).notNull().defaults(to: false)
            }
            try db.create(
                index: "club_shortName_active_idx",
                on: "club",
                columns: ["shortName"],
                options: .unique,
                condition: Column("isArchived") == false
            )
            for club in Club.seedCatalog {
                try club.insert(db)
            }
        }

        // End-of-hole score reconciliation (watch "Finish Hole"): a tracked
        // stroke the confirmed score says wasn't real is EXCLUDED, not deleted,
        // so it stays restorable. Nullable column → existing rows are active.
        migrator.registerMigration("v6_shot_excluded") { db in
            try db.alter(table: "shot") { t in
                t.add(column: "excludedAt", .datetime)
            }
        }

        // Clubs in play: the bag ids left home for a round, as a JSON array
        // (GRDB's Codable encoding of `Round.clubsLeftOut`). Nullable →
        // existing rounds keep the whole bag.
        migrator.registerMigration("v7_round_clubs_left_out") { db in
            try db.alter(table: "round") { t in
                t.add(column: "clubsLeftOut", .text)
            }
        }

        // Watch GPS first (B35): which device located each shot, and how far
        // apart the watch and phone fixes were when both were usable. Both
        // nullable: pre-v8 shots have unknown provenance, and no-GPS shots have
        // none. locationSource is TEXT: watch / phone / manual / track.
        migrator.registerMigration("v8_shot_location_source") { db in
            try db.alter(table: "shot") { t in
                t.add(column: "locationSource", .text)
                t.add(column: "locationDisagreementMeters", .double)
            }
        }

        // Watch trail (B38): the watch uploads its own GPS trail so a phone left in
        // the cart still yields the walked path. NULL = phone breadcrumb (all
        // legacy rows); 'watch' = from a watch trail batch.
        migrator.registerMigration("v9_trace_point_source") { db in
            try db.alter(table: "tracePoint") { t in
                t.add(column: "source", .text)
            }
            try db.create(index: "tracePoint_roundID_timestamp_idx", on: "tracePoint",
                          columns: ["roundID", "timestamp"])
        }

        // Duo v2 (PR 2): explicit hand scores instead of placeholder strokes,
        // so late-start and casual-entered holes are distinguishable from
        // tracked ones. hole.scoreSource is TEXT 'tracked' | 'hand' (NULL =
        // legacy, read as tracked); handStrokes/handPutts hold the typed-in
        // score. round.mode ('tracking' | 'casual') and round.startingHole
        // record the choices made at Begin, so a finished round knows its mode
        // and which earlier holes need an entry (ADD). All nullable/additive.
        // Penalty strokes need no column: penalty.strokeCount exists since v1.
        //
        // NOTE: docs/WATCH_OWNS_ROUND.md (branch docs/watch-owns-round) also
        // plans a "v10". Whichever ships second renumbers to v11 — GRDB keys
        // migrations by name, so only the name/order must stay unique.
        migrator.registerMigration("v10_hole_score_source") { db in
            try db.alter(table: "hole") { t in
                t.add(column: "scoreSource", .text)
                t.add(column: "handStrokes", .integer)
                t.add(column: "handPutts", .integer)
            }
            try db.alter(table: "round") { t in
                t.add(column: "mode", .text)
                t.add(column: "startingHole", .integer)
            }
        }

        // FIR + GIR (after build 134): the tee shot's finish on a par 4 or 5
        // ('left' | 'fairway' | 'right' | 'short', asked at Finish hole) and
        // a GIR the golfer set by hand in review (NULL = worked out from the
        // shots). Both nullable/additive.
        migrator.registerMigration("v11_hole_fir_gir") { db in
            try db.alter(table: "hole") { t in
                t.add(column: "teeShot", .text)
                t.add(column: "girOverride", .boolean)
            }
        }

        return migrator
    }
}
