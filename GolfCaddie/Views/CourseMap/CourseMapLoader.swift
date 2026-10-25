import CoreLocation
import Foundation

/// Reads a finished round's course map from the database: its holes, shots
/// and penalties, plus the tee/green anchors of its matched course (a local
/// capture wins over the curated anchor, as everywhere else). Synchronous
/// GRDB reads — call it from `onAppear` or a button action, never a `.task`.
@MainActor
enum CourseMapLoader {
    static func load(round: Round, courseName: String?) -> CourseMapContent {
        let rows = (try? HoleRepository.holesForRound(round.id)) ?? []
        var shots: [UUID: [Shot]] = [:]
        var penalties: [UUID: Int] = [:]
        for hole in rows {
            shots[hole.id] = (try? ShotRepository.shotsForHole(hole.id)) ?? []
            penalties[hole.id] = ((try? PenaltyRepository.penaltiesForHole(hole.id)) ?? []).totalStrokes
        }
        let anchors = anchorTable(courseId: round.curatedCourseId)
        let holes = CourseOutlineBuilder.holes(from: rows, shots: shots, penaltyStrokes: penalties,
                                               coursePar: { anchors.pars[$0] })
        let outlines = CourseOutlineBuilder.outlines(holes,
                                                     anchors: { anchors.byHole[$0] ?? HolePathAnchors.none },
                                                     curatedPar: { anchors.pars[$0] })
        let hasAnchors = outlines.contains { $0.tee != nil || $0.green != nil }
        let roundText = CourseMapText.roundText(dateText: ReviewText.dateText(round.startedAt), holes: holes)
        return CourseMapContent(outlines: outlines,
                                title: CourseMapText.title(courseName: courseName),
                                caption: CourseMapText.caption(roundText: roundText, hasCourseAnchors: hasAnchors),
                                hasCourseAnchors: hasAnchors)
    }

    /// Every hole's anchors and par for the round's course, read once. Empty
    /// for a round without a matched course: the map then draws only shots.
    private static func anchorTable(courseId: String?)
        -> (byHole: [Int: HolePathAnchors], pars: [Int: Int]) {
        guard let courseId else { return ([:], [:]) }
        let curated = try? CourseDataRepository.course(byId: courseId)
        let local = (try? LocalAnchorRepository.anchorsForCourse(courseId)) ?? []
        var byHole: [Int: HolePathAnchors] = [:]
        var pars: [Int: Int] = [:]
        for number in HoleScoring.holeRange {
            let curatedHole = curated?.hole(number)
            let localHole = local.first { $0.holeNumber == number }
            let tee = localHole?.tee ?? curatedHole?.teeAnchor
            let green = localHole?.green ?? curatedHole?.greenAnchor
            byHole[number] = HolePathAnchors(tee: tee?.coordinate, green: green?.coordinate)
            if let par = curatedHole?.par { pars[number] = par }
        }
        return (byHole, pars)
    }
}
