import XCTest
@testable import FastTrack

final class SpeedFusionConcurrencyTests: XCTestCase {

    /// Smoke test: concurrent predict + update must not corrupt Kalman state.
    /// The actor serializes all access, so interleaved read-modify-write on
    /// `P` and `speed` cannot race; this test catches gross corruption if the
    /// actor isolation were ever regressed.
    func testConcurrentPredictAndUpdate_speedRemainsValid() async {
        let fusion = SpeedFusion()

        await withTaskGroup(of: Void.self) { group in
            // 200 concurrent predicts (simulating 100 Hz IMU bursts)
            for _ in 0..<200 {
                group.addTask { await fusion.predict(longAccelG: 0.5, dt: 0.01) }
            }
            // 20 concurrent updates (simulating ~1 Hz GPS)
            for i in 0..<20 {
                group.addTask { await fusion.update(gpsSpeed: Double(i) * 0.5, gpsSpeedAccuracy: 0.5) }
            }
        }

        let speed = await fusion.speed
        XCTAssertGreaterThanOrEqual(speed, 0,
            "Speed must be non-negative after concurrent access")
        XCTAssertFalse(speed.isNaN || speed.isInfinite,
            "Speed must be finite after concurrent access")
    }

    /// Sequential predict + update should produce a stable, repeatable result.
    /// The actor serializes calls deterministically, so the same sequence must
    /// always yield the same fused speed.
    func testSequentialPredictAndUpdate_stableResult() async {
        let fusion = SpeedFusion()
        for _ in 0..<100 {
            await fusion.predict(longAccelG: 0.3, dt: 0.01)
        }
        await fusion.update(gpsSpeed: 5.0, gpsSpeedAccuracy: 0.5)
        let speed1 = await fusion.speed

        let fusion2 = SpeedFusion()
        for _ in 0..<100 {
            await fusion2.predict(longAccelG: 0.3, dt: 0.01)
        }
        await fusion2.update(gpsSpeed: 5.0, gpsSpeedAccuracy: 0.5)
        let speed2 = await fusion2.speed

        XCTAssertEqual(speed1, speed2, accuracy: 0.001,
            "Same sequential operations must produce the same result")
    }
}
