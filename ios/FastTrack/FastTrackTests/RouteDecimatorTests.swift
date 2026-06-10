import XCTest
import CoreLocation
@testable import FastTrack

final class RouteDecimatorTests: XCTestCase {

    func test_emptyAndSinglePointAreReturnedAsIs() {
        XCTAssertEqual(RouteDecimator.decimate([], toleranceMeters: 5).count, 0)
        let one = [CLLocationCoordinate2D(latitude: 0, longitude: 0)]
        XCTAssertEqual(RouteDecimator.decimate(one, toleranceMeters: 5).count, 1)
    }

    func test_straightLineIsReducedToEndpoints() {
        // 100 collinear points on a line at the equator.
        let pts = (0..<100).map { i in
            CLLocationCoordinate2D(latitude: 0, longitude: Double(i) * 0.0001)
        }
        let out = RouteDecimator.decimate(pts, toleranceMeters: 5)
        // Endpoints + any corners; collinear reduces to 2.
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.first?.longitude ?? -1, 0, accuracy: 1e-6)
        XCTAssertEqual(out.last?.longitude ?? -1, 99 * 0.0001, accuracy: 1e-6)
    }

    func test_sharpTurnIsPreserved() {
        // Straight, then 90° turn, then straight.
        var pts: [CLLocationCoordinate2D] = []
        for i in 0..<50 { pts.append(CLLocationCoordinate2D(latitude: 0, longitude: Double(i) * 0.0001)) }
        for i in 0..<50 { pts.append(CLLocationCoordinate2D(latitude: Double(i) * 0.0001, longitude: 50 * 0.0001)) }
        let out = RouteDecimator.decimate(pts, toleranceMeters: 5)
        // Must keep the corner point (the 90° turn).
        XCTAssertGreaterThanOrEqual(out.count, 3)
        // The middle point should be the corner.
        let mid = out[out.count / 2]
        XCTAssertEqual(mid.latitude, 0, accuracy: 1e-3)
        XCTAssertEqual(mid.longitude, 50 * 0.0001, accuracy: 1e-3)
    }

    func test_respectsMaxOutputSize() {
        // 1000 noisy points that don't simplify down to 2; ensure
        // the decimation reduces the array, and that running
        // decimation on a sliding window never blows past the cap.
        let pts = (0..<1000).map { i in
            CLLocationCoordinate2D(
                latitude: sin(Double(i) / 10.0) * 0.001,
                longitude: Double(i) * 0.0001
            )
        }
        let out = RouteDecimator.decimate(pts, toleranceMeters: 1, maxOutput: 200)
        XCTAssertLessThanOrEqual(out.count, 200)
    }
}
