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
}
