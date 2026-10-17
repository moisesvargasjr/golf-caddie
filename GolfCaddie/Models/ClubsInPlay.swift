import Foundation

/// The clubs carried for one round: the bag minus what stayed home that day.
///
/// The bag is everything the golfer owns (B33 lifted the 14-club cap), so
/// offering all of it in a round made the watch's auto-club suggest clubs that
/// weren't there (field test 1, 2026-09-21). A round stores the ids LEFT OUT
/// rather than the ids in play, so a club added to the bag mid-round shows up
/// without touching the round.
enum ClubsInPlay {
    /// The last pick, offered as the default for the next round.
    static let leftOutDefaultsKey = "clubsLeftOut"

    /// `bag` minus `leftOut`, in bag order. Always keeps a putter (the PUTT
    /// keys resolve against one) and falls back to the whole bag rather than
    /// return a round with no full-shot club.
    static func resolve(bag: [Club], leftOut: [String]) -> [Club] {
        guard !leftOut.isEmpty else { return bag }
        let out = Set(leftOut)
        var kept = bag.filter { !out.contains($0.id) }
        guard kept.contains(where: { $0.kind != .putter }) else { return bag }
        if !kept.contains(where: { $0.kind == .putter }),
           let putter = bag.first(where: { $0.kind == .putter }) {
            kept = bag.filter { !out.contains($0.id) || $0.id == putter.id }
        }
        return kept
    }

    /// `leftOut` reduced to what `resolve` actually leaves out of `bag`: ids no
    /// longer in the bag drop off, and so do picks the putter / full-shot rules
    /// override. What a round stores, and what the pick sheet shows.
    static func normalized(bag: [Club], leftOut: [String]) -> [String] {
        let inPlay = Set(resolve(bag: bag, leftOut: leftOut).map(\.id))
        return bag.map(\.id).filter { !inPlay.contains($0) }
    }

    /// Whether `club` may be left out of `bag` given what's already out: not
    /// the last putter in play, and not the last full-shot club.
    static func canLeaveOut(_ club: Club, bag: [Club], leftOut: [String]) -> Bool {
        let out = Set(leftOut)
        let others = bag.filter { $0.id != club.id && !out.contains($0.id) }
        return others.contains { ($0.kind == .putter) == (club.kind == .putter) }
    }
}
