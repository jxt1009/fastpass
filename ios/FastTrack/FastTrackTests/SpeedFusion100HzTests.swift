import XCTest
@testable import FastTrack

final class SpeedFusion100HzTests: XCTestCase {
    func test_dampingCoefficients_preservesPerSecondBehavior() {
        var t = SpeedFusion()
        for _ in 0..<100 { t.predict(longAccelG: 0.5, dt: 1.0/100.0) }
        XCTAssertTrue(SpeedFusion.lowSpeedDampingCoefficient_100Hz > 0.9)
        XCTAssertTrue(SpeedFusion.lowSpeedDampingCoefficient_100Hz < 0.95)
    }
}
