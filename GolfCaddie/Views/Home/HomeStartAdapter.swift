import Foundation

extension RoundController {
    /// Starts a round from Home's Begin.
    ///
    /// Adapter until PR 2 (`startRound(startingHole:mode:)`) merges: the
    /// existing start adopts the Settings casual default, so the mode picked
    /// at Begin is applied right after it. On merge, the first two calls
    /// become `try startRound(startingHole:mode:)` (plus clubs left out).
    func startRound(_ request: HomeStartRequest) throws {
        try startRound(startingHole: request.startingHole, clubsLeftOut: request.clubsLeftOut)
        setCasualMode(request.mode == .casual)
        // A course picked on the Course row is a manual link; nil leaves the
        // usual detection at the tee.
        if let courseId = request.curatedCourseId {
            setCuratedCourseId(courseId)
        }
    }
}
