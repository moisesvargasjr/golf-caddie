import CoreLocation
import Foundation

/// Tunable config for Path-B (phone-only) reconstruction (B6). Shares the green
/// radius with Path A; adds a dwell-merge radius. Overridable via `UserDefaults`
/// as a field-test knob; tests pass an explicit config for determinism.
struct PathBConfig: Equatable {
    /// A dwell within this radius of the green anchor is on/around the green, so
    /// it's not a full-shot candidate (≈25 m absorbs green + fringe + GPS noise —
    /// the R1 value).
    var greenRadiusMeters: Double
    /// Dwells within this radius of each other are the same stop (a slow walk-up,
    /// a re-address) and get merged. The R1 prototype landed on 20 m.
    var mergeRadiusMeters: Double

    init(greenRadiusMeters: Double = 25, mergeRadiusMeters: Double = 20) {
        self.greenRadiusMeters = greenRadiusMeters
        self.mergeRadiusMeters = mergeRadiusMeters
    }

    static let mergeRadiusKey = "reconstruct.pathBMergeMeters"

    /// Baked defaults; green radius shares Path A's key so one knob tunes both.
    static var `default`: PathBConfig {
        let d = UserDefaults.standard
        return PathBConfig(
            greenRadiusMeters: (d.object(forKey: ReconstructionConfig.greenRadiusKey) as? Double) ?? 25,
            mergeRadiusMeters: (d.object(forKey: mergeRadiusKey) as? Double) ?? 20
        )
    }
}

/// One reconstructed stroke from Path B: a pin placed from the GPS track (or a
/// known anchor). Unlike Path A — where the watch already located each shot —
/// Path B *infers* positions, so each pin is a starting guess the golfer nudges.
struct PathBShot: Equatable {
    var sequenceNumber: Int
    var latitude: Double
    var longitude: Double
    var isPutt: Bool
    /// false → a fallback pin with no dwell behind it (dropped on the green/tee
    /// because we had fewer dwells than strokes); the UI ambers these to nudge.
    var placedFromDwell: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// The reconstructed hole for Path B: the golfer entered a score, and we turned
/// it into placed strokes — full shots at track dwells, putts clustered on the
/// green.
struct PathBReconstruction: Equatable {
    var shots: [PathBShot]
    var score: Int
    /// How many strokes we estimated were full shots (the rest are putts).
    var estimatedFullCount: Int

    var puttCount: Int { shots.lazy.filter(\.isPutt).count }
    var fullShotCount: Int { shots.count - puttCount }
    /// Fallback pins with no dwell behind them — what the golfer should reposition.
    var unplacedShots: [PathBShot] { shots.filter { !$0.placedFromDwell } }
}

/// Pure Path-B (phone-only) reconstruction (B6). Data-in / data-out so it's
/// unit-testable like `TrackSegmenter` / `Reconstructor`. A faithful port of the
/// R1 Python prototype's `path_b`, validated against the real Emerald Isle round
/// (split exact 5/18 holes, ~11 m placement). The golfer supplies a score; the
/// track supplies dwells; this estimates the full/putt split and places pins.
enum PathBReconstructor {
    /// Combine dwells within `meters` of the previous kept stop (a slow walk-up
    /// reads as several stays). Dwell-weighted centroid; the merged stop's
    /// `dwellSeconds` is the SUM of its parts (encoded via a synthetic
    /// `departure`) so longer total stands stay stronger candidates. Time-ordered.
    static func mergeStops(_ stops: [TrackStop], within meters: Double) -> [TrackStop] {
        let ordered = stops.sorted { $0.arrival < $1.arrival }
        var out: [TrackStop] = []
        for s in ordered {
            guard let last = out.last,
                  Distance.meters(from: last.coordinate, to: s.coordinate) <= meters else {
                out.append(s)
                continue
            }
            let w0 = last.dwellSeconds + 1   // +1 (Laplace) so a 0 s dwell still counts
            let w1 = s.dwellSeconds + 1
            let w = w0 + w1
            let lat = (last.latitude * w0 + s.latitude * w1) / w
            let lng = (last.longitude * w0 + s.longitude * w1) / w
            let arrival = min(last.arrival, s.arrival)
            let summedDwell = last.dwellSeconds + s.dwellSeconds
            let prominence = min(1.0, summedDwell / TrackSegmenter.prominenceSaturationSeconds)
            out[out.count - 1] = TrackStop(
                latitude: lat,
                longitude: lng,
                arrival: arrival,
                departure: arrival.addingTimeInterval(summedDwell),
                sampleCount: last.sampleCount + s.sampleCount,
                prominence: prominence
            )
        }
        return out
    }

    /// Reconstruct the hole's strokes from the entered `score`, the track's dwell
    /// `stops`, and the tee/green anchors.
    ///
    /// 1. Merge nearby dwells.
    /// 2. Off-green dwells are full-shot candidates; estimate the full count as
    ///    their number, clamped to `1...score`.
    /// 3. Keep the longest-dwell candidates, back in time order, as the full-shot
    ///    pins; snap shot 1 to the tee.
    /// 4. The remaining strokes are putts, clustered on the green.
    static func reconstruct(score: Int, stops: [TrackStop],
                            tee: CLLocationCoordinate2D?, green: CLLocationCoordinate2D?,
                            config: PathBConfig = .default) -> PathBReconstruction {
        guard score > 0 else {
            return PathBReconstruction(shots: [], score: max(0, score), estimatedFullCount: 0)
        }

        let merged = mergeStops(stops, within: config.mergeRadiusMeters)
        let offGreen: [TrackStop]
        if let green {
            offGreen = merged.filter {
                Distance.meters(from: $0.coordinate, to: green) > config.greenRadiusMeters
            }
        } else {
            offGreen = merged // no green anchor → can't green-split; treat all as full candidates
        }

        let estFull = max(1, min(score, offGreen.isEmpty ? 1 : offGreen.count))

        // Strongest `estFull` candidates by total dwell, returned to play (time) order.
        let chosen = offGreen.sorted { $0.dwellSeconds > $1.dwellSeconds }
            .prefix(estFull)
            .sorted { $0.arrival < $1.arrival }

        var shots: [PathBShot] = chosen.map {
            PathBShot(sequenceNumber: 0, latitude: $0.latitude, longitude: $0.longitude,
                      isPutt: false, placedFromDwell: true)
        }

        // Fewer dwells than estimated full shots (only when nothing was off-green):
        // drop the remainder on the green as clearly-fallback pins.
        while shots.count < estFull {
            let c = green ?? tee ?? chosen.last?.coordinate ?? .init(latitude: 0, longitude: 0)
            shots.append(PathBShot(sequenceNumber: 0, latitude: c.latitude, longitude: c.longitude,
                                   isPutt: false, placedFromDwell: false))
        }

        // Shot 1 is the tee shot — snap it to the tee anchor when we have one
        // (after padding, so a no-track hole still gets its drive on the tee, not
        // the green fallback).
        if let tee, !shots.isEmpty {
            shots[0].latitude = tee.latitude
            shots[0].longitude = tee.longitude
            shots[0].placedFromDwell = true // a known anchor, not a guess
        }

        // Remaining strokes are putts — cluster on the green (a sensible spot when
        // we know it, so not flagged; a guess otherwise).
        let putts = max(0, score - estFull)
        if putts > 0 {
            let c = green ?? shots.last?.coordinate ?? tee ?? .init(latitude: 0, longitude: 0)
            for _ in 0..<putts {
                shots.append(PathBShot(sequenceNumber: 0, latitude: c.latitude, longitude: c.longitude,
                                       isPutt: true, placedFromDwell: green != nil))
            }
        }

        // Stamp sequence numbers in final order.
        for i in shots.indices { shots[i].sequenceNumber = i + 1 }

        return PathBReconstruction(shots: shots, score: score, estimatedFullCount: estFull)
    }
}
