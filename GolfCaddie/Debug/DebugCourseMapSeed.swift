#if DEBUG
import CoreLocation
import Foundation

/// `-DebugOpen course-map`: a finished round on the course map (PR 8), so the
/// course pose can be screenshotted without playing a round. Reuses the
/// `DebugScorecardSeed` card (late start on 4, same pars / scores / putts)
/// but with every shot placed on the map:
///
/// - with a cached curated course that has tee/green anchors, the round is
///   linked to it and each hole's shots run from its tee to its green
///   (holes 1–3, never played, still show tee → green from the course);
/// - otherwise the holes are laid out on a ring near the Debug Links pin and
///   the round has no course — the "rounds without a matched course" case,
///   shots only.
///
/// Seeded once; the round is found again by its notes marker.
@MainActor
enum DebugCourseMapSeed {
    static let marker = "debug-course-map"
    private static let center = CLLocationCoordinate2D(latitude: 33.1, longitude: -117.1)
    private static let ringMeters = 1_100.0
    private static let metersPerDegree = 111_320.0
    private static let clubs = ["driver", "sevenIron", "pitchingWedge", "nineIron"]

    static func round() -> Round? {
        if let existing = (try? RoundRepository.allRounds())?.first(where: { $0.notes == marker }) {
            return existing
        }
        do {
            return try seed()
        } catch {
            NSLog("[DebugCourseMapSeed] seed failed: \(error)")
            return nil
        }
    }

    private static func seed() throws -> Round {
        let course = ((try? CourseDataRepository.allCourses()) ?? []).first { course in
            course.holes.contains { $0.teeAnchor != nil && $0.greenAnchor != nil }
        }
        let start = Date().addingTimeInterval(-50 * 3600)
        let round = Round(id: UUID(), startedAt: start, endedAt: start.addingTimeInterval(4 * 3600),
                          courseName: course?.name ?? "Debug Links", notes: marker,
                          curatedCourseId: course?.id, clubsLeftOut: nil,
                          mode: .tracking, startingHole: DebugScorecardSeed.startingHole)
        try RoundRepository.insert(round)
        for number in DebugScorecardSeed.startingHole...18 {
            let index = number - 1
            let ends = holeEnds(number, course: course)
            let hole = Hole(id: UUID(), roundID: round.id, holeNumber: number,
                            par: course?.hole(number)?.par ?? DebugScorecardSeed.pars[index],
                            confirmedAt: start.addingTimeInterval(Double(number) * 600))
            try HoleRepository.insert(hole)
            try insertShots(for: hole, index: index, from: ends.tee, to: ends.green, start: start)
        }
        NSLog("[DebugCourseMapSeed] seeded course-map round \(round.id) course=\(course?.id ?? "none")")
        return round
    }

    private static func insertShots(for hole: Hole, index: Int, from tee: CLLocationCoordinate2D,
                                    to green: CLLocationCoordinate2D, start: Date) throws {
        let score = DebugScorecardSeed.scores[index]
        let full = score - DebugScorecardSeed.putts[index]
        for sequence in 1...score {
            let isPutt = sequence > full
            // Full shots spread tee → just short of the green, weaving a little;
            // putts a few metres apart on the green.
            let fraction = isPutt ? 1.0 : Double(sequence - 1) / Double(max(full, 1)) * 0.9
            let weave = isPutt ? Double(sequence - full) * 3 : (sequence.isMultiple(of: 2) ? 14.0 : -10.0)
            let at = offset(interpolate(tee, green, fraction), east: weave, north: isPutt ? -4 : 0)
            let time = start.addingTimeInterval(Double(hole.holeNumber) * 600 + Double(sequence) * 60)
            try ShotRepository.insert(Shot(
                id: UUID(), holeID: hole.id, sequenceNumber: sequence, timestamp: time,
                latitude: at.latitude, longitude: at.longitude, gpsAccuracy: 5, hadGPS: true,
                club: isPutt ? "putter" : clubs[(sequence - 1) % clubs.count],
                source: .button, notes: nil, isPutt: isPutt))
        }
    }

    /// Tee and green: the course's anchors, else two points on the ring.
    private static func holeEnds(_ number: Int, course: CuratedCourse?)
        -> (tee: CLLocationCoordinate2D, green: CLLocationCoordinate2D) {
        if let hole = course?.hole(number), let tee = hole.teeAnchor, let green = hole.greenAnchor {
            return (tee.coordinate, green.coordinate)
        }
        let step = 2 * Double.pi / 18
        let a = Double(number - 1) * step
        let b = a + step * 0.8
        return (offset(center, east: ringMeters * sin(a), north: ringMeters * cos(a)),
                offset(center, east: ringMeters * sin(b), north: ringMeters * cos(b)))
    }

    private static func interpolate(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D,
                                    _ t: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                               longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    private static func offset(_ c: CLLocationCoordinate2D, east: Double, north: Double) -> CLLocationCoordinate2D {
        let lat = c.latitude + north / metersPerDegree
        let lng = c.longitude + east / (metersPerDegree * cos(c.latitude * .pi / 180))
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}
#endif
