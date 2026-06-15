import XCTest
@testable import FastTrack

final class DriveModelBackwardCompatTests: XCTestCase {
    func test_Drive_decodesOldServerResponse_withoutNewFields() throws {
        let json = """
        {"id":1,"user_id":1,"start_time":"2025-01-01T00:00:00Z","end_time":"2025-01-01T00:30:00Z","start_latitude":0,"start_longitude":0,"end_latitude":0,"end_longitude":0,"distance":1000,"duration":1800,"max_speed":30,"min_speed":0,"avg_speed":20,"stopped_time":0,"left_turns":0,"right_turns":0,"brake_events":0,"lane_changes":0,"max_acceleration":0,"max_deceleration":0,"peak_g_force":0,"top_corner_speed":0}
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let drive = try decoder.decode(Drive.self, from: json)
        XCTAssertNil(drive.fusedMaxSpeed)
        XCTAssertNil(drive.gpsMaxSpeed)
        XCTAssertEqual(drive.maxSpeed, 30.0)
    }
}
