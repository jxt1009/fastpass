import XCTest
@testable import FastTrack

final class SpeedFusionConcurrencyTests: XCTestCase {

    /// Smoke test: concurrent predict + update must not corrupt Kalman state.
    /// Without the lock, interleaved read-modify-write on `P` and `speed`
    /// can produce NaN or negative values. The definitive verification is
    /// TSan (deferred to R2); this test catches gross corruption.
    func testConcurrentPredictAndUpdate_speedRemainsValid() {
        let fusion = SpeedFusion()
        let group = DispatchGroup()

        // 200 concurrent predicts (simulating 100 Hz IMU bursts)
        for _ in 0..<200 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                fusion.predict(longAccelG: 0.5, dt: 0.01)
                group.leave()
            }
        }

        // 20 concurrent updates (simulating ~1 Hz GPS)
        for i in 0..<20 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                fusion.update(gpsSpeed: Double(i) * 0.5, gpsSpeedAccuracy: 0.5)
                group.leave()
            }
        }

        group.wait()

        XCTAssertGreaterThanOrEqual(fusion.speed, 0,
            "Speed must be non-negative after concurrent access")
        XCTAssertFalse(fusion.speed.isNaN || fusion.speed.isInfinite,
            "Speed must be finite after concurrent access")
    }

    /// Sequential predict + update should produce a stable, repeatable result.
    /// This verifies the lock doesn't change single-threaded behavior.
    func testSequentialPredictAndUpdate_stableResult() {
        let fusion = SpeedFusion()
        for _ in 0..<100 {
            fusion.predict(longAccelG: 0.3, dt: 0.01)
        }
        fusion.update(gpsSpeed: 5.0, gpsSpeedAccuracy: 0.5)

        let speed1 = fusion.speed

        let fusion2 = SpeedFusion()
        for _ in 0..<100 {
            fusion2.predict(longAccelG: 0.3, dt: 0.01)
        }
        fusion2.update(gpsSpeed: 5.0, gpsSpeedAccuracy: 0.5)

        XCTAssertEqual(speed1, fusion2.speed, accuracy: 0.001,
            "Same sequential operations must produce the same result")
    }
}
