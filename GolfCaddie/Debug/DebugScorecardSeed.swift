#if DEBUG
import Foundation

/// `-DebugOpen roundcard`: opens a finished round's card from Home, so the
/// finished-round scorecard can be screenshotted without playing a round.
/// Uses the most recent finished round; on a fresh simulator it first seeds
/// one — a late start on hole 4 (holes 1–3 show ADD), holes 4–18 tracked.
@MainActor
enum DebugScorecardSeed {
    static let pars = [4, 5, 3, 4, 4, 3, 4, 4, 5, 4, 3, 5, 4, 4, 3, 4, 5, 4]
    static let scores = [5, 5, 3, 5, 4, 4, 5, 4, 6, 5, 3, 6, 5, 5, 2, 4, 6, 5]
    static let putts = [2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2]
    static let startingHole = 4
    private static let clubs = ["driver", "sevenIron", "pitchingWedge", "sandWedge", "nineIron"]

    static func finishedRound() -> Round? {
        if let existing = (try? RoundRepository.allRounds())?.first(where: { $0.endedAt != nil }) {
            return existing
        }
        do {
            return try seed()
        } catch {
            NSLog("[DebugScorecardSeed] seed failed: \(error)")
            return nil
        }
    }

    private static func seed() throws -> Round {
        let start = Date().addingTimeInterval(-26 * 3600)
        let round = Round(id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(4 * 3600 + 5 * 60),
                          courseName: "Debug Links", notes: nil, curatedCourseId: nil, clubsLeftOut: nil,
                          mode: .tracking, startingHole: startingHole)
        try RoundRepository.insert(round)
        for number in startingHole...18 {
            let index = number - 1
            let hole = Hole(id: UUID(), roundID: round.id, holeNumber: number, par: pars[index],
                            confirmedAt: start.addingTimeInterval(Double(number) * 600))
            try HoleRepository.insert(hole)
            let full = scores[index] - putts[index]
            for sequence in 1...scores[index] {
                let isPutt = sequence > full
                try ShotRepository.insert(Shot(
                    id: UUID(), holeID: hole.id, sequenceNumber: sequence,
                    timestamp: start.addingTimeInterval(Double(number) * 600 + Double(sequence) * 60),
                    latitude: nil, longitude: nil, gpsAccuracy: nil, hadGPS: false,
                    club: isPutt ? "putter" : clubs[(sequence - 1) % clubs.count],
                    source: .button, notes: nil, isPutt: isPutt))
            }
        }
        NSLog("[DebugScorecardSeed] seeded finished round \(round.id)")
        return round
    }
}
#endif
