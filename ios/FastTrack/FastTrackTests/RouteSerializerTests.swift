import XCTest
@testable import FastTrack

final class RouteSerializerTests: XCTestCase {
    func test_encodesEmptyRouteAsEmptyArrays() {
        let snap = RouteSerializationSnapshot(
            richRoutePoints: [],
            recordedRouteEvents: [],
            attempts: []
        )
        let json = RouteSerializer.encodeV2(snapshot: snap)
        XCTAssertNotNil(json)
        // Round-trip the JSON to assert the shape.
        let data = json!.data(using: .utf8)!
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["v"] as? Int, 2)
        XCTAssertEqual((obj?["points"] as? [Any])?.count, 0)
        XCTAssertEqual((obj?["events"] as? [Any])?.count, 0)
    }

    func test_encodesPointsAndEvents() {
        let snap = RouteSerializationSnapshot(
            richRoutePoints: [(lat: 1.0, lng: 2.0, speed: 10.0, ts: 100.0)],
            recordedRouteEvents: [(type: "brake", lat: 1.0, lng: 2.0, ts: 100.5)],
            attempts: []
        )
        let json = RouteSerializer.encodeV2(snapshot: snap)!
        let data = json.data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual((obj["points"] as! [Any]).count, 1)
        XCTAssertEqual((obj["events"] as! [Any]).count, 1)
    }
}
