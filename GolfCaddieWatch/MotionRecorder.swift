import CoreMotion
import Foundation

/// Single 100 Hz motion-acquisition path. Always taps live samples to the
/// `onAccel`/`onGyro` callbacks (feeding the live swing detector); ALSO writes
/// the raw binary files when started with a directory (validation mode, for
/// continued ground-truth FP/FN measurement). One CMMotionManager — two would
/// double battery.
///
/// Raw accel is the impact channel; gyro is the arc channel. On watchOS the raw
/// gyro is unavailable, so gyro comes from fused deviceMotion rotationRate.
///
/// Binary record layouts (validation mode) mirror `spikelib.py`:
///   dm.bin    t:f8, userAccel xyz:f4, rotationRate xyz:f4, gravity xyz:f4, quat wxyz:f4
///   accel.bin t:f8, xyz:f4
///   gyro.bin  t:f8, xyz:f4
final class MotionRecorder {
    struct Counts {
        var dm = 0
        var accel = 0
        var gyro = 0
    }

    enum RecorderError: LocalizedError {
        case sensorUnavailable(String)
        var errorDescription: String? {
            if case .sensorUnavailable(let name) = self { return "\(name) unavailable" }
            return nil
        }
    }

    /// Live sample taps — fire on the motion queue. (timestamp, x, y, z).
    var onAccel: ((TimeInterval, Double, Double, Double) -> Void)?
    var onGyro: ((TimeInterval, Double, Double, Double) -> Void)?

    private let manager = CMMotionManager()
    private let queue: OperationQueue = {
        let q = OperationQueue()
        q.maxConcurrentOperationCount = 1 // serializes handlers; no locking needed
        q.name = "golfcaddie.motion"
        return q
    }()

    // Touched only on `queue` (or after waitUntilAllOperationsAreFinished).
    private var dmFile: FileHandle?
    private var accelFile: FileHandle?
    private var gyroFile: FileHandle?
    private var dmBuf = Data()
    private var accelBuf = Data()
    private var gyroBuf = Data()
    private var counts = Counts()
    private var recentDMTimes: [TimeInterval] = []
    private var recording = false

    /// Delivered deviceMotion rate, reported on the main queue every ~100 samples.
    var onRateSample: (@MainActor (Double) -> Void)?

    /// "raw" when gyro comes from CMGyroData; "deviceMotion" when watchOS hides
    /// the raw gyro and we fall back to the fused rotationRate.
    private(set) var gyroSource = "raw"

    private static let flushEvery = 256

    /// Start streaming. Pass a directory to also write raw binary files
    /// (validation mode); pass nil for live-detection-only (production).
    func start(recordRawTo directory: URL?) throws {
        guard manager.isDeviceMotionAvailable else { throw RecorderError.sensorUnavailable("Device motion") }
        guard manager.isAccelerometerAvailable else { throw RecorderError.sensorUnavailable("Accelerometer") }
        let hasRawGyro = manager.isGyroAvailable
        gyroSource = hasRawGyro ? "raw" : "deviceMotion"
        recording = directory != nil
        if let directory {
            dmFile = try Self.makeFile(directory.appendingPathComponent("dm.bin"))
            accelFile = try Self.makeFile(directory.appendingPathComponent("accel.bin"))
            gyroFile = try Self.makeFile(directory.appendingPathComponent("gyro.bin"))
        }

        manager.deviceMotionUpdateInterval = 0.01
        manager.accelerometerUpdateInterval = 0.01
        manager.gyroUpdateInterval = 0.01

        manager.startDeviceMotionUpdates(to: queue) { [weak self] dm, _ in
            guard let self, let dm else { return }
            if recording {
                dmBuf.appendLE(dm.timestamp)
                dmBuf.appendLE(Float(dm.userAcceleration.x))
                dmBuf.appendLE(Float(dm.userAcceleration.y))
                dmBuf.appendLE(Float(dm.userAcceleration.z))
                dmBuf.appendLE(Float(dm.rotationRate.x))
                dmBuf.appendLE(Float(dm.rotationRate.y))
                dmBuf.appendLE(Float(dm.rotationRate.z))
                dmBuf.appendLE(Float(dm.gravity.x))
                dmBuf.appendLE(Float(dm.gravity.y))
                dmBuf.appendLE(Float(dm.gravity.z))
                dmBuf.appendLE(Float(dm.attitude.quaternion.w))
                dmBuf.appendLE(Float(dm.attitude.quaternion.x))
                dmBuf.appendLE(Float(dm.attitude.quaternion.y))
                dmBuf.appendLE(Float(dm.attitude.quaternion.z))
                counts.dm += 1
                if counts.dm % Self.flushEvery == 0 {
                    dmFile?.write(dmBuf)
                    dmBuf.removeAll(keepingCapacity: true)
                }
            }
            if !hasRawGyro {
                onGyro?(dm.timestamp, dm.rotationRate.x, dm.rotationRate.y, dm.rotationRate.z)
                if recording {
                    appendVec(t: dm.timestamp, dm.rotationRate.x, dm.rotationRate.y, dm.rotationRate.z,
                              buf: &gyroBuf, file: gyroFile, count: &counts.gyro)
                }
            }
            trackRate(dm.timestamp)
        }
        manager.startAccelerometerUpdates(to: queue) { [weak self] data, _ in
            guard let self, let data else { return }
            onAccel?(data.timestamp, data.acceleration.x, data.acceleration.y, data.acceleration.z)
            if recording {
                appendVec(t: data.timestamp, data.acceleration.x, data.acceleration.y, data.acceleration.z,
                          buf: &accelBuf, file: accelFile, count: &counts.accel)
            }
        }
        if hasRawGyro {
            manager.startGyroUpdates(to: queue) { [weak self] data, _ in
                guard let self, let data else { return }
                onGyro?(data.timestamp, data.rotationRate.x, data.rotationRate.y, data.rotationRate.z)
                if recording {
                    appendVec(t: data.timestamp, data.rotationRate.x, data.rotationRate.y, data.rotationRate.z,
                              buf: &gyroBuf, file: gyroFile, count: &counts.gyro)
                }
            }
        }
    }

    /// Stops streams, flushes and closes any files. Returns final counts.
    @discardableResult
    func stop() -> Counts {
        manager.stopDeviceMotionUpdates()
        manager.stopAccelerometerUpdates()
        manager.stopGyroUpdates()
        queue.addOperation { [self] in
            if recording {
                dmFile?.write(dmBuf)
                accelFile?.write(accelBuf)
                gyroFile?.write(gyroBuf)
                for f in [dmFile, accelFile, gyroFile] { try? f?.close() }
            }
            dmBuf.removeAll()
            accelBuf.removeAll()
            gyroBuf.removeAll()
            dmFile = nil
            accelFile = nil
            gyroFile = nil
        }
        queue.waitUntilAllOperationsAreFinished()
        return counts
    }

    private func appendVec(t: TimeInterval, _ x: Double, _ y: Double, _ z: Double,
                           buf: inout Data, file: FileHandle?, count: inout Int) {
        buf.appendLE(t)
        buf.appendLE(Float(x))
        buf.appendLE(Float(y))
        buf.appendLE(Float(z))
        count += 1
        if count % Self.flushEvery == 0 {
            file?.write(buf)
            buf.removeAll(keepingCapacity: true)
        }
    }

    private func trackRate(_ t: TimeInterval) {
        recentDMTimes.append(t)
        guard recentDMTimes.count >= 100 else { return }
        let span = recentDMTimes.last! - recentDMTimes.first!
        let hz = span > 0 ? Double(recentDMTimes.count - 1) / span : 0
        recentDMTimes.removeAll(keepingCapacity: true)
        if let onRateSample {
            DispatchQueue.main.async { onRateSample(hz) }
        }
    }

    private static func makeFile(_ url: URL) throws -> FileHandle {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        return try FileHandle(forWritingTo: url)
    }
}

private extension Data {
    mutating func appendLE(_ value: Double) {
        var bits = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &bits) { append(contentsOf: $0) }
    }

    mutating func appendLE(_ value: Float) {
        var bits = value.bitPattern.littleEndian
        Swift.withUnsafeBytes(of: &bits) { append(contentsOf: $0) }
    }
}
