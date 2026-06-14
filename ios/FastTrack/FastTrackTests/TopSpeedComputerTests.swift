import XCTest
@testable import FastTrack

final class TopSpeedComputerTests: XCTestCase {
    func test_rejectsIMUSpike_preservesRealPeak() {
        var stream: [(TimeInterval, Double, Bool, Double)] = []
        for i in 0..<500 {
            let speed: Double
            if i == 250 { speed = 80.0 }
            else if i > 100 && i < 300 { speed = 30.0 }
            else { speed = Double(i) * 0.1 }
            stream.append((Double(i) * 0.01, speed, false, 0.0))
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
            (Double(i) * 0.01, Double(i) * 0.2, false, 0.0)
        }
        let result = TopSpeedComputer.compute(
            speedStream: stream,
            gpsMaxSpeed: 5.0,
            nearestGpsAccuracyMeters: 200.0
        )
        XCTAssertEqual(result.maxSpeed, 19.8, accuracy: 1.0)
    }
}
