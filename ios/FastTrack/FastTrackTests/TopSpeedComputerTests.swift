import XCTest
@testable import FastTrack

final class TopSpeedComputerTests: XCTestCase {
    func test_rejectsIMUSpike_preservesRealPeak() {
        var stream: [(TimeInterval, Double, Bool, Double)] = []
        for i in 0..<100 {
            stream.append((Double(i) * 0.01, Double(i) * 0.3, false, 0.0))
        }
        for i in 100..<400 {
            let speed: Double = (i == 250) ? 80.0 : 30.0
            stream.append((Double(i) * 0.01, speed, false, 0.0))
        }
        for i in 400..<500 {
            let speed = 30.0 - Double(i - 400) * 0.3
            stream.append((Double(i) * 0.01, max(0, speed), false, 0.0))
        }
        let result = TopSpeedComputer.compute(
            speedStream: stream,
            gpsMaxSpeed: 28.0,
            nearestGpsAccuracyMeters: 30.0
        )
        XCTAssertEqual(result.fusedMaxSpeed, 30.0, accuracy: 0.5)
        XCTAssertEqual(result.gpsMaxSpeed, 28.0, accuracy: 0.001)
        XCTAssertEqual(result.maxSpeed, 30.0, accuracy: 1.0)
    }

    func test_fallsBackToFused_whenGpsInaccurate() {
        let stream: [(TimeInterval, Double, Bool, Double)] = (0..<100).map { i in
            (Double(i) * 0.01, 20.0, false, 0.0)
        }
        let result = TopSpeedComputer.compute(
            speedStream: stream,
            gpsMaxSpeed: 5.0,
            nearestGpsAccuracyMeters: 200.0
        )
        XCTAssertEqual(result.maxSpeed, 20.0, accuracy: 0.5)
    }
}
