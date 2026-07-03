import Foundation
import GRDB

// MARK: - Data-driven club model (B33)

/// Broad club family. Drives putt semantics (`kind == .putter` is what makes
/// the PUTT flows and `Shot.derivedIsPutt` work for renamed/custom putters)
/// and the default-carry prefill for new clubs.
enum ClubKind: String, Codable, CaseIterable, Identifiable {
    case wood, hybrid, iron, wedge, putter

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .wood: return "Wood"
        case .hybrid: return "Hybrid"
        case .iron: return "Iron"
        case .wedge: return "Wedge"
        case .putter: return "Putter"
        }
    }
}

/// One club, as a `club` table row (B33). Replaces the fixed `ClubID` enum:
/// clubs are user-renameable and creatable. Seed rows keep their `id` equal to
/// the old enum rawValue ("gapWedge", …) so historical `shot.club` TEXT values
/// and `clubConfiguration.bagJSON` decode unchanged — zero data migration.
/// `shortName` is the wire vocabulary (watch + glasses payloads and commands);
/// active clubs are shortName-unique (partial index backstops the editor).
struct Club: Codable, Identifiable, Hashable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "club"

    var id: String
    var name: String
    var shortName: String
    var kind: ClubKind
    /// Fallback carry (yards) shown on the watch selector until ClubAverages
    /// has real history for this club. Editable per club.
    var defaultYards: Int
    var sortOrder: Int
    /// Soft delete: a club referenced by historical shots is archived, not
    /// destroyed — hidden from the bag/pickers/wire, but the Logbook keeps
    /// resolving its id to the real name.
    var isArchived: Bool = false
}

extension Club {
    /// The one seed id production logic names directly (PUTT-flow fallbacks).
    static let putterID = "putter"

    /// The 18 rows seeded by `v5_custom_clubs`, lifted verbatim from the old
    /// `ClubID` tables (ids = enum rawValues; carries = the old
    /// WatchStatePublisher.defaultYards switch).
    static let seedCatalog: [Club] = [
        Club(id: "driver", name: "Driver", shortName: "Dr", kind: .wood, defaultYards: 235, sortOrder: 0),
        Club(id: "threeWood", name: "3 Wood", shortName: "3W", kind: .wood, defaultYards: 215, sortOrder: 1),
        Club(id: "fiveWood", name: "5 Wood", shortName: "5W", kind: .wood, defaultYards: 200, sortOrder: 2),
        Club(id: "threeHybrid", name: "3 Hybrid", shortName: "3H", kind: .hybrid, defaultYards: 200, sortOrder: 3),
        Club(id: "fourHybrid", name: "4 Hybrid", shortName: "4H", kind: .hybrid, defaultYards: 190, sortOrder: 4),
        Club(id: "fiveHybrid", name: "5 Hybrid", shortName: "5H", kind: .hybrid, defaultYards: 195, sortOrder: 5),
        Club(id: "threeIron", name: "3 Iron", shortName: "3i", kind: .iron, defaultYards: 200, sortOrder: 6),
        Club(id: "fourIron", name: "4 Iron", shortName: "4i", kind: .iron, defaultYards: 185, sortOrder: 7),
        Club(id: "fiveIron", name: "5 Iron", shortName: "5i", kind: .iron, defaultYards: 175, sortOrder: 8),
        Club(id: "sixIron", name: "6 Iron", shortName: "6i", kind: .iron, defaultYards: 165, sortOrder: 9),
        Club(id: "sevenIron", name: "7 Iron", shortName: "7i", kind: .iron, defaultYards: 150, sortOrder: 10),
        Club(id: "eightIron", name: "8 Iron", shortName: "8i", kind: .iron, defaultYards: 138, sortOrder: 11),
        Club(id: "nineIron", name: "9 Iron", shortName: "9i", kind: .iron, defaultYards: 125, sortOrder: 12),
        Club(id: "pitchingWedge", name: "Pitching Wedge", shortName: "PW", kind: .wedge, defaultYards: 110, sortOrder: 13),
        Club(id: "gapWedge", name: "Gap Wedge", shortName: "GW", kind: .wedge, defaultYards: 95, sortOrder: 14),
        Club(id: "sandWedge", name: "Sand Wedge", shortName: "SW", kind: .wedge, defaultYards: 80, sortOrder: 15),
        Club(id: "lobWedge", name: "Lob Wedge", shortName: "LW", kind: .wedge, defaultYards: 65, sortOrder: 16),
        Club(id: Club.putterID, name: "Putter", shortName: "Pt", kind: .putter, defaultYards: 12, sortOrder: 17),
    ]

    /// Prefill carry for a newly created custom club, by kind.
    static func defaultYards(for kind: ClubKind) -> Int {
        switch kind {
        case .wood: return 210
        case .hybrid: return 195
        case .iron: return 160
        case .wedge: return 90
        case .putter: return 12
        }
    }
}
