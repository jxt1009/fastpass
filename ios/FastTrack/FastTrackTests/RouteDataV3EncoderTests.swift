import XCTest
@testable import FastTrack

final class RouteDataV3EncoderTests: XCTestCase {
    func test_SpeedPeak_encodesWithSourceAndConfidence() throws {
        let peak = SpeedPeak(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            speed: 35.0,
            source: .fused,
            confidence: 0.87
        )
        let data = try JSONEncoder().encode(peak)
        let dict = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(dict["source"] as? String, "fused")
        XCTAssertEqual(dict["confidence"] as? Double, 0.87)
        XCTAssertEqual(dict["speed"] as? Double, 35.0)
    }

    func test_RouteSerializationSnapshot_carriesSpeedStreamAndPeaks() {
        let snapshot = RouteSerializationSnapshot(
            richRoutePoints: [],
            recordedRouteEvents: [],
            attempts: [],
            speedStream: [(0.0, 0.0, true, 1.0), (0.01, 0.5, false, 0.0)],
            speedPeaks: []
        )
        XCTAssertEqual(snapshot.speedStream.count, 2)
        XCTAssertEqual(snapshot.speedStream[0].3, 1.0)
    }
}
