import XCTest
@testable import FastTrack

final class SpeedFusionActorTests: XCTestCase {

    func test_predictAndReadReturnsUpdatedSpeed() async {
        let fusion = SpeedFusion()
        let snapshot = await fusion.predictAndRead(longAccelG: 0.5, dt: 0.01)
        XCTAssertGreaterThan(snapshot.speed, 0, "Speed should increase with forward acceleration")
    }

    func test_updateAndReadConvergesToGPSSpeed() async {
        let fusion = SpeedFusion()
        for _ in 0..<10 {
            _ = await fusion.updateAndRead(gpsSpeed: 15, gpsSpeedAccuracy: 0.5)
        }
        let snapshot = await fusion.currentSnapshot()
        XCTAssertEqual(snapshot.speed, 15, accuracy: 1.0, "Fused speed should converge to GPS speed")
    }

    func test_zeroLockEngages() async {
        let fusion = SpeedFusion()
        _ = await fusion.updateAndRead(gpsSpeed: 0, gpsSpeedAccuracy: 0.5)
        let snapshot = await fusion.currentSnapshot()
        XCTAssertTrue(snapshot.isZeroLocked, "Zero lock should engage at 0 speed with good accuracy")
    }

    func test_gpsContextStored() async {
        let fusion = SpeedFusion()
        await fusion.updateGPSContext(speed: 12.5, accuracy: 0.8)
        let ctx = await fusion.gpsContext()
        XCTAssertEqual(ctx.speed, 12.5)
        XCTAssertEqual(ctx.accuracy, 0.8)
    }

    func test_resetClearsState() async {
        let fusion = SpeedFusion()
        _ = await fusion.predictAndRead(longAccelG: 0.5, dt: 0.01)
        await fusion.reset()
        let snapshot = await fusion.currentSnapshot()
        XCTAssertEqual(snapshot.speed, 0)
        XCTAssertFalse(snapshot.isZeroLocked)
    }

    func test_concurrentAccessIsSafe() async {
        let fusion = SpeedFusion()
        async let p1: SpeedFusionSnapshot = fusion.predictAndRead(longAccelG: 0.3, dt: 0.01)
        async let p2: SpeedFusionSnapshot = fusion.predictAndRead(longAccelG: 0.4, dt: 0.01)
        async let u1: SpeedFusionSnapshot = fusion.updateAndRead(gpsSpeed: 10, gpsSpeedAccuracy: 0.5)
        async let s1: SpeedFusionSnapshot = fusion.currentSnapshot()
        _ = await (p1, p2, u1, s1)
        let final = await fusion.currentSnapshot()
        XCTAssertGreaterThanOrEqual(final.speed, 0)
    }

    func test_snapshotIsSendable() {
        let snap = SpeedFusionSnapshot(speed: 5, isZeroLocked: false, stationaryConfidence: 0.2)
        XCTAssertEqual(snap.speed, 5)
        XCTAssertEqual(snap.isZeroLocked, false)
        XCTAssertEqual(snap.stationaryConfidence, 0.2)
    }
}
