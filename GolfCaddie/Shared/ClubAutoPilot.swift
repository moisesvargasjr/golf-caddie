import Foundation

/// Suggest the club whose avg carry is closest to `yards`.
func suggestedClubIndex(_ clubs: [WatchClub], yards: Int) -> Int? {
    guard !clubs.isEmpty else { return nil }
    var best = 0
    var diff = Int.max
    for (i, c) in clubs.enumerated() {
        let d = abs(c.avgYards - yards)
        if d < diff { diff = d; best = i }
    }
    return best
}

/// "The club follows you": while in auto, the watch's selected club tracks the
/// suggestion for the current distance, so the club stamped on a shot is right
/// without touching the crown. A manual pick holds until that shot is logged
/// (stroke count changes) or the hole changes, then auto resumes.
///
/// Before this, the club stayed on whatever was last picked — after a drive the
/// approach was still logged as Driver unless the golfer unlocked, scrolled and
/// re-locked (watch UI review, 2026-09-20).
struct ClubAutoPilot: Equatable {
    /// GPS jitter near the midpoint between two clubs mustn't flip-flop the
    /// selection: only switch when the new club is closer by at least this much.
    static let hysteresisYards = 3

    private(set) var isAuto = true
    private var lastStrokeCount: Int?
    private var lastHole: Int?

    /// The golfer picked a club by hand — hold it for this shot.
    mutating func userPicked() { isAuto = false }

    /// Feed the latest state; returns the club short name to select, or nil for
    /// no change. `clubs` must already exclude the putter (it's button-driven).
    mutating func update(
        hole: Int, strokeCount: Int, yards: Int?, clubs: [WatchClub], currentShort: String?
    ) -> String? {
        if lastHole != hole || lastStrokeCount != strokeCount {
            // First update just records the baseline; after that, a logged shot
            // or a new hole hands control back to auto.
            if lastHole != nil { isAuto = true }
            lastHole = hole
            lastStrokeCount = strokeCount
        }
        guard isAuto, let yards, let idx = suggestedClubIndex(clubs, yards: yards) else { return nil }
        let suggested = clubs[idx]
        guard suggested.short != currentShort else { return nil }
        if let current = clubs.first(where: { $0.short == currentShort }) {
            let gain = abs(current.avgYards - yards) - abs(suggested.avgYards - yards)
            guard gain >= Self.hysteresisYards else { return nil }
        }
        return suggested.short
    }
}
