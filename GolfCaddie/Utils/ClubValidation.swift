import Foundation

/// Pure validation for the club editor (B33). The DB's partial unique index
/// is the backstop; these rules run first so the editor can show inline
/// errors and disable Save.
enum ClubValidation {
    static let maxNameLength = 24
    /// Existing shorts are ≤2 chars; 3 fits "56W" on the watch grid and the
    /// glasses fixed-width HUD.
    static let maxShortNameLength = 3

    enum Problem: Equatable {
        case nameEmpty
        case nameTooLong
        case shortNameEmpty
        case shortNameTooLong
        /// Case-insensitive collision with another ACTIVE club — stricter
        /// than the case-sensitive wire needs, so "SW"/"sw" can't coexist.
        case shortNameTaken(by: String)
    }

    /// Validate a candidate club against the active catalog. `others` is the
    /// list of active clubs EXCLUDING the one being edited.
    static func problems(name: String, shortName: String, others: [Club]) -> [Problem] {
        var found: [Problem] = []
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedShort = shortName.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty { found.append(.nameEmpty) }
        if trimmedName.count > maxNameLength { found.append(.nameTooLong) }
        if trimmedShort.isEmpty { found.append(.shortNameEmpty) }
        if trimmedShort.count > maxShortNameLength { found.append(.shortNameTooLong) }
        if let clash = others.first(where: {
            $0.shortName.compare(trimmedShort, options: .caseInsensitive) == .orderedSame
        }) {
            found.append(.shortNameTaken(by: clash.name))
        }
        return found
    }

    static func trimmed(name: String, shortName: String) -> (name: String, shortName: String) {
        (
            name.trimmingCharacters(in: .whitespacesAndNewlines),
            shortName.trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
