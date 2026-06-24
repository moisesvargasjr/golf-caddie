import CoreLocation
import Foundation

/// Tunable config for end-of-hole reconstruction (B7/B6). Like `StopDetectionConfig`,
/// the green radius is a field-test knob overridable via `UserDefaults` without a
/// rebuild; tests pass an explicit config so they stay deterministic.
struct ReconstructionConfig: Equatable {
    /// A stroke struck from within this radius of the green anchor is a putt
    /// (DESIGN green-split). ~25 m absorbs green + fringe + GPS noise — the value
    /// the R1 prototype landed on against the real Emerald Isle round.
    var greenRadiusMeters: Double
    /// GPS accuracy (m) at/below which a located full shot is fully trusted (1.0).
    var goodAccuracyMeters: Double
    /// GPS accuracy (m) at/above which a located full shot is least trusted (floor).
    var poorAccuracyMeters: Double

    init(greenRadiusMeters: Double = 25, goodAccuracyMeters: Double = 6, poorAccuracyMeters: Double = 25) {
        self.greenRadiusMeters = greenRadiusMeters
        self.goodAccuracyMeters = goodAccuracyMeters
        self.poorAccuracyMeters = poorAccuracyMeters
    }

    static let greenRadiusKey = "reconstruct.greenRadiusMeters"

    /// Baked defaults, green radius overridable at runtime (field-test knob).
    static var `default`: ReconstructionConfig {
        let stored = UserDefaults.standard.object(forKey: greenRadiusKey) as? Double
        return ReconstructionConfig(greenRadiusMeters: stored ?? 25)
    }
}

/// One stroke as the end-of-hole confirmation card sees it: the source shot plus
/// the derived classification. `applied` is the shot with `isPutt`/`confidence`
/// written back, ready for the integration layer (B7.2) to persist.
struct ReconstructedShot: Equatable, Identifiable {
    var shot: Shot
    var isPutt: Bool
    /// 0…1; the card ambers strokes below `HoleReconstruction.lowConfidenceThreshold`.
    var confidence: Double

    var id: UUID { shot.id }
    var applied: Shot {
        var s = shot
        s.isPutt = isPutt
        s.confidence = confidence
        return s
    }
}

/// The reconciled end-of-hole view for one hole (Path A): the live-logged shots —
/// already *located* by `LiveShotCoordinator.fuse()` at swing time — classified
/// into full shots + putts, each scored for confidence, with the detected count
/// checked against the score the golfer entered.
struct HoleReconstruction: Equatable {
    var shots: [ReconstructedShot]   // sequence order
    var enteredScore: Int?

    var puttCount: Int { shots.lazy.filter(\.isPutt).count }
    var fullShotCount: Int { shots.count - puttCount }

    /// How the detected stroke count squares with the entered score.
    enum CountReconciliation: Equatable {
        case noScore                  // score not entered yet
        case matches                  // detected == entered
        case detectedFewer(by: Int)   // entered > detected → likely a missed detection
        case detectedMore(by: Int)    // detected > entered → likely a phantom
    }
    var reconciliation: CountReconciliation {
        guard let entered = enteredScore else { return .noScore }
        let detected = shots.count
        if entered == detected { return .matches }
        return entered > detected ? .detectedFewer(by: entered - detected)
                                  : .detectedMore(by: detected - entered)
    }

    static let lowConfidenceThreshold = 0.5
    var lowConfidenceShots: [ReconstructedShot] {
        shots.filter { $0.confidence < Self.lowConfidenceThreshold }
    }
}

/// Pure end-of-hole reconstruction (Path A). Data-in / data-out — no DB, no UI —
/// so it's unit-testable like `TrackSegmenter`. Locations are already supplied by
/// the live `fuse()` (swing time → nearest breadcrumb, validated to GPS noise in
/// the R1 prototype); this layer classifies putts (green-split), scores confidence,
/// and reconciles the detected count against the entered score.
enum Reconstructor {
    /// A stroke is a putt if it was logged with the putter OR it was struck from
    /// inside the green radius (DESIGN green-split). A no-GPS non-putter can't be
    /// green-classified, so it conservatively stays a full shot (the card lets the
    /// golfer toggle it).
    static func isPutt(_ shot: Shot, green: CLLocationCoordinate2D?,
                       config: ReconstructionConfig) -> Bool {
        if shot.club == .putter { return true }
        guard let green, let lat = shot.latitude, let lng = shot.longitude else { return false }
        return Distance.meters(from: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                               to: green) <= config.greenRadiusMeters
    }

    /// Confidence (0…1) that a full shot is correctly located: high when the GPS
    /// fix was tight, low when loose or absent. Putts cluster on the green and
    /// don't need a precise location, so they're always confident.
    static func confidence(for shot: Shot, isPutt: Bool,
                           config: ReconstructionConfig) -> Double {
        if isPutt { return 1.0 }
        guard shot.hadGPS, let acc = shot.gpsAccuracy else { return 0.2 } // no fix → amber
        if acc <= config.goodAccuracyMeters { return 1.0 }
        if acc >= config.poorAccuracyMeters { return 0.3 }
        let span = config.poorAccuracyMeters - config.goodAccuracyMeters
        return 1.0 - 0.7 * (acc - config.goodAccuracyMeters) / span // linear 1.0 → 0.3
    }

    /// Classify + score the hole's shots and reconcile against the entered score.
    static func reconstruct(shots: [Shot], green: CLLocationCoordinate2D?,
                            enteredScore: Int? = nil,
                            config: ReconstructionConfig = .default) -> HoleReconstruction {
        let rshots = shots
            .sorted { $0.sequenceNumber < $1.sequenceNumber }
            .map { shot -> ReconstructedShot in
                let putt = isPutt(shot, green: green, config: config)
                return ReconstructedShot(shot: shot, isPutt: putt,
                                         confidence: confidence(for: shot, isPutt: putt, config: config))
            }
        return HoleReconstruction(shots: rshots, enteredScore: enteredScore)
    }
}
