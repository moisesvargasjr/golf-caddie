import CoreLocation
import Foundation

/// Lazy per-club average yardage computed from historical GPS shots. Used by
/// the Active Round bottom sheet to label each club cell ("avg 150 yd").
///
/// Cheap to query (returns nil when fewer than 3 samples exist for a club —
/// the call site hides the label in that case). Recomputed on demand; cache
/// keyed by ClubID with a single global invalidation timestamp.
@MainActor
final class ClubAverages {
    static let shared = ClubAverages()

    private var cache: [ClubID: Int] = [:]
    private var lastComputeAt: Date?
    /// How long to trust the cache. A round can move averages a little; one
    /// minute is fine for an in-play overlay (no need for live updates).
    private let ttl: TimeInterval = 60

    /// Yards per club, computed from successive-shot GPS distances across all
    /// rounds. Returns nil when fewer than `minSamples` distance samples
    /// exist for that club.
    func average(for club: ClubID, minSamples: Int = 3) -> Int? {
        if cache.isEmpty || lastComputeAt.map({ Date().timeIntervalSince($0) > ttl }) ?? true {
            recompute(minSamples: minSamples)
        }
        return cache[club]
    }

    private func recompute(minSamples: Int) {
        var sums: [ClubID: (sum: Double, n: Int)] = [:]
        // For each round, pull its shots in sequence; for shot i with club X,
        // distance to shot i+1 (if both have GPS) attributes that distance to
        // club X (the club that hit the ball ending at shot i+1).
        let rounds = (try? RoundRepository.allRounds()) ?? []
        for round in rounds {
            let holes = (try? HoleRepository.holesForRound(round.id)) ?? []
            for hole in holes {
                let shots = (try? ShotRepository.shotsForHole(hole.id)) ?? []
                // Need at least two shots to compute a distance pair. `0..<count - 1`
                // would trap when count is 0; guard explicitly.
                guard shots.count >= 2 else { continue }
                for idx in 0..<(shots.count - 1) {
                    let curr = shots[idx]
                    let next = shots[idx + 1]
                    guard let club = next.club,
                          let cLat = curr.latitude, let cLng = curr.longitude,
                          let nLat = next.latitude, let nLng = next.longitude
                    else { continue }
                    let m = Distance.meters(
                        from: CLLocationCoordinate2D(latitude: cLat, longitude: cLng),
                        to: CLLocationCoordinate2D(latitude: nLat, longitude: nLng)
                    )
                    let yds = Distance.yards(fromMeters: m)
                    var entry = sums[club] ?? (0, 0)
                    entry.sum += yds
                    entry.n += 1
                    sums[club] = entry
                }
            }
        }
        var result: [ClubID: Int] = [:]
        for (club, entry) in sums where entry.n >= minSamples {
            result[club] = Int((entry.sum / Double(entry.n)).rounded())
        }
        cache = result
        lastComputeAt = Date()
    }

    /// Force-recompute on next query — call after a round ends to refresh.
    func invalidate() {
        cache = [:]
        lastComputeAt = nil
    }
}
