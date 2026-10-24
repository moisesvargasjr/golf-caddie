import Foundation

// Pure decisions behind `RoundMapScreen`, kept out of the view so they are
// unit tested (RoundMapRulesTests).

// MARK: - Auto-hide wiring

/// Which `AutoHidePauseReason`s the screen's UI state holds open (rule 5:
/// auto-hide pauses while a question, a selected pin or a drag is open).
enum AutoHideWiring {
    static func pauseReasons(questionOpen: Bool, entryOpen: Bool, shotSelected: Bool,
                             dragging: Bool) -> Set<AutoHidePauseReason> {
        var reasons: Set<AutoHidePauseReason> = []
        // The late-start / casual score entry is a question too.
        if questionOpen || entryOpen { reasons.insert(.question) }
        if shotSelected { reasons.insert(.selection) }
        if dragging { reasons.insert(.drag) }
        return reasons
    }

    /// What to tell the controller to move from `current` to `desired`.
    static func changes(from current: Set<AutoHidePauseReason>,
                        to desired: Set<AutoHidePauseReason>)
        -> (pause: Set<AutoHidePauseReason>, resume: Set<AutoHidePauseReason>) {
        (pause: desired.subtracting(current), resume: current.subtracting(desired))
    }

    @MainActor
    static func apply(_ desired: Set<AutoHidePauseReason>, to controller: AutoHideController) {
        let delta = changes(from: controller.pauseReasons, to: desired)
        // Pause before resuming so a swap (question → selection) never lets
        // a countdown start in between with nothing paused.
        for reason in delta.pause { controller.pause(reason) }
        for reason in delta.resume { controller.resume(reason) }
    }
}

// MARK: - What the panel shows for the hole on screen

enum HolePanelState: Equatable, Sendable {
    /// The hole being played: yardage, then shots + SHOT (tracking) or the
    /// round so far (casual), and Finish.
    case live
    /// A finished, tracked hole: its result; pins and clubs stay editable.
    case pastTracked
    /// No tracked shots (before a late start, a skipped hole, a hand-scored
    /// hole): strokes + putts entry (tracking) or the score grid (casual).
    case entry

    /// `mode` is kept for PR 7's review mode; tracking and casual resolve alike
    /// (the casual live hole asks for its score only when Finish is tapped).
    static func resolve(mode: RoundMapMode, isLive: Bool, isTracked: Bool,
                        needsEntry: Bool, isHandScored: Bool) -> HolePanelState {
        if isLive { return .live }
        if needsEntry || isHandScored || !isTracked { return .entry }
        return .pastTracked
    }
}

// MARK: - ‹ › and the hole grid

enum HoleNavigation {
    enum Step: Equatable {
        /// Show this hole (past or before the start); the live hole carries on.
        case view(Int)
        /// Back to following the live hole.
        case live
        /// From the live hole, › moves the live hole on without finishing it
        /// (the old arrows' skip-ahead; the hole stays open to come back to).
        case skipAhead
    }

    static let holes = HoleScoring.holeRange

    /// ‹ — the hole before the one on screen; nil on hole 1.
    static func previous(viewing: Int, live: Int?) -> Step? {
        guard viewing > holes.lowerBound else { return nil }
        let target = viewing - 1
        return target == live ? .live : .view(target)
    }

    /// › — the next hole towards the live one; from the live hole, skip ahead.
    static func next(viewing: Int, live: Int?) -> Step? {
        guard let live else {
            return viewing < holes.upperBound ? .view(viewing + 1) : nil
        }
        if viewing == live { return .skipAhead }
        let target = viewing % holes.upperBound + 1
        return target == live ? .live : .view(target)
    }

    /// A hole picked on the grid: finished, hand-scored or before-the-start
    /// holes open for review/entry; anything else becomes the live hole.
    static func gridPick(_ number: Int, live: Int?, isFinished: Bool,
                         isBeforeStart: Bool) -> Step {
        if number == live { return .live }
        if isFinished || isBeforeStart || live == nil { return .view(number) }
        return .skipAhead
    }
}

// MARK: - One-time "hold the map" tip (Decision 3)

/// The first hold-to-add of any round shows a longer tip; later ones the
/// short toast. "Seen" is remembered in `UserDefaults`.
struct HoldToAddTip {
    static let defaultsKey = "tips.holdToAddShot.seen"
    static let message = "Added where you held — shots are numbered by where they sit along the hole. Drag it to fine-tune, then pick its club."

    let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var hasBeenSeen: Bool { defaults.bool(forKey: Self.defaultsKey) }

    /// The tip for this hold, or nil once seen. Marks it seen.
    func consume() -> String? {
        guard !hasBeenSeen else { return nil }
        defaults.set(true, forKey: Self.defaultsKey)
        return Self.message
    }
}

// MARK: - Text

enum RoundMapFormat {
    /// "E", "+2", "-1".
    static func toPar(_ diff: Int) -> String {
        diff == 0 ? "E" : (diff > 0 ? "+\(diff)" : "\(diff)")
    }

    /// "+1 · 2 SCORED" over the holes that have a score; nil before any.
    /// Holes without a par count as scored but not toward par.
    static func roundScoreText(holes: [(par: Int?, score: Int?)]) -> String? {
        let scored = holes.filter { $0.score != nil }
        guard !scored.isEmpty else { return nil }
        let diff = scored.reduce(0) { total, hole in
            guard let par = hole.par, let score = hole.score else { return total }
            return total + score - par
        }
        return "\(toPar(diff)) · \(scored.count) SCORED"
    }

    /// Round to par alone ("+1") for the compact header; nil before any score.
    static func roundToPar(holes: [(par: Int?, score: Int?)]) -> String? {
        roundScoreText(holes: holes)?.components(separatedBy: " · ").first
    }

    /// Result of a finished hole: "5 (+1) · 2 putts".
    static func resultLine(score: Int?, par: Int?, putts: Int?) -> String {
        guard let score else { return "No score yet" }
        var text = "\(score)"
        if let par { text += " (\(toPar(score - par)))" }
        if let putts { text += " · \(putts) \(putts == 1 ? "putt" : "putts")" }
        return text
    }

    /// "NOT TRACKED · YOU STARTED ON HOLE 7" before a late start, else
    /// "NOT TRACKED".
    static func notTrackedText(holeNumber: Int, startingHole: Int?) -> String {
        guard let startingHole, holeNumber < startingHole else { return "NOT TRACKED" }
        return "NOT TRACKED · YOU STARTED ON HOLE \(startingHole)"
    }

    /// "PAR 4 · CASUAL": the caption with the mode's tag, if any.
    static func tagged(_ caption: String, tag: String?) -> String {
        guard let tag else { return caption }
        return caption + " · " + tag
    }

    /// "PAR 4 · 398 YD" (open) or "PAR 4 · 398 · +1" (compact headers).
    static func holeCaption(par: Int?, length: Int?, unit: String?, roundToPar: String?) -> String {
        var parts = [par.map { "PAR \($0)" } ?? "PAR —"]
        if let length { parts.append(unit.map { "\(length) \($0.uppercased())" } ?? "\(length)") }
        if let roundToPar { parts.append(roundToPar) }
        return parts.joined(separator: " · ")
    }
}
