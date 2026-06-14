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

    func test_encodeSpeedStream_deltaCompresses() {
        let stream: [(TimeInterval, Double, Bool, Double)] = [
            (1000.0, 0.0, true, 1.0),
            (1000.01, 0.5, false, 0.0),
            (1000.02, 1.0, false, 0.0)
        ]
        let encoded = RouteSerializer.encodeSpeedStream(stream)
        XCTAssertEqual(encoded.first as? [AnyHashable], [1000.0, 0.0, 1, 1.0] as [AnyHashable])
        let second = encoded[1] as? [Any]
        XCTAssertEqual(second?[0] as? Int, 10)
        XCTAssertEqual(second?[1] as? Double, 0.5)
    }

    func test_encodeSpeedStream_decodeSpeedStream_roundtrip() {
        let original: [(TimeInterval, Double, Bool, Double)] = [
            (1000.0, 0.0, true, 1.0),
            (1000.01, 0.5, false, 0.0),
            (1000.05, 2.0, false, 0.0)
        ]
        let encoded = RouteSerializer.encodeSpeedStream(original)
        let decoded = RouteSerializer.decodeSpeedStream(encoded)
        XCTAssertEqual(decoded.count, original.count)
        for (a, b) in zip(decoded, original) {
            XCTAssertEqual(a.0, b.0, accuracy: 0.001)
            XCTAssertEqual(a.1, b.1, accuracy: 0.0001)
            XCTAssertEqual(a.2, b.2)
            XCTAssertEqual(a.3, b.3, accuracy: 0.0001)
        }
    }
}
