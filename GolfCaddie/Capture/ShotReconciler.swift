import CoreMotion
import Foundation

/// Step source for the reconciler. Abstracted so the grouping logic unit-tests
/// with synthetic step counts (no device).
protocol StepCounting {
    /// Steps the player took in `[from, to]`. Implementations that cannot
    /// answer (pedometer unavailable/errored) MUST return a large value so the
    /// reconciler treats the interval as "walked" and never silently collapses
    /// two real strokes — false positives are flickable, lost strokes are not.
    func steps(from: Date, to: Date) async -> Int
}

/// A candidate the reconciler can order in time. The concrete payload (the
/// fused SwingEvent + coordinate) rides along untouched.
protocol TimedCandidate {
    var candidateTime: Date { get }
}

/// Collapses a burst of consecutive auto-detections to the real shots, using a
/// step-gate: practice swings and the real strike happen at the SAME address
/// position (zero steps between), so they collapse to the LAST detection (the
/// real shot — correct count AND correct takeoff location). Two genuinely
/// distinct shots are separated by walking to the next ball (even a duffed
/// 3-footer costs a step), so a step between detections is a cluster boundary.
///
/// The one unsolvable corner — re-hitting a ball at your feet with zero steps —
/// under-counts; that stays a manual correction (asserted in the tests so the
/// limitation is pinned, not forgotten).
///
/// Pure grouping only. The debounce timing (waiting a few seconds for a possible
/// successor before committing) lives in the integration layer (LiveShotCoordinator).
struct ShotReconciler {
    var stepThreshold: Int = 1
    var clusterMaxGap: TimeInterval = 8.0
    let steps: StepCounting

    /// Given a time-ordered buffer of candidates, return the committed shots —
    /// the last candidate of each step-gated cluster.
    func commit<T: TimedCandidate>(_ buffer: [T]) async -> [T] {
        guard buffer.count > 1 else { return buffer }
        var committed: [T] = []
        for i in 1..<buffer.count {
            let gap = buffer[i].candidateTime.timeIntervalSince(buffer[i - 1].candidateTime)
            let walked = await steps.steps(from: buffer[i - 1].candidateTime, to: buffer[i].candidateTime)
            let isBoundary = walked >= stepThreshold || gap >= clusterMaxGap
            if isBoundary {
                committed.append(buffer[i - 1]) // last of the cluster that just closed
            }
        }
        committed.append(buffer[buffer.count - 1]) // last of the final cluster
        return committed
    }
}

/// CMPedometer-backed step source (phone in pocket counts the player's steps).
/// Fails safe: any unavailability/error → Int.max so nothing collapses.
final class PedometerStepCounter: StepCounting {
    private let pedometer = CMPedometer()

    func steps(from: Date, to: Date) async -> Int {
        guard CMPedometer.isStepCountingAvailable(), to > from else { return Int.max }
        return await withCheckedContinuation { continuation in
            pedometer.queryPedometerData(from: from, to: to) { data, error in
                if let data, error == nil {
                    continuation.resume(returning: data.numberOfSteps.intValue)
                } else {
                    continuation.resume(returning: Int.max) // fail safe: treat as walked
                }
            }
        }
    }
}
