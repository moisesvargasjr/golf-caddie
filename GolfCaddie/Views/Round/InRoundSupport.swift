import CoreGraphics
import Foundation
import WatchConnectivity

enum InRoundMetrics {
    /// Apple HIG minimum touch target.
    static let minTouch: CGFloat = 44
}

/// Accessibility identifiers UI and screenshot tests look the round screen up
/// by. Every layout's copy of a control uses the same identifier.
enum InRoundAccessibilityID {
    /// The hole number button; its accessibility value is the hole on screen.
    static let holeNumber = "round.holeNumber"
    static let nextHole = "round.nextHole"
    static let previousHole = "round.previousHole"
    static let map = "round.map"
    static func puttsOption(_ putts: Int) -> String { "round.putts.\(putts)" }
    static let teeShotQuestion = "round.teeShot"
    static let editClubs = "round.clubs.edit"
    static func teeShotOption(_ result: TeeShotResult) -> String { "round.teeShot.\(result.rawValue)" }
    static let reviewTeeGir = "round.review.teeGir"
    static func reviewTeeShot(_ result: TeeShotResult) -> String { "round.review.teeShot.\(result.rawValue)" }
    static let reviewGir = "round.review.gir"
    static let panel = "round.panel"
    static let yardage = "round.yardage"
    static let shotList = "round.shotList"
    static let clubList = "round.clubList"
    static let addShot = "round.addShot"
    static let addPenalty = "round.addPenalty"
    static let finishHole = "round.finishHole"
    static let confirmFinish = "round.confirmFinish"
    static let backToLive = "round.backToLive"
    static let puttsQuestion = "round.puttsQuestion"
    static let penaltyQuestion = "round.penaltyQuestion"
    static let handEntry = "round.handEntry"
    static let saveEntry = "round.saveEntry"
    static let selectedShot = "round.selectedShot"
    static let compass = "round.compass"
    static let hideControls = "round.hideControls"
    static let showControls = "round.showControls"
    static let card = "round.card"
    static let more = "round.more"

    // Review (a finished round)
    static let reviewResult = "round.review.result"
    static let reviewPutts = "round.review.putts"
    static let reviewNext = "round.review.next"

    // Casual
    static let scoreGrid = "round.scoreGrid"
    static let saveScore = "round.saveScore"
    static let roundScores = "round.roundScores"
    static func scoreCell(_ strokes: Int) -> String { "round.scoreGrid.score.\(strokes)" }
    static func puttsCell(_ putts: Int) -> String { "round.scoreGrid.putts.\(putts)" }
    static func roundScoreHole(_ hole: Int) -> String { "round.roundScores.hole.\(hole)" }
}

/// One vocabulary for the in-round actions.
enum InRoundLabels {
    static let shot = "+ SHOT"
    static let penalty = "+ PENALTY"
    static let finish = "Finish hole ›"
}

/// The watch app is reachable, so it is detecting swings.
enum WatchReachability {
    static var isReachable: Bool {
        guard WCSession.isSupported() else { return false }
        let session = WCSession.default
        return session.activationState == .activated && session.isReachable
    }
}
