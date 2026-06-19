import XCTest
import MapKit
@testable import FastTrack

final class RouteSpanTests: XCTestCase {

    func testRouteSpan_eastWestRoute_hasWideLongitudeSpan() {
        let lats: [Double] = [37.0, 37.0, 37.0]
        let lngs: [Double] = [-122.0, -121.0, -120.0]

        let span = routeCoordinateSpan(lats: lats, lngs: lngs)

        // Longitude range is 2.0 degrees; span should be 2.0 * 1.3 = 2.6
        XCTAssertEqual(span.longitudeDelta, 2.6, accuracy: 0.001,
            "Longitude span must reflect the actual longitude range, not 0")
        XCTAssertEqual(span.latitudeDelta, max(0.001, 0 * 1.3), accuracy: 0.001,
            "Latitude span is 0 for constant latitude")
    }

    func testRouteSpan_northSouthRoute_hasWideLatitudeSpan() {
        let lats: [Double] = [37.0, 38.0, 39.0]
        let lngs: [Double] = [-122.0, -122.0, -122.0]

        let span = routeCoordinateSpan(lats: lats, lngs: lngs)

        XCTAssertEqual(span.latitudeDelta, 2.6, accuracy: 0.001,
            "Latitude span must reflect the actual latitude range")
        XCTAssertEqual(span.longitudeDelta, max(0.001, 0 * 1.3), accuracy: 0.001,
            "Longitude span is 0 for constant longitude")
    }

    func testRouteSpan_diagonalRoute_bothSpansNonZero() {
        let lats: [Double] = [37.0, 38.0]
        let lngs: [Double] = [-122.0, -121.0]

        let span = routeCoordinateSpan(lats: lats, lngs: lngs)

        XCTAssertEqual(span.latitudeDelta, 1.3, accuracy: 0.001)
        XCTAssertEqual(span.longitudeDelta, 1.3, accuracy: 0.001)
    }

    func testRouteSpan_singlePoint_minimumSpan() {
        let lats: [Double] = [37.0]
        let lngs: [Double] = [-122.0]

        let span = routeCoordinateSpan(lats: lats, lngs: lngs)

        XCTAssertEqual(span.latitudeDelta, 0.001, accuracy: 0.0001)
        XCTAssertEqual(span.longitudeDelta, 0.001, accuracy: 0.0001)
    }
}
