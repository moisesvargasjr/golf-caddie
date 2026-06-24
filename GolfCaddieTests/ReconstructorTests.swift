import CoreLocation
import XCTest
@testable import GolfCaddie

/// B7 Path-A reconstruction core — pure classification / confidence / reconciliation.
/// Locations are assumed already supplied by the live fuse(); these tests cover the
/// hole-out layer the confirmation card renders.
final class ReconstructorTests: XCTestCase {
    // Green anchor + offsets (1° lat ≈ 111_320 m).
    let green = CLLocationCoordinate2D(latitude: 33.2132, longitude: -117.3327)
    func offsetNorth(_ meters: Double) -> (Double, Double) {
        (green.latitude + meters / 111_320.0, green.longitude)
    }
    let cfg = ReconstructionConfig() // explicit defaults: green 25 m, good 6 m, poor 25 m

    private func shot(_ seq: Int, lat: Double? = nil, lng: Double? = nil,
                      acc: Double? = nil, club: ClubID? = nil,
                      source: ShotSource = .watchAuto) -> Shot {
        Shot(id: UUID(), holeID: UUID(), sequenceNumber: seq, timestamp: Date(),
             latitude: lat, longitude: lng, gpsAccuracy: acc, hadGPS: lat != nil,
             club: club, source: source, notes: nil)
    }

    // MARK: - Putt classification

    func testPutterIsAlwaysPuttEvenFarFromGreen() {
        let (la, lo) = offsetNorth(200) // 200 m away, but it's a putter
        XCTAssertTrue(Reconstructor.isPutt(shot(1, lat: la, lng: lo, acc: 5, club: .putter),
                                           green: green, config: cfg))
    }

    func testStrokeStruckFromGreenIsPutt() {
        let (la, lo) = offsetNorth(10) // within 25 m
        XCTAssertTrue(Reconstructor.isPutt(shot(1, lat: la, lng: lo, acc: 5, club: .sevenIron),
                                           green: green, config: cfg))
    }

    func testStrokeOffGreenIsFullShot() {
        let (la, lo) = offsetNorth(150)
        XCTAssertFalse(Reconstructor.isPutt(shot(1, lat: la, lng: lo, acc: 5, club: .sevenIron),
                                            green: green, config: cfg))
    }

    func testNoGPSNonPutterStaysFullShot() {
        XCTAssertFalse(Reconstructor.isPutt(shot(1, club: .sevenIron), green: green, config: cfg))
    }

    // MARK: - Confidence

    func testConfidenceScalesWithAccuracy() {
        let (la, lo) = offsetNorth(150) // a full shot
        func conf(_ acc: Double?) -> Double {
            let s = shot(1, lat: la, lng: lo, acc: acc, club: .sevenIron)
            return Reconstructor.confidence(for: s, isPutt: false, config: cfg)
        }
        XCTAssertEqual(conf(6), 1.0, accuracy: 0.001)    // tight fix → full trust
        XCTAssertEqual(conf(25), 0.3, accuracy: 0.001)   // loose fix → floor
        XCTAssertEqual(conf(15.5), 0.65, accuracy: 0.01) // halfway → linear
    }

    func testNoGPSFullShotIsLowConfidence() {
        let s = shot(1, club: .sevenIron) // hadGPS == false
        XCTAssertEqual(Reconstructor.confidence(for: s, isPutt: false, config: cfg), 0.2, accuracy: 0.001)
    }

    func testPuttsAreAlwaysConfident() {
        let s = shot(1, club: .putter)
        XCTAssertEqual(Reconstructor.confidence(for: s, isPutt: true, config: cfg), 1.0, accuracy: 0.001)
    }

    // MARK: - Whole-hole reconstruct + reconciliation

    /// A par-3-shaped hole: 2 full shots reaching the green, then 3 putts.
    private func twoFullThreePutts() -> [Shot] {
        let (fa, fo) = offsetNorth(150)
        let (ga, go) = offsetNorth(8)
        return [
            shot(1, lat: fa, lng: fo, acc: 7, club: .sevenIron),  // tee shot (full)
            shot(2, lat: fa, lng: fo, acc: 9, club: .pitchingWedge), // approach (full)
            shot(3, lat: ga, lng: go, acc: 6, club: .putter),     // putt
            shot(4, lat: ga, lng: go, acc: 6, club: .putter),     // putt
            shot(5, lat: ga, lng: go, acc: 6, club: .putter),     // putt
        ]
    }

    func testSplitCountsAndOrder() {
        let r = Reconstructor.reconstruct(shots: twoFullThreePutts(), green: green,
                                          enteredScore: 5, config: cfg)
        XCTAssertEqual(r.shots.count, 5)
        XCTAssertEqual(r.fullShotCount, 2)
        XCTAssertEqual(r.puttCount, 3)
        XCTAssertEqual(r.shots.map { $0.shot.sequenceNumber }, [1, 2, 3, 4, 5])
    }

    func testReconciliationMatchesFewerMore() {
        let shots = twoFullThreePutts()
        XCTAssertEqual(Reconstructor.reconstruct(shots: shots, green: green, enteredScore: 5, config: cfg).reconciliation, .matches)
        XCTAssertEqual(Reconstructor.reconstruct(shots: shots, green: green, enteredScore: 6, config: cfg).reconciliation, .detectedFewer(by: 1))
        XCTAssertEqual(Reconstructor.reconstruct(shots: shots, green: green, enteredScore: 4, config: cfg).reconciliation, .detectedMore(by: 1))
        XCTAssertEqual(Reconstructor.reconstruct(shots: shots, green: green, enteredScore: nil, config: cfg).reconciliation, .noScore)
    }

    func testAppliedWritesBackClassification() {
        let r = Reconstructor.reconstruct(shots: twoFullThreePutts(), green: green, enteredScore: 5, config: cfg)
        let putt = r.shots[2]
        XCTAssertTrue(putt.applied.isPutt)
        XCTAssertEqual(putt.applied.confidence, 1.0)
        // Full shots carry their computed confidence through to the persisted shot.
        XCTAssertEqual(r.shots[0].applied.confidence, r.shots[0].confidence)
    }

    func testNoGreenAnchorLeavesNonPuttersAsFull() {
        // Without a green anchor, only the putter rule classifies putts.
        let r = Reconstructor.reconstruct(shots: twoFullThreePutts(), green: nil, enteredScore: 5, config: cfg)
        XCTAssertEqual(r.puttCount, 3)      // the 3 putters still classify
        XCTAssertEqual(r.fullShotCount, 2)
    }
}
