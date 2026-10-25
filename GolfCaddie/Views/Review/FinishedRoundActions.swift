import Foundation

/// The writes behind a finished round's ··· (moved from the old
/// `RoundReviewView`): link / unlink its curated course, delete it, and what
/// Share round hands the share sheet.
@MainActor
enum FinishedRoundActions {
    /// Links (or, with nil, unlinks) the round's curated course. A link also
    /// adopts the course's name as the round's label — the same as the
    /// in-round link — so a wrong auto-detected name gets replaced, and the
    /// pars the old course filled in follow the new one (`CourseRelinkPars`,
    /// the live round's rule). Returns the updated round; the passed one is
    /// not changed.
    static func settingCourse(_ id: String?, on round: Round, courses: [CuratedCourse]) throws -> Round {
        let parChanges = try CourseRelinkPars.changes(roundID: round.id, from: round.curatedCourseId, to: id)
        try RoundRepository.setCuratedCourseId(roundID: round.id, id: id)
        for change in parChanges {
            try HoleRepository.setPar(holeID: change.holeID, par: change.par)
        }
        var updated = round
        updated.curatedCourseId = id
        if let id, let name = courses.first(where: { $0.id == id })?.name {
            updated.courseName = name
            try RoundRepository.update(updated)
        }
        return updated
    }

    /// Permanently removes the round and every hole, shot and penalty in it.
    static func delete(_ round: Round) throws {
        try RoundRepository.delete(round)
    }

    /// Share round: the card as an image for a post or a message, plus a
    /// one-line summary. Never the logbook's database — that backup lives in
    /// Settings → Export Rounds and holds every round's GPS.
    static func shareItems(for round: Round) throws -> [Any] {
        let text = ReviewText.shareText(courseName: round.courseName, roundText: roundText(for: round))
        guard let summary = RoundShareSummary.make(round: round),
              let image = RoundShareCard.renderPNG(summary) else {
            throw ShareError.couldNotDrawCard
        }
        return [image, text]
    }

    enum ShareError: LocalizedError {
        case couldNotDrawCard
        var errorDescription: String? { "The card image couldn't be drawn." }
    }

    /// "OCT 23 · 79 (+7)" from the round's card.
    static func roundText(for round: Round) -> String {
        let date = ReviewText.dateText(round.startedAt)
        guard let card = try? ScorecardLoader.load(round: round, curatedCourseId: round.curatedCourseId) else {
            return date
        }
        let holes: [(par: Int?, score: Int?)] = card.model.columns.map { column in
            (par: column.par, score: column.needsEntry ? nil : column.score)
        }
        return ReviewText.roundText(dateText: date, holes: holes)
    }
}
