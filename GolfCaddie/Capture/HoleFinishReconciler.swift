import CoreLocation
import Foundation

/// End-of-hole reconciliation for the watch "Finish Hole" check: the golfer
/// says how many putts and confirms the score; that score is the truth and the
/// tracked strokes are evidence. Pure planning — `RoundController.finishHole`
/// applies it.
///
///   score = full shots + putts + penalty strokes
///
/// - Putts are made to equal the number given (they carry no location worth
///   keeping, and the golfer just told us the count).
/// - Too FEW full shots tracked → the detector missed some (chips and partial
///   swings, typically): add unlocated placeholders, which review flags amber.
/// - Too MANY → phantoms (practice swings): EXCLUDE the least-likely-real ones —
///   never a stroke the golfer logged by hand.
enum HoleFinishReconciler {
    struct Plan: Equatable {
        var puttsToAdd = 0
        var fullShotsToAdd = 0
        /// Strokes to exclude (restorable), putts and phantom full shots alike.
        var excludeIDs: [UUID] = []
        /// Phantoms we were told exist but couldn't safely pick (only hand-logged
        /// strokes left): the hole keeps them and scores high — review decides.
        var unresolvedExtra = 0
    }

    static func plan(shots: [Shot], penaltyStrokes: Int, putts: Int, score: Int) -> Plan {
        var plan = Plan()
        let putts = max(0, putts)
        let targetFull = max(0, score - putts - max(0, penaltyStrokes))

        let puttShots = shots.filter(\.isPutt).sorted { $0.sequenceNumber < $1.sequenceNumber }
        if puttShots.count < putts {
            plan.puttsToAdd = putts - puttShots.count
        } else {
            plan.excludeIDs += puttShots.suffix(puttShots.count - putts).map(\.id) // newest first to go
        }

        let full = shots.filter { !$0.isPutt }.sorted { $0.sequenceNumber < $1.sequenceNumber }
        if full.count < targetFull {
            plan.fullShotsToAdd = targetFull - full.count
        } else if full.count > targetFull {
            let surplus = full.count - targetFull
            let ranked = phantomRanking(full)
            plan.excludeIDs += ranked.prefix(surplus).map(\.id)
            plan.unresolvedExtra = max(0, surplus - ranked.count)
        }
        return plan
    }

    /// Auto-detected full shots, most-likely-phantom first. v1 evidence:
    ///   1. never placed (no GPS) — nothing ties it to the course;
    ///   2. struck from (nearly) the same spot as the NEXT stroke — a practice
    ///      swing: you don't move, then the real one follows. The EARLIER of the
    ///      pair is the practice swing;
    ///   3. otherwise the closer it is to its nearest neighbour, the more suspect.
    /// Hand-logged strokes (MARK, phone button, glasses, pins) are never candidates.
    static func phantomRanking(_ fullShots: [Shot]) -> [Shot] {
        let ordered = fullShots.sorted { $0.sequenceNumber < $1.sequenceNumber }
        func coord(_ s: Shot) -> CLLocationCoordinate2D? {
            guard let lat = s.latitude, let lng = s.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        func gap(_ a: Shot, _ b: Shot) -> Double? {
            guard let ca = coord(a), let cb = coord(b) else { return nil }
            return Distance.meters(from: ca, to: cb)
        }
        let scored: [(shot: Shot, score: Double)] = ordered.enumerated().compactMap { i, shot in
            guard shot.source == .watchAuto else { return nil }
            guard coord(shot) != nil else { return (shot, 0) } // unplaced: most suspect
            let toNext = i + 1 < ordered.count ? gap(shot, ordered[i + 1]) : nil
            let toPrev = i > 0 ? gap(ordered[i - 1], shot) : nil
            // Distance to the following stroke counts double: standing still
            // BEFORE the next swing is the practice-swing signature.
            let nearest = [toNext.map { $0 * 0.5 }, toPrev].compactMap { $0 }.min() ?? .greatestFiniteMagnitude
            return (shot, 1 + nearest)
        }
        return scored.sorted { $0.score < $1.score }.map(\.shot)
    }
}
