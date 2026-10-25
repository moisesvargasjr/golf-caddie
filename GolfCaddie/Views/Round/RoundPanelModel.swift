import SwiftUI

// What every layout draws, as plain values. `RoundMapScreen` builds one
// `RoundPanelModel` per render from the hole session and the round; the
// layouts only arrange the shared components and call `RoundPanelActions`,
// so a layout can be redrawn without touching round logic.

struct RoundYardage: Equatable {
    /// Middle of the green, display units.
    let middle: Int
    let front: Int
    let back: Int
    let unit: String
    /// "WATCH GPS" / "PHONE GPS".
    let sourceText: String?
}

struct ShotRowModel: Identifiable, Equatable {
    let id: UUID
    let number: Int
    /// "Dr", or "?" until a held-in shot gets its club.
    let clubText: String
    /// "251 YD" to the next shot (or the green on a finished hole).
    let distanceText: String?
    let isSelected: Bool
    let needsClub: Bool

    var leftText: String { "\(number) · \(clubText)" }
}

struct PenaltyRowModel: Identifiable, Equatable {
    let id: UUID
    let title: String
    let strokes: Int
}

struct ClubChipModel: Identifiable, Equatable {
    let club: Club
    /// Carry in display units ("148").
    let carryText: String?
    let isActive: Bool
    var id: String { club.id }
}

struct RoundToast: Equatable {
    enum Kind: Equatable { case info, tip, error }
    let text: String
    var kind: Kind = .info
}

struct RoundPanelModel {
    var mode: RoundMapMode
    var layout: RoundMapLayout

    // Hole
    var holeNumber: Int
    var liveHoleNumber: Int?
    var par: Int?
    /// "PAR 4 · 398 YD"
    var holeCaption: String
    /// "PAR 4 · 398 · +1"
    var compactCaption: String
    /// "H8 · P4" (hidden-controls label)
    var shortCaption: String
    var canGoPrevious: Bool
    var canGoNext: Bool
    var state: HolePanelState
    /// The live round's current hole is on screen (in any mode).
    var viewingLive: Bool

    // Round
    /// "+1 · 2 SCORED"
    var roundScoreText: String?
    var courseName: String?
    var needsCourseLink: Bool

    // Live hole
    var yardage: RoundYardage?
    var watchDetecting: Bool
    var isMarking: Bool

    // Past hole
    /// "5 (+1) · 2 putts"
    var resultText: String

    // Shots
    var shotRows: [ShotRowModel]
    var penaltyRows: [PenaltyRowModel]
    /// "2 · 8i · NEXT" on the live hole.
    var nextShotText: String?
    var selectedShotTitle: String?
    var hasSelection: Bool { selectedShotTitle != nil }

    // Clubs
    var clubs: [ClubChipModel]
    /// "NEXT SHOT", "SHOT 2", "TAP A SHOT".
    var clubListTitle: String
    var clubListHighlighted: Bool
    var clubsEnabled: Bool

    // Questions
    var question: RoundMapQuestion?
    var puttsChoice: Int
    /// Finish hole's tee-shot pick (par 4s and 5s); nil = none yet.
    var teeShotChoice: TeeShotResult? = nil
    /// Finish hole asks where the tee shot finished (par 4s and 5s).
    var asksTeeShot: Bool = false
    var puttsSummary: String
    var finishConfirmTitle: String

    // Entry
    var entry: HandScoreDraft
    var entryTitle: String
    var entrySummary: String
    var entrySaveTitle: String
    var notTrackedText: String
    var entryShowsBackToLive: Bool

    // Casual
    /// Every scored hole, newest first, with the running total.
    var roundSoFar: RoundSoFar = .empty
    /// The score grid's picks (casual Finish, or a casual hole being edited).
    var scoreDraft: ScoreGridDraft = .empty

    // Chrome
    var controlsVisible: Bool
    var compassRotation: Double
    var toast: RoundToast?

    // Review (a finished round; PR 7)
    /// Next hole › / Back to card ›; nil outside review.
    var reviewNext: ReviewNavigation.Next? = nil
    /// "RESULT · 3 SHOTS + 2 PUTTS".
    var reviewResultLabel: String = ""
    /// The hole's score (nil before one is entered).
    var reviewScore: Int? = nil
    /// "+1 · BOGEY".
    var reviewToParLabel: String = ""
    /// The hole's putts (the result card's stepper).
    var putts: Int? = nil
    /// The result card's TEE row: the tee shot's finish (par 4s and 5s).
    var reviewTeeShot: TeeShotResult? = nil
    /// The hole is a par 4 or 5, so the TEE row offers the four choices.
    var reviewAsksTeeShot: Bool = false
    /// GIR as the card shows it (the golfer's, else worked out); nil = unknown.
    var reviewGir: Bool? = nil
    /// `reviewGir` is the golfer's own answer (YOU), not worked out (AUTO).
    var reviewGirIsManual: Bool = false
    /// ··· items for a finished round; nil in the live round.
    var roundActions: RoundActionsAvailability? = nil
    /// The ··· section header ("NATIVE OAKS · OCT 23 · 79 (+7)").
    var roundActionsTitle: String = "THIS ROUND"
    /// COURSE MAP beside ‹ CARD: a finished round's hole opened on the
    /// course map's screen (PR 8). Glides the same map back out.
    var offersCourseMap: Bool = false

    var showsClubList: Bool { state != .entry && mode.tracksShots }
    /// The round so far takes the shot list's / club list's place (casual).
    var showsRoundSoFar: Bool { mode.showsRoundSoFar }
    /// The 1–10+ grid is open: casual Finish, or a casual hole entered by hand.
    var showsScoreGrid: Bool {
        question == .score || (question == nil && state == .entry && mode.entryUsesScoreGrid)
    }
    /// Saving the grid moves the round on (Finish on the live hole).
    var scoreGridAdvances: Bool { question == .score }
    /// The panel shows an answer area (putts, grid, entry) instead of the actions.
    var isAsking: Bool { question == .putts || showsScoreGrid || state == .entry }
    var isLiveHole: Bool { state == .live }
    var backToLiveTitle: String { "Back to hole \(liveHoleNumber ?? holeNumber) ›" }
    /// Short version for narrow buttons.
    var backToLiveShortTitle: String { "BACK TO HOLE \(liveHoleNumber ?? holeNumber)" }
    var hintText: String {
        if reviewNext != nil { return ReviewText.reviewHint }
        return watchDetecting ? "WATCH IS DETECTING SWINGS · HOLD THE MAP TO ADD A SHOT"
            : "DRAG A PIN TO MOVE IT · HOLD THE MAP TO ADD ONE"
    }
    /// The hint line over the actions: the live tracked hole, or a finished
    /// tracked hole in review.
    var showsPanelHint: Bool {
        (isLiveHole && mode.tracksShots) || (reviewNext != nil && state == .pastTracked)
    }
    /// The result card's PUTTS stepper (review, a tracked hole; a hand-scored
    /// hole edits its putts in the score entry).
    var showsPuttsStepper: Bool { mode.editsPuttsInResult && state == .pastTracked }
    var cardTitle: String { mode.cardButtonTitle }
    /// "5", or "—" before a score.
    var reviewScoreText: String { reviewScore.map { String($0) } ?? "—" }
    /// Review shows the hole's result card: a finished tracked hole, or a
    /// hole already scored by hand (one still to enter shows NOT TRACKED).
    var showsReviewResult: Bool {
        reviewNext != nil && (state == .pastTracked || (state == .entry && reviewScore != nil))
    }
    /// The result card's TEE + GIR row: any scored hole in review.
    var showsTeeGirRow: Bool { showsReviewResult }
}

struct RoundPanelActions {
    var previousHole: () -> Void = {}
    var nextHole: () -> Void = {}
    var openHoleGrid: () -> Void = {}
    var backToLive: () -> Void = {}

    var addShot: () -> Void = {}
    var askPenalty: () -> Void = {}
    var finishHole: () -> Void = {}

    var pickPutts: (Int) -> Void = { _ in }
    /// Finish hole's tee shot (tapping the picked one clears it).
    var pickTeeShot: (TeeShotResult) -> Void = { _ in }
    var confirmFinish: () -> Void = {}
    var pickPenalty: (PenaltyType) -> Void = { _ in }
    var cancelQuestion: () -> Void = {}

    var selectShot: (UUID) -> Void = { _ in }
    var removePenalty: (UUID) -> Void = { _ in }
    var pickClub: (Club) -> Void = { _ in }
    var deleteSelectedShot: () -> Void = {}
    var doneSelection: () -> Void = {}

    /// Score grid (casual): a score cell, a putts cell, save.
    var pickScore: (Int) -> Void = { _ in }
    var pickScorePutts: (Int) -> Void = { _ in }
    var saveScore: () -> Void = {}
    /// A hole in the round-so-far list: open it to edit its score.
    var openRoundHole: (Int) -> Void = { _ in }

    /// Review: Next hole › (or Back to card ›), and the result card's putts.
    var reviewNext: () -> Void = {}
    var stepPutts: (Int) -> Void = { _ in }
    /// Review: the TEE row (tapping the picked one clears it) and GIR toggle.
    var setReviewTeeShot: (TeeShotResult) -> Void = { _ in }
    var toggleGir: () -> Void = {}

    var stepEntryStrokes: (Int) -> Void = { _ in }
    var stepEntryPutts: (Int) -> Void = { _ in }
    var saveEntry: () -> Void = {}

    var hideControls: () -> Void = {}
    var showControls: () -> Void = {}
    var resetCompass: () -> Void = {}
    /// Any touch on the controls (restarts the auto-hide countdown).
    var noteInteraction: () -> Void = {}

    var openCard: () -> Void = {}
    var openBag: () -> Void = {}
    var linkCourse: () -> Void = {}
    var unlinkCourse: () -> Void = {}
    var toggleCasual: () -> Void = {}
    var endRound: () -> Void = {}
    /// ··· for a finished round (review).
    var roundActions = RoundActionHandlers()
    /// COURSE MAP (review on a finished round's course map).
    var openCourseMap: () -> Void = {}
}
