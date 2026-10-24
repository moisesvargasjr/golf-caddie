import Foundation

/// The writes behind a finished round's ··· (moved from the old
/// `RoundReviewView`): link / unlink its curated course, delete it, and what
/// Share round hands the share sheet.
@MainActor
enum FinishedRoundActions {
    /// Links (or, with nil, unlinks) the round's curated course. A link also
    /// adopts the course's name as the round's label — the same as the
    /// in-round link — so a wrong auto-detected name gets replaced. Returns
    /// the updated round; the passed one is not changed.
    static func settingCourse(_ id: String?, on round: Round, courses: [CuratedCourse]) throws -> Round {
        try RoundRepository.setCuratedCourseId(roundID: round.id, id: id)
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

    /// Share round: a one-line summary plus the logbook's `.sqlite` snapshot
    /// (the same export as Settings → Export Rounds).
    static func shareItems(for round: Round) throws -> [Any] {
        let url = try Database.makeExport()
        let text = ReviewText.shareText(courseName: round.courseName, roundText: roundText(for: round))
        return [text, url]
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
