import Foundation

/// Reads what Home shows from the repositories. Thin: the selection and
/// totals live in the pure `HomeViewModel` / `HomeRoundEntry`.
enum HomeData {
    struct Snapshot: Equatable {
        let roundCount: Int
        let lastEntry: HomeRoundEntry?
        let earlierRounds: [HomeRoundEntry]

        static let empty = Snapshot(roundCount: 0, lastEntry: nil, earlierRounds: [])
    }

    static func load() throws -> Snapshot {
        let rounds = try RoundRepository.allRounds()
        let last = HomeViewModel.lastEntry(from: rounds)
        let earlier = HomeViewModel.earlierRounds(from: rounds, excluding: last,
                                                  limit: HomeViewModel.earlierRoundsLimit)
        return Snapshot(roundCount: rounds.count,
                        lastEntry: try last.map(entry(for:)),
                        earlierRounds: try earlier.map(entry(for:)))
    }

    /// Curated course names by id, for the Course row. Soft-fails to empty.
    static func courseNames() -> (courses: [CuratedCourse], names: [String: String]) {
        let courses = (try? CourseDataRepository.allCourses()) ?? []
        let names = Dictionary(courses.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        return (courses, names)
    }

    /// The round as Home shows it, scored by the same rules as the card:
    /// `HoleScoring` (a hand score wins over logged shots), a hand-scored
    /// hole counts as finished, and a hole without a par takes its course's.
    static func entry(for round: Round) throws -> HomeRoundEntry {
        let course = round.curatedCourseId.flatMap { try? CourseDataRepository.course(byId: $0) }
        let holes = try HoleRepository.holesForRound(round.id).map { hole in
            HomeHoleInput.make(hole: hole,
                               shots: (try? ShotRepository.shotsForHole(hole.id)) ?? [],
                               penaltyStrokes: ((try? PenaltyRepository.penaltiesForHole(hole.id)) ?? [])
                                   .totalStrokes,
                               coursePar: course?.holes.first(where: { $0.number == hole.holeNumber })?.par)
        }
        return HomeRoundEntry.make(round: round, holes: holes)
    }
}

/// The player (Profile, after build 134): a name for the card's PLAYER line
/// and Home's profile button, plus an optional home course and handicap
/// index. Device-local settings, like the theme and units.
enum PlayerProfile {
    static let nameKey = "profile.name"
    static let homeCourseKey = "profile.homeCourseId"
    static let handicapKey = "profile.handicapIndex"

    static var name: String { trimmed(UserDefaults.standard.string(forKey: nameKey) ?? "") }

    static func trimmed(_ name: String) -> String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// "MOISES ›", or "YOUR NAME ›" before one is set.
    static func buttonTitle(name: String) -> String {
        let clean = trimmed(name)
        return (clean.isEmpty ? "YOUR NAME" : clean.uppercased()) + " ›"
    }

    /// A handicap index as typed ("12.4", "+1.2"), or nil when it isn't one.
    /// WHS indexes run from +10.0 down to 54.0.
    static func handicapIndex(_ text: String) -> Double? {
        let clean = trimmed(text).replacingOccurrences(of: ",", with: ".")
        guard !clean.isEmpty else { return nil }
        let plus = clean.hasPrefix("+")
        guard let value = Double(plus ? String(clean.dropFirst()) : clean) else { return nil }
        let index = plus ? -value : value
        return (-10...54).contains(index) ? index : nil
    }
}
