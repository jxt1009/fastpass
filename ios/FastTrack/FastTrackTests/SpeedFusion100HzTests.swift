import XCTest
@testable import FastTrack

final class SpeedFusion100HzTests: XCTestCase {
    func test_dampingCoefficients_preservesPerSecondDecay() {
        XCTAssertEqual(pow(SpeedFusion.lowSpeedDampingCoefficient_100Hz, 100),
                       pow(SpeedFusion.lowSpeedDampingCoefficient_25Hz, 25),
                       accuracy: 0.0005,
                       "per-second non-active damping should match")
        XCTAssertEqual(pow(SpeedFusion.lowSpeedDampingCoefficientActive_100Hz, 100),
                       pow(SpeedFusion.lowSpeedDampingCoefficientActive_25Hz, 25),
                       accuracy: 0.0005,
                       "per-second active damping should match")
    }
}
