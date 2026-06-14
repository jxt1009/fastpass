import XCTest
@testable import FastTrack

final class SpeedFusion100HzTests: XCTestCase {
    func test_dampingCoefficients_preservesPerSecondBehavior() {
        let t = SpeedFusion()
        for _ in 0..<100 { t.predict(longAccelG: 0.5, dt: 1.0 / 100.0) }
        let speedAfter100Hz = t.speed

        let s = SpeedFusion()
        for _ in 0..<25 { s.predict(longAccelG: 0.5, dt: 1.0 / 25.0) }
        let speedAfter25Hz = s.speed

        XCTAssertEqual(speedAfter100Hz, speedAfter25Hz, accuracy: 0.01,
                       "damping over 1 simulated second should be similar at 100 Hz and 25 Hz")
    }
}
