#if DEBUG
import CoreLocation
import Foundation

/// `-DebugOpen roundcard`: opens a finished round's card from Home, so the
/// finished-round scorecard can be screenshotted without playing a round.
/// Uses the most recent finished round; on a fresh simulator it first seeds
/// one — a late start on hole 4 (holes 1–3 show ADD), holes 4–18 tracked.
/// Shots are laid from tee to green (the curated course's anchors when the
/// course near the simulated location is already synced, otherwise the
/// Vineyard at Escondido's hole 1) so the review map frames a real hole.
@MainActor
enum DebugScorecardSeed {
    static let pars = [4, 5, 3, 4, 4, 3, 4, 4, 5, 4, 3, 5, 4, 4, 3, 4, 5, 4]
    static let scores = [5, 5, 3, 5, 4, 4, 5, 4, 6, 5, 3, 6, 5, 5, 2, 4, 6, 5]
    static let putts = [2, 2, 2, 2, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2, 1, 2, 2, 2]
    static let startingHole = 4
    private static let clubs = ["driver", "sevenIron", "pitchingWedge", "sandWedge", "nineIron"]
    /// The tour's simulated location and its hole 1 (see verify.sh).
    private static let simulatedLocation = CLLocationCoordinate2D(latitude: 33.0707, longitude: -117.0548)
    private static let fallbackTee = CLLocationCoordinate2D(latitude: 33.0716, longitude: -117.053691)
    private static let fallbackGreen = CLLocationCoordinate2D(latitude: 33.069494, longitude: -117.056016)

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
        let course = CourseCatalog.nearest(in: (try? CourseDataRepository.allCourses()) ?? [],
                                           to: simulatedLocation)
        let round = Round(id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(4 * 3600 + 5 * 60),
                          courseName: course?.name ?? "Debug Links", notes: nil, curatedCourseId: course?.id,
                          clubsLeftOut: nil,
                          mode: .tracking, startingHole: startingHole)
        try RoundRepository.insert(round)
        for number in startingHole...18 {
            let index = number - 1
            let hole = Hole(id: UUID(), roundID: round.id, holeNumber: number, par: pars[index],
                            confirmedAt: start.addingTimeInterval(Double(number) * 600))
            try HoleRepository.insert(hole)
            let full = scores[index] - putts[index]
            let anchors = course?.hole(number)
            let tee = anchors?.teeAnchor?.coordinate ?? fallbackTee
            let green = anchors?.greenAnchor?.coordinate ?? fallbackGreen
            for sequence in 1...scores[index] {
                let isPutt = sequence > full
                let spot = position(of: sequence, fullShots: full, tee: tee, green: green)
                try ShotRepository.insert(Shot(
                    id: UUID(), holeID: hole.id, sequenceNumber: sequence,
                    timestamp: start.addingTimeInterval(Double(number) * 600 + Double(sequence) * 60),
                    latitude: spot.latitude, longitude: spot.longitude, gpsAccuracy: 5, hadGPS: true,
                    club: isPutt ? "putter" : clubs[(sequence - 1) % clubs.count],
                    source: .button, notes: nil, isPutt: isPutt))
            }
        }
        NSLog("[DebugScorecardSeed] seeded finished round \(round.id)")
        return round
    }

    /// Full shots step from the tee toward the green, alternating a little
    /// left and right of the line; putts sit on the green.
    private static func position(of sequence: Int, fullShots: Int,
                                 tee: CLLocationCoordinate2D,
                                 green: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        guard sequence <= fullShots, fullShots > 0 else { return green }
        let t = Double(sequence - 1) / Double(fullShots) + (sequence == 1 ? 0 : 0.08)
        let side = sequence == 1 ? 0 : (sequence.isMultiple(of: 2) ? 0.00008 : -0.00006)
        return CLLocationCoordinate2D(latitude: tee.latitude + (green.latitude - tee.latitude) * t + side,
                                      longitude: tee.longitude + (green.longitude - tee.longitude) * t - side)
    }
}
#endif
