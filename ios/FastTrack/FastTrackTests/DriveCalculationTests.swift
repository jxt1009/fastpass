import XCTest
@testable import FastTrack

// NOTE: These tests exercise pure calculation logic extracted from DriveManager.
// DriveManager itself is not directly tested here (requires location entitlements).

final class DriveCalculationTests: XCTestCase {

    // MARK: - Speed statistics helpers

    /// Simulates the avgSpeed calculation used after a drive completes.
    private func avgSpeed(readings: [Double]) -> Double {
        guard !readings.isEmpty else { return 0 }
        return readings.reduce(0, +) / Double(readings.count)
    }

    private func makeDrive(routeData: String, maxSpeed: Double, avgSpeed: Double, best060Time: Double?) -> Drive {
        Drive(
            id: nil,
            userID: 1,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_010),
            startLatitude: 37.0,
            startLongitude: -122.0,
            endLatitude: 37.001,
            endLongitude: -122.0,
            distance: 100,
            duration: 10,
            maxSpeed: maxSpeed,
            minSpeed: 0,
            avgSpeed: avgSpeed,
            routeData: routeData,
            carId: nil,
            carMake: nil,
            carModel: nil,
            carYear: nil,
            carTrim: nil,
            carNickname: nil,
            stoppedTime: 0,
            leftTurns: 0,
            rightTurns: 0,
            brakeEvents: 0,
            laneChanges: 0,
            maxAcceleration: 0,
            maxDeceleration: 0,
            peakGForce: 0,
            topCornerSpeed: 0,
            best060Time: best060Time
        )
    }

    func testAvgSpeed_EmptyReadings() {
        XCTAssertEqual(avgSpeed(readings: []), 0.0)
    }

    func testAvgSpeed_SingleReading() {
        XCTAssertEqual(avgSpeed(readings: [10.0]), 10.0, accuracy: 0.001)
    }

    func testAvgSpeed_MultipleReadings() {
        let result = avgSpeed(readings: [10.0, 20.0, 30.0])
        XCTAssertEqual(result, 20.0, accuracy: 0.001)
    }

    func testAvgSpeed_AllZeros() {
        XCTAssertEqual(avgSpeed(readings: [0, 0, 0]), 0.0)
    }

    // MARK: - Distance calculation (Haversine)

    /// Approximates great-circle distance between two lat/lon points in meters.
    private func haversineDistance(
        lat1: Double, lon1: Double,
        lat2: Double, lon2: Double
    ) -> Double {
        let R = 6371000.0 // Earth radius in meters
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat/2) * sin(dLat/2)
            + cos(lat1 * .pi / 180) * cos(lat2 * .pi / 180)
            * sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return R * c
    }

    func testHaversine_SamePoint() {
        let d = haversineDistance(lat1: 37.0, lon1: -122.0, lat2: 37.0, lon2: -122.0)
        XCTAssertEqual(d, 0.0, accuracy: 0.001)
    }

    func testHaversine_KnownDistance_ApproxOneDegreeLatitude() {
        // 1 degree of latitude ≈ 111,195 meters
        let d = haversineDistance(lat1: 0.0, lon1: 0.0, lat2: 1.0, lon2: 0.0)
        XCTAssertEqual(d, 111195.0, accuracy: 500.0) // within 500m tolerance
    }

    func testHaversine_ShortDistance() {
        // ~111 meters north
        let d = haversineDistance(lat1: 37.33182, lon1: -122.03118,
                                   lat2: 37.33272, lon2: -122.03118)
        XCTAssertEqual(d, 100.0, accuracy: 15.0) // within 15m
    }

    // MARK: - Max/min speed

    func testMaxSpeed() {
        let readings = [10.0, 25.5, 18.3, 44.7, 30.1]
        XCTAssertEqual(readings.max() ?? 0, 44.7, accuracy: 0.001)
    }

    func testMinSpeed_ExcludeZero() {
        // minSpeed should ignore stopped (0 m/s) readings when computing meaningful minimum
        let readings = [0.0, 0.0, 5.2, 10.4, 8.0]
        let nonZero = readings.filter { $0 > 0 }
        XCTAssertEqual(nonZero.min() ?? 0, 5.2, accuracy: 0.001)
    }

    func testMinSpeed_AllZero() {
        let readings = [0.0, 0.0, 0.0]
        let nonZero = readings.filter { $0 > 0 }
        XCTAssertTrue(nonZero.isEmpty)
    }

    // MARK: - 0-60 time calculation

    /// Finds the shortest time span in a speed-time series to go from 0 to 60 mph (26.82 m/s).
    private func best060(speedSamples: [(time: TimeInterval, speed: Double)]) -> Double? {
        let target = 26.8224 // m/s = 60 mph
        var result: Double? = nil

        for i in 0..<speedSamples.count {
            guard speedSamples[i].speed < 2.0 else { continue } // near standstill
            for j in (i+1)..<speedSamples.count {
                if speedSamples[j].speed >= target {
                    let elapsed = speedSamples[j].time - speedSamples[i].time
                    if result == nil || elapsed < result! {
                        result = elapsed
                    }
                    break
                }
            }
        }
        return result
    }

    func testBest060_PerfectAcceleration() {
        // Simulated 4-second 0-60
        let samples: [(TimeInterval, Double)] = [
            (0.0, 0.0),
            (1.0, 6.7),
            (2.0, 13.4),
            (3.0, 20.1),
            (4.0, 27.0)  // exceeds 26.8224 m/s
        ]
        let result = best060(speedSamples: samples)
        XCTAssertNotNil(result)
        XCTAssertEqual(result!, 4.0, accuracy: 0.01)
    }

    func testBest060_NeverReaches60() {
        let samples: [(TimeInterval, Double)] = [
            (0.0, 0.0),
            (1.0, 10.0),
            (2.0, 20.0)
        ]
        let result = best060(speedSamples: samples)
        XCTAssertNil(result)
    }

    func testBest060_NeverStopsFirst() {
        // Never starts from standstill — no valid 0-60 window
        let samples: [(TimeInterval, Double)] = [
            (0.0, 15.0),
            (1.0, 20.0),
            (2.0, 30.0)
        ]
        let result = best060(speedSamples: samples)
        XCTAssertNil(result)
    }

    func testSpeedFusion_ZeroLockEngagesQuicklyNearStop() {
        let fusion = SpeedFusion()

        fusion.update(gpsSpeed: 0.4, gpsSpeedAccuracy: 1.0)
        XCTAssertFalse(fusion.isZeroLocked)

        for _ in 0..<15 {
            fusion.predict(longAccelG: 0, dt: 1.0 / 25.0)
        }

        XCTAssertTrue(fusion.isZeroLocked)
        XCTAssertEqual(fusion.speed, 0, accuracy: 0.01)
        XCTAssertGreaterThanOrEqual(fusion.stationaryConfidence, 0.99)
    }

    func testLaunchTracker_InterpolatesFastZeroToSixty() {
        var tracker = LaunchTracker()
        let start = Date(timeIntervalSince1970: 1_700_000_000)

        let samples = [
            SpeedSample(speed: 0.0, rawGPSSpeed: 0.0, speedAccuracy: 0.5, timestamp: start, isZeroLocked: true, stationaryConfidence: 1.0),
            SpeedSample(speed: 0.9, rawGPSSpeed: 0.8, speedAccuracy: 0.5, timestamp: start.addingTimeInterval(0.04), isZeroLocked: false, stationaryConfidence: 0.0),
            SpeedSample(speed: 25.85, rawGPSSpeed: 25.5, speedAccuracy: 0.5, timestamp: start.addingTimeInterval(2.92), isZeroLocked: false, stationaryConfidence: 0.0),
            SpeedSample(speed: 27.15, rawGPSSpeed: 27.0, speedAccuracy: 0.5, timestamp: start.addingTimeInterval(2.96), isZeroLocked: false, stationaryConfidence: 0.0)
        ]

        var result: Double?
        for sample in samples {
            result = tracker.ingest(sample) ?? result
        }

        XCTAssertNotNil(result)
        XCTAssertEqual(result ?? 0, 2.91, accuracy: 0.03)
        XCTAssertEqual(tracker.best060Time ?? 0, 2.91, accuracy: 0.03)
    }

    func testLaunchTracker_RejectsRollingStart() {
        var tracker = LaunchTracker()
        let start = Date(timeIntervalSince1970: 1_700_000_100)

        let samples = [
            SpeedSample(speed: 6.0, rawGPSSpeed: 6.0, speedAccuracy: 0.5, timestamp: start, isZeroLocked: false, stationaryConfidence: 0.0),
            SpeedSample(speed: 20.0, rawGPSSpeed: 20.0, speedAccuracy: 0.5, timestamp: start.addingTimeInterval(1.5), isZeroLocked: false, stationaryConfidence: 0.0),
            SpeedSample(speed: 27.0, rawGPSSpeed: 27.0, speedAccuracy: 0.5, timestamp: start.addingTimeInterval(2.5), isZeroLocked: false, stationaryConfidence: 0.0)
        ]

        var result: Double?
        for sample in samples {
            result = tracker.ingest(sample) ?? result
        }

        XCTAssertNil(result)
        XCTAssertNil(tracker.best060Time)
    }

    func testPerformanceMetrics_ParsesV2RoutePayloadAndUsesStoredBest060() throws {
        var points: [[String: Any]] = []
        for index in 0..<10 {
            points.append([
                "lat": 37.0 + Double(index) * 0.0001,
                "lng": -122.0,
                "speed": Double(index) * 3.0,
                "ts": 1_700_000_000.0 + Double(index)
            ])
        }
        let payload: [String: Any] = ["v": 2, "points": points, "events": []]
        let data = try JSONSerialization.data(withJSONObject: payload)
        let routeData = try XCTUnwrap(String(data: data, encoding: .utf8))

        let drive = makeDrive(routeData: routeData, maxSpeed: 27.0, avgSpeed: 13.5, best060Time: 2.91)

        let metrics = try XCTUnwrap(drive.calculatePerformanceMetrics())
        let zeroToSixty = try XCTUnwrap(metrics.accelerationMetrics.zeroToSixty)
        XCTAssertEqual(zeroToSixty, 2.91, accuracy: 0.001)
    }

    func testPerformanceMetrics_ParsesLegacyRouteArray() throws {
        var points: [[String: Any]] = []
        for index in 0..<10 {
            points.append([
                "lat": 37.0 + Double(index) * 0.0001,
                "lng": -122.0,
                "speed": Double(index),
                "timestamp": 1_700_000_000.0 + Double(index)
            ])
        }
        let data = try JSONSerialization.data(withJSONObject: points)
        let routeData = try XCTUnwrap(String(data: data, encoding: .utf8))

        let drive = makeDrive(routeData: routeData, maxSpeed: 9, avgSpeed: 4.5, best060Time: nil)

        XCTAssertNotNil(drive.calculatePerformanceMetrics())
    }
}
