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
