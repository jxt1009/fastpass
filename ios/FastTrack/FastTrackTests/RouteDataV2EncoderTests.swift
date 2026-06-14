import XCTest
@testable import FastTrack

final class RouteDataV2EncoderTests: XCTestCase {

    func test_encoderProducesV2Array() {
        let points: [(lat: Double, lng: Double, speed: Double, ts: Double)] = [
            (lat: 37.0, lng: -122.0, speed: 10, ts: 1000),
            (lat: 37.001, lng: -122.001, speed: 15, ts: 1001)
        ]
        let snapshot = RouteSerializationSnapshot(
            richRoutePoints: points,
            recordedRouteEvents: [],
            attempts: [],
            speedStream: [],
            speedPeaks: []
        )
        let output = RouteSerializer.encode(snapshot)
        XCTAssertEqual(output.v2Array.count, 2)
        XCTAssertEqual(output.v2Array[0]["lat"] as? Double, 37.0)
        XCTAssertEqual(output.v2Array[0]["speed"] as? Double, 10)
        XCTAssertEqual(output.v2Array[1]["lng"] as? Double, -122.001)
    }

    func test_v1StringIsValidJSON() {
        let points: [(lat: Double, lng: Double, speed: Double, ts: Double)] = [
            (lat: 37.0, lng: -122.0, speed: 10, ts: 1000)
        ]
        let snapshot = RouteSerializationSnapshot(
            richRoutePoints: points,
            recordedRouteEvents: [],
            attempts: [],
            speedStream: [],
            speedPeaks: []
        )
        let output = RouteSerializer.encode(snapshot)
        let data = output.v1String.data(using: .utf8)!
        let json = try? JSONSerialization.jsonObject(with: data)
        XCTAssertNotNil(json, "v1String must be valid JSON")
    }
}
