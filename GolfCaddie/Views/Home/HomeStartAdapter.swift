import Foundation

extension RoundController {
    /// Starts a round from Home's Begin: the hole, the mode picked there (it
    /// replaces the Settings casual default) and the clubs left out.
    func startRound(_ request: HomeStartRequest) throws {
        try startRound(startingHole: request.startingHole,
                       mode: request.mode == .casual ? .casual : .tracking,
                       clubsLeftOut: request.clubsLeftOut)
        setCasualMode(request.mode == .casual)
        // A course picked on the Course row is a manual link; nil leaves the
        // usual detection at the tee.
        if let courseId = request.curatedCourseId {
            setCuratedCourseId(courseId)
        }
    }
}
