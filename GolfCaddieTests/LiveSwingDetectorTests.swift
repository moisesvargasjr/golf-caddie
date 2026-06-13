import XCTest
@testable import GolfCaddie

final class LiveSwingDetectorTests: XCTestCase {
    // Fixture lives next to this source file (carved from the validated 56-min
    // range session; reference detections produced by scripts/swing_spike/detect.py).
    private var fixturesDir: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
    }

    private struct Vec { let t, x, y, z: Double }

    private func loadVecBin(_ name: String) throws -> [Vec] {
        let data = try Data(contentsOf: fixturesDir.appendingPathComponent(name))
        let stride = 20 // f8 t + 3×f4
        return data.withUnsafeBytes { raw in
            (0..<(data.count / stride)).map { i in
                let b = i * stride
                return Vec(
                    t: raw.loadUnaligned(fromByteOffset: b, as: Double.self),
                    x: Double(raw.loadUnaligned(fromByteOffset: b + 8, as: Float.self)),
                    y: Double(raw.loadUnaligned(fromByteOffset: b + 12, as: Float.self)),
                    z: Double(raw.loadUnaligned(fromByteOffset: b + 16, as: Float.self))
                )
            }
        }
    }

    /// Merge the two time-sorted streams and drive the detector in timestamp order.
    private func run(_ detector: LiveSwingDetector, accel: [Vec], gyro: [Vec]) -> [LiveSwingDetector.Detection] {
        var out: [LiveSwingDetector.Detection] = []
        detector.onDetection = { out.append($0) }
        var i = 0, j = 0
        while i < accel.count || j < gyro.count {
            let useAccel = j >= gyro.count || (i < accel.count && accel[i].t <= gyro[j].t)
            if useAccel {
                let a = accel[i]; i += 1
                detector.ingestAccel(t: a.t, x: a.x, y: a.y, z: a.z)
            } else {
                let g = gyro[j]; j += 1
                detector.ingestGyro(t: g.t, x: g.x, y: g.y, z: g.z)
            }
        }
        return out
    }

    func testParityWithOfflineDetectorOnRealSession() throws {
        let accel = try loadVecBin("parity_accel.bin")
        let gyro = try loadVecBin("parity_gyro.bin")
        let refData = try Data(contentsOf: fixturesDir.appendingPathComponent("parity_reference.json"))
        let ref = try JSONSerialization.jsonObject(with: refData) as! [String: Any]
        let refDets = (ref["reference_detections"] as! [[String: Any]]).map { $0["t"] as! Double }

        let dets = run(LiveSwingDetector(), accel: accel, gyro: gyro)

        // Same count as detect.py (the window holds 5 real full shots).
        XCTAssertEqual(dets.count, refDets.count, "detected \(dets.map { round2($0.t) }) vs ref \(refDets)")
        // Each detection aligns with a reference impact within 0.15 s.
        for r in refDets {
            XCTAssertTrue(dets.contains { abs($0.t - r) < 0.15 }, "no live detection near ref \(r)")
        }
    }

    // MARK: - Deterministic synthetic cases (no fixture dependency)

    /// Build a synthetic stream: a swing arc (gyro hump) optionally followed by
    /// a high-frequency impact burst on accel.
    private func synth(arcPeak: Double, impactG: Double, at center: Double = 5.0,
                       fs: Double = 100, dur: Double = 10) -> (accel: [Vec], gyro: [Vec]) {
        var accel: [Vec] = [], gyro: [Vec] = []
        let n = Int(dur * fs)
        for k in 0..<n {
            let t = Double(k) / fs
            let env = exp(-0.5 * pow((t - center) / 0.15, 2))
            // impact: ~30 ms alternating-sign burst just after the arc peak
            var ax = 0.0
            if impactG > 0 {
                let burst = exp(-0.5 * pow((t - (center + 0.02)) / 0.012, 2))
                ax = burst * (k % 2 == 0 ? 1.0 : -1.0) * impactG
            }
            accel.append(Vec(t: t, x: ax, y: 0, z: 0))
            gyro.append(Vec(t: t, x: env * arcPeak, y: 0, z: 0))
        }
        return (accel, gyro)
    }

    func testFullShotFires() {
        let s = synth(arcPeak: 24, impactG: 12)
        XCTAssertEqual(run(LiveSwingDetector(), accel: s.accel, gyro: s.gyro).count, 1)
    }

    func testChipFires() {
        let s = synth(arcPeak: 10, impactG: 8)
        XCTAssertEqual(run(LiveSwingDetector(), accel: s.accel, gyro: s.gyro).count, 1)
    }

    func testPracticeSwingNoImpactDoesNotFire() {
        // Big arc, no ball contact → no impact transient → must not fire.
        let s = synth(arcPeak: 22, impactG: 0)
        XCTAssertEqual(run(LiveSwingDetector(), accel: s.accel, gyro: s.gyro).count, 0)
    }

    func testImpactWithoutArcDoesNotFire() {
        // A tap/bag-drop: impact but no swing arc → gated out.
        let s = synth(arcPeak: 1.5, impactG: 12)
        XCTAssertEqual(run(LiveSwingDetector(), accel: s.accel, gyro: s.gyro).count, 0)
    }

    private func round2(_ x: Double) -> Double { (x * 100).rounded() / 100 }
}
