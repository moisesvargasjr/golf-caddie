import Foundation

/// In-memory id → Club lookup over the whole `club` table, archived rows
/// included — how the many views that render a shot's club id resolve names
/// without threading dictionaries through every initializer (B33). Mirrors
/// the ClubAverages cache pattern; the bag editor invalidates after any
/// ClubRepository write.
@MainActor
final class ClubCatalog {
    static let shared = ClubCatalog()

    private var byID: [String: Club]?

    private func table() -> [String: Club] {
        if let byID { return byID }
        let all = (try? ClubRepository.all(includeArchived: true)) ?? []
        let built = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
        byID = built
        return built
    }

    func club(id: String?) -> Club? {
        guard let id else { return nil }
        return table()[id]
    }

    func name(id: String?) -> String? {
        club(id: id)?.name
    }

    func shortName(id: String?) -> String? {
        club(id: id)?.shortName
    }

    /// Kind-based putter check — nil/unknown ids are not putters.
    func isPutter(id: String?) -> Bool {
        club(id: id)?.kind == .putter
    }

    /// Call after any ClubRepository save/delete.
    func invalidate() {
        byID = nil
    }
}
