import Foundation

/// How a round is played, picked at Begin on Home (stored as `RoundMode`).
enum RoundStartMode: String, CaseIterable, Equatable, Sendable {
    case tracking
    case casual

    /// The initial pick: the Settings "Casual by default" toggle.
    static func initial(casualDefault: Bool) -> RoundStartMode {
        casualDefault ? .casual : .tracking
    }

    var title: String {
        switch self {
        case .tracking: return "Track shots"
        case .casual: return "Casual"
        }
    }

    var caption: String {
        switch self {
        case .tracking: return "WATCH + MAP + CLUBS"
        case .casual: return "YARDAGE + SCORE"
        }
    }
}

/// Everything Begin hands to the round start.
struct HomeStartRequest: Equatable, Sendable {
    let startingHole: Int
    let clubsLeftOut: [String]
    let mode: RoundStartMode
    /// Curated course picked on the Course row; nil = detect at the tee.
    let curatedCourseId: String?
}

/// Copy density: the open Duo's roomy pages or the folded single column.
enum HomeCopyStyle: Equatable, Sendable {
    case open
    case folded
}

/// The Start a round panel: mode, course and starting hole. Value type; every
/// change returns a new copy.
struct HomeStartState: Equatable, Sendable {
    static let holeRange = 1...18

    let mode: RoundStartMode
    let startingHole: Int
    let curatedCourseId: String?

    init(mode: RoundStartMode, startingHole: Int = 1, curatedCourseId: String? = nil) {
        self.mode = mode
        self.startingHole = min(max(startingHole, Self.holeRange.lowerBound), Self.holeRange.upperBound)
        self.curatedCourseId = curatedCourseId
    }

    /// Clubs only matter when tracking shots.
    var showsClubsRow: Bool { mode == .tracking }

    func with(mode: RoundStartMode) -> HomeStartState {
        HomeStartState(mode: mode, startingHole: startingHole, curatedCourseId: curatedCourseId)
    }

    func with(courseId: String?) -> HomeStartState {
        HomeStartState(mode: mode, startingHole: startingHole, curatedCourseId: courseId)
    }

    /// Steps the starting hole, wrapping 18 → 1 and 1 → 18 (as the mockup).
    func steppingHole(by delta: Int) -> HomeStartState {
        let count = Self.holeRange.count
        let zeroBased = ((startingHole - 1 + delta) % count + count) % count
        return HomeStartState(mode: mode, startingHole: zeroBased + 1, curatedCourseId: curatedCourseId)
    }

    /// The Course row's value. `names` maps curated ids to course names.
    func courseLabel(names: [String: String]) -> String {
        guard let curatedCourseId else { return "Auto-detect" }
        return names[curatedCourseId] ?? "Linked course"
    }

    func beginSubtitle(clubsInPlay: Int, style: HomeCopyStyle) -> String {
        var parts: [String] = [mode == .tracking ? "TRACKED" : "CASUAL"]
        if mode == .tracking, style == .open { parts.append("\(clubsInPlay) CLUBS") }
        parts.append("HOLE \(startingHole)")
        if startingHole > 1 {
            parts.append(style == .open ? "EARLIER HOLES ADDED LATER" : "ADD EARLIER LATER")
        }
        return parts.joined(separator: " · ")
    }

    func request(clubsLeftOut: [String]) -> HomeStartRequest {
        HomeStartRequest(startingHole: startingHole, clubsLeftOut: clubsLeftOut,
                         mode: mode, curatedCourseId: curatedCourseId)
    }
}

// MARK: - Logbook entries

/// One hole of a stored round, as Home needs it.
struct HomeHoleInput: Equatable, Sendable {
    let number: Int
    let par: Int?
    /// The hole's score (`HoleScoring.score`); 0 when it has none.
    let strokes: Int
    let confirmed: Bool

    /// One stored hole, scored like the card: the hand score for a
    /// hand-entered hole, else shots + penalty strokes; finished when
    /// confirmed or hand-scored; the course's par when the row has none.
    static func make(hole: Hole, shots: [Shot], penaltyStrokes: Int, coursePar: Int?) -> HomeHoleInput {
        let score = HoleScoring.score(hole: hole, shots: shots, penaltyStrokes: penaltyStrokes) ?? 0
        let handScored = hole.isHandScored && hole.handStrokes != nil
        return HomeHoleInput(number: hole.holeNumber, par: hole.par ?? coursePar, strokes: score,
                             confirmed: hole.confirmedAt != nil || handScored)
    }
}

/// A cell in the last entry's score strip.
struct HomeHoleCell: Equatable, Sendable {
    enum Shape: Equatable, Sendable { case plain, circle, square }

    let number: Int
    let score: Int
    let shape: Shape
}

/// A finished round as Home shows it (last entry and earlier rounds).
struct HomeRoundEntry: Identifiable, Equatable {
    let round: Round
    let courseTitle: String
    let score: Int
    /// Par of the holes that were played; 0 when none had a par.
    let par: Int
    let cells: [HomeHoleCell]
    let durationText: String
    let dateText: String

    var id: UUID { round.id }

    /// "+7", "-1", "E"; nil without par.
    var deltaText: String? {
        guard par > 0 else { return nil }
        let delta = score - par
        if delta == 0 { return "E" }
        return delta > 0 ? "+\(delta)" : "\(delta)"
    }

    var dateAndDurationText: String {
        durationText == "—" ? dateText : "\(dateText) · \(durationText)"
    }

    static func make(round: Round, holes: [HomeHoleInput]) -> HomeRoundEntry {
        let played = holes.filter { $0.strokes > 0 }
        let cells = played
            .filter(\.confirmed)
            .sorted { $0.number < $1.number }
            .map { HomeHoleCell(number: $0.number, score: $0.strokes, shape: shape(for: $0)) }
        let trimmed = round.courseName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let duration = round.endedAt.map { $0.timeIntervalSince(round.startedAt) } ?? 0
        return HomeRoundEntry(
            round: round,
            courseTitle: trimmed.isEmpty ? "Untitled round" : trimmed,
            score: played.reduce(0) { $0 + $1.strokes },
            par: played.reduce(0) { $0 + ($1.par ?? 0) },
            cells: cells,
            durationText: HomeViewModel.durationText(duration),
            dateText: HomeViewModel.shortDate(round.startedAt)
        )
    }

    private static func shape(for hole: HomeHoleInput) -> HomeHoleCell.Shape {
        guard let par = hole.par else { return .plain }
        if hole.strokes < par { return .circle }
        if hole.strokes > par { return .square }
        return .plain
    }
}

// MARK: - Selection and copy

/// Pure helpers behind Home: which round is the last entry, the logbook
/// preview, and the bag / date copy.
enum HomeViewModel {
    /// Rows in the open Duo's "Earlier rounds" preview.
    static let earlierRoundsLimit = 3

    /// The most recently started round that has ended.
    static func lastEntry(from rounds: [Round]) -> Round? {
        finished(rounds).first
    }

    /// Finished rounds after `excluding`, newest first, at most `limit`.
    static func earlierRounds(from rounds: [Round], excluding: Round?, limit: Int) -> [Round] {
        Array(finished(rounds).filter { $0.id != excluding?.id }.prefix(max(0, limit)))
    }

    static func bagInPlayText(inPlay: Int, total: Int) -> String {
        "\(inPlay) OF \(total) IN PLAY"
    }

    /// "16 ROUNDS" / "1 ROUND".
    static func roundsText(_ count: Int) -> String { count == 1 ? "1 ROUND" : "\(count) ROUNDS" }

    static func clubsRowText(inPlay: Int, total: Int) -> String {
        "\(inPlay)/\(total)"
    }

    static func bagAccessibilityLabel(inPlay: Int, total: Int) -> String {
        "The bag: \(inPlay) of \(total) clubs in play. Change the clubs in play."
    }

    /// "OCT 24 · FRIDAY" (open) / "OCT 24 · FRI" (folded).
    static func dateStrip(_ date: Date, style: HomeCopyStyle) -> String {
        format(date, style == .open ? "MMM d · EEEE" : "MMM d · EEE")
    }

    /// "OCT 23".
    static func shortDate(_ date: Date) -> String {
        format(date, "MMM d")
    }

    /// "4H 12M", "38M"; "—" when unknown.
    static func durationText(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "—" }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        return hours > 0 ? "\(hours)H \(minutes)M" : "\(minutes)M"
    }

    private static func finished(_ rounds: [Round]) -> [Round] {
        rounds.filter { $0.endedAt != nil }.sorted { $0.startedAt > $1.startedAt }
    }

    private static func format(_ date: Date, _ pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = pattern
        return formatter.string(from: date).uppercased()
    }
}

// MARK: - Watch status

/// The watch's link, shown next to G2 on Home.
enum WatchLinkStatus: Equatable, Sendable {
    /// Paired, app installed, reachable now.
    case ready
    /// Paired with the app installed, but not reachable (asleep / out of range).
    case asleep
    /// No usable watch.
    case unavailable

    static func resolve(isSupported: Bool, isActivated: Bool, isPaired: Bool,
                        isAppInstalled: Bool, isReachable: Bool) -> WatchLinkStatus {
        guard isSupported, isActivated, isPaired, isAppInstalled else { return .unavailable }
        return isReachable ? .ready : .asleep
    }

    var isLive: Bool { self == .ready }

    func label(style: HomeCopyStyle) -> String {
        switch (self, style) {
        case (.ready, .open): return "WATCH READY"
        case (.asleep, .open): return "WATCH ASLEEP"
        case (.ready, .folded), (.asleep, .folded): return "WATCH"
        case (.unavailable, _): return "NO WATCH"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .ready: return "Watch ready"
        case .asleep: return "Watch not reachable"
        case .unavailable: return "No watch"
        }
    }
}
