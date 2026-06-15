import XCTest
@testable import FastTrack

final class RouteDataBackwardCompatTests: XCTestCase {
    func test_ZeroToSixtyAttempt_decodeMissingConfidence_defaultsToZero() throws {
        let json = """
        {"start_index":0,"end_index":10,"start_ts":1000.0,"end_ts":1002.5,"elapsed_s":2.5,"start_lat":1.0,"start_lng":2.0,"end_lat":1.1,"end_lng":2.1}
        """.data(using: .utf8)!
        let attempt = try JSONDecoder().decode(ZeroToSixtyAttempt.self, from: json)
        XCTAssertEqual(attempt.confidence, 0.0)
    }

    func test_v2RouteData_decodesCleanly() throws {
        let data = """
        {"v":2,"points":[{"lat":1.0,"lng":2.0,"speed":5.0,"ts":1000.0}]}
        """.data(using: .utf8)!
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(json?["v"] as? Int, 2)
        XCTAssertNotNil(json?["points"])
    }
}
