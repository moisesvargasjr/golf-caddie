import Foundation

/// Holes currently open in the review sheet or hole detail (B38). The late-trail
/// re-lay skips them so pins never jump under the user's finger. Counted, because
/// the review sheet can be presented over hole detail.
@MainActor
enum HolesUnderEdit {
    private static var counts: [UUID: Int] = [:]

    static func begin(_ id: UUID) { counts[id, default: 0] += 1 }

    static func end(_ id: UUID) {
        guard let n = counts[id] else { return }
        if n <= 1 { counts[id] = nil } else { counts[id] = n - 1 }
    }

    static func contains(_ id: UUID) -> Bool { counts[id] != nil }
}
