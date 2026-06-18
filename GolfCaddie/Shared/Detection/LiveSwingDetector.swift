import Foundation

/// Streaming, on-wrist port of `scripts/swing_spike/detect.py` (impact-led).
/// Foundation-only and platform-agnostic (plain `Double` samples, no
/// CoreMotion) so it compiles into the watch app AND the iOS test target for
/// replay-parity testing against the offline detector.
///
/// Design: a ball strike is a large, brief, DISCRETE high-frequency event
/// (10–22 g high-passed vs <1 g for putts/noise). We detect impact peaks on a
/// high-passed accelerometer channel, then gate each by a swing-arc envelope
/// (smoothed gyro magnitude) in the ~1 s leading into it — rejecting
/// bag-drops/taps while surviving the continuous between-shot motion that
/// broke the original arc-first detector.
///
/// **Causal-filter note:** `detect.py` uses `scipy.sosfiltfilt` (zero-phase,
/// forward+backward — non-causal, needs the whole signal). That cannot run
/// live, so this uses a forward-only 4th-order Butterworth high-pass (two RBJ
/// biquads, Butterworth Q pair). Forward-only filtering shifts phase and
/// changes the transient's magnitude, so `impactThreshG` is re-tuned against
/// THIS filter via the parity test — the same empirical loop the offline
/// thresholds went through on range data.
final class LiveSwingDetector {
    struct Params {
        var sampleRateHz: Double = 100
        var impactHpHz: Double = 20
        var impactThreshG: Double = 3.0 // re-tuned for the causal filter (see LiveSwingDetectorTests)
        var refractoryS: Double = 0.6
        var arcThresh: Double = 6.0
        var arcPreS: Double = 1.0
        var arcPostS: Double = 0.2
        var smoothS: Double = 0.05
    }

    struct Detection: Equatable {
        let t: Double // impact timestamp, in the input sample clock
        let impactPeakG: Double
        let arcGyro: Double
    }

    private let p: Params
    private var hpX: ButterworthHighPass4
    private var hpY: ButterworthHighPass4
    private var hpZ: ButterworthHighPass4

    // Gyro smoothing (trailing boxcar) + a timestamped envelope ring for the
    // arc-gate lookback/lookahead window.
    private var gyroWindow: [Double] = []
    private let gyroWindowSize: Int
    private var arcRing: [(t: Double, env: Double)] = []

    // Open impact cluster (consecutive above-threshold samples within refractory).
    private var clusterOpen = false
    private var clusterPeakT = 0.0
    private var clusterPeakHp = 0.0
    private var clusterLastAboveT = 0.0

    private var latestTime = 0.0

    /// Emitted on the caller's thread when a detection is confirmed.
    var onDetection: ((Detection) -> Void)?

    /// Recent peak of the high-passed impact channel (g), reported ~10×/s — a
    /// live "the watch is sensing motion" meter for the UI. Peak-hold with decay
    /// so a brief spike stays visible.
    var onActivity: ((Double) -> Void)?
    private var activityPeak = 0.0
    private var accelCount = 0

    init(params: Params = Params()) {
        self.p = params
        self.hpX = ButterworthHighPass4(fs: params.sampleRateHz, cutoffHz: params.impactHpHz)
        self.hpY = ButterworthHighPass4(fs: params.sampleRateHz, cutoffHz: params.impactHpHz)
        self.hpZ = ButterworthHighPass4(fs: params.sampleRateHz, cutoffHz: params.impactHpHz)
        self.gyroWindowSize = max(1, Int((params.smoothS * params.sampleRateHz).rounded()))
    }

    /// Feed a raw accelerometer sample (g). May confirm a pending detection.
    func ingestAccel(t: Double, x: Double, y: Double, z: Double) {
        latestTime = max(latestTime, t)
        let fx = hpX.process(x), fy = hpY.process(y), fz = hpZ.process(z)
        let hp = (fx * fx + fy * fy + fz * fz).squareRoot()

        if hp >= p.impactThreshG {
            if !clusterOpen || hp > clusterPeakHp {
                clusterPeakHp = hp
                clusterPeakT = t
            }
            clusterOpen = true
            clusterLastAboveT = t
        }
        // Live activity meter: peak-hold with per-sample decay, reported ~10×/s.
        activityPeak = Swift.max(activityPeak * 0.9, hp)
        accelCount += 1
        if accelCount % 10 == 0 { onActivity?(activityPeak) }
        finalizeIfReady(now: t)
    }

    /// Feed a gyro / rotation-rate sample (rad/s). Builds the swing-arc envelope.
    func ingestGyro(t: Double, x: Double, y: Double, z: Double) {
        latestTime = max(latestTime, t)
        let mag = (x * x + y * y + z * z).squareRoot()
        gyroWindow.append(mag)
        if gyroWindow.count > gyroWindowSize { gyroWindow.removeFirst(gyroWindow.count - gyroWindowSize) }
        let env = gyroWindow.reduce(0, +) / Double(gyroWindow.count)
        arcRing.append((t, env))
        // Prune older than we could ever need (arcPre back from a peak that is
        // itself up to refractory in the past when finalized).
        let horizon = t - (p.arcPreS + p.refractoryS + 0.5)
        if let firstKeep = arcRing.firstIndex(where: { $0.t >= horizon }), firstKeep > 0 {
            arcRing.removeFirst(firstKeep)
        }
        finalizeIfReady(now: t)
    }

    private func finalizeIfReady(now: Double) {
        guard clusterOpen, now - clusterLastAboveT >= p.refractoryS else { return }
        // Refractory (0.6 s) > arcPostS (0.2 s), so the arc window's future
        // gyro is already in the ring by the time we finalize.
        let lo = clusterPeakT - p.arcPreS
        let hi = clusterPeakT + p.arcPostS
        let arc = arcRing.filter { $0.t >= lo && $0.t <= hi }.map(\.env).max() ?? 0
        if arc >= p.arcThresh {
            onDetection?(Detection(t: clusterPeakT, impactPeakG: clusterPeakHp, arcGyro: arc))
        }
        clusterOpen = false
        clusterPeakHp = 0
    }
}

/// 4th-order Butterworth high-pass = two cascaded RBJ biquad sections with the
/// Butterworth Q pair. Direct-Form-II transposed, forward-only (causal).
struct ButterworthHighPass4 {
    private var s1: Biquad
    private var s2: Biquad

    init(fs: Double, cutoffHz: Double) {
        // 4th-order Butterworth pole Qs.
        s1 = Biquad(highpassFs: fs, cutoffHz: cutoffHz, q: 0.54119610)
        s2 = Biquad(highpassFs: fs, cutoffHz: cutoffHz, q: 1.30656296)
    }

    mutating func process(_ x: Double) -> Double { s2.process(s1.process(x)) }
}

/// Single biquad (RBJ cookbook high-pass), Direct-Form-II transposed.
struct Biquad {
    private let b0, b1, b2, a1, a2: Double
    private var z1 = 0.0, z2 = 0.0

    init(highpassFs fs: Double, cutoffHz: Double, q: Double) {
        let w0 = 2 * Double.pi * cutoffHz / fs
        let cosw0 = cos(w0), sinw0 = sin(w0)
        let alpha = sinw0 / (2 * q)
        let a0 = 1 + alpha
        b0 = ((1 + cosw0) / 2) / a0
        b1 = (-(1 + cosw0)) / a0
        b2 = ((1 + cosw0) / 2) / a0
        a1 = (-2 * cosw0) / a0
        a2 = (1 - alpha) / a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + z1
        z1 = b1 * x - a1 * y + z2
        z2 = b2 * x - a2 * y
        return y
    }
}
