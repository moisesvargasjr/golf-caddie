import XCTest
@testable import GolfCaddie

final class ShotReconcilerTests: XCTestCase {
    private struct Candidate: TimedCandidate, Equatable {
        let tag: String
        let candidateTime: Date
    }

    /// Step source driven by an explicit list of (intervalStart → steps). For
    /// each query it returns the steps registered at the matching `from` time;
    /// defaults to 0 (stood still) when unspecified.
    private struct FakeSteps: StepCounting {
        let stepsAtFrom: [Date: Int]
        func steps(from: Date, to: Date) async -> Int { stepsAtFrom[from] ?? 0 }
    }

    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)
    private func at(_ s: TimeInterval) -> Date { t0.addingTimeInterval(s) }

    func testPracticeThenShotCollapsesToLast() async {
        // Two practice swings then the real shot, ~2 s apart, no steps.
        let buf = [Candidate(tag: "practice1", candidateTime: at(0)),
                   Candidate(tag: "practice2", candidateTime: at(2)),
                   Candidate(tag: "shot", candidateTime: at(4))]
        let r = ShotReconciler(steps: FakeSteps(stepsAtFrom: [:]))
        let out = await r.commit(buf)
        XCTAssertEqual(out.map(\.tag), ["shot"]) // collapsed to the last = the real shot
    }

    func testTwoRealShotsWithStepsBetweenStayDistinct() async {
        let buf = [Candidate(tag: "shotA", candidateTime: at(0)),
                   Candidate(tag: "shotB", candidateTime: at(40))]
        // Walked ~50 steps between them.
        let r = ShotReconciler(steps: FakeSteps(stepsAtFrom: [at(0): 50]))
        let out = await r.commit(buf)
        XCTAssertEqual(out.map(\.tag), ["shotA", "shotB"])
    }

    func testDuffedShortShotStaysDistinct() async {
        // Duff goes 3 ft; you take a single step to it and hit again.
        let buf = [Candidate(tag: "duff", candidateTime: at(0)),
                   Candidate(tag: "recovery", candidateTime: at(5))]
        let r = ShotReconciler(steps: FakeSteps(stepsAtFrom: [at(0): 1]))
        let out = await r.commit(buf)
        XCTAssertEqual(out.map(\.tag), ["duff", "recovery"]) // 1 step = boundary, stroke preserved
    }

    func testLoneShotPassesThrough() async {
        let buf = [Candidate(tag: "shot", candidateTime: at(0))]
        let r = ShotReconciler(steps: FakeSteps(stepsAtFrom: [:]))
        let out = await r.commit(buf)
        XCTAssertEqual(out.map(\.tag), ["shot"])
    }

    func testLongTimeGapIsBoundaryEvenWithoutSteps() async {
        // Two impacts >clusterMaxGap apart with no steps — not the same address
        // event; keep both rather than silently merge.
        let buf = [Candidate(tag: "a", candidateTime: at(0)),
                   Candidate(tag: "b", candidateTime: at(20))]
        let r = ShotReconciler(steps: FakeSteps(stepsAtFrom: [:]))
        let out = await r.commit(buf)
        XCTAssertEqual(out.map(\.tag), ["a", "b"])
    }

    func testRehitWithZeroStepsUndercounts_pinnedLimitation() async {
        // The one unsolvable corner: ball ends at your feet, you re-hit without
        // stepping. The step-gate cannot distinguish this from a practice swing,
        // so it collapses to one. Pinned here so the limitation is explicit and
        // a future fix (e.g. impact-spacing heuristic) has a failing-intent test.
        let buf = [Candidate(tag: "realShot1", candidateTime: at(0)),
                   Candidate(tag: "realShot2_rehit", candidateTime: at(3))]
        let r = ShotReconciler(steps: FakeSteps(stepsAtFrom: [:]))
        let out = await r.commit(buf)
        XCTAssertEqual(out.map(\.tag), ["realShot2_rehit"]) // documents the under-count
    }

    func testMixedClustersInOneBuffer() async {
        // practice+shot (0 steps) | walk | practice+shot (0 steps)
        let buf = [Candidate(tag: "p1", candidateTime: at(0)),
                   Candidate(tag: "shot1", candidateTime: at(2)),
                   Candidate(tag: "p2", candidateTime: at(60)),
                   Candidate(tag: "shot2", candidateTime: at(62))]
        let r = ShotReconciler(steps: FakeSteps(stepsAtFrom: [at(2): 40])) // walked between the two clusters
        let out = await r.commit(buf)
        XCTAssertEqual(out.map(\.tag), ["shot1", "shot2"])
    }
}
