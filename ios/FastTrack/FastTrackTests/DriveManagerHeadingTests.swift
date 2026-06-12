import XCTest
@testable import FastTrack

final class DriveManagerHeadingTests: XCTestCase {

    @MainActor
    func test_headingTotalsAccumulate() async {
        let dm = DriveManager()
        dm.isRecording = true
        dm.richRoutePoints = [
            (lat: 37.0, lng: -122.0, speed: 0, ts: Date().timeIntervalSince1970)
        ]

        await RecordingActor.shared.resetHeading()

        for i in 0..<3 {
            _ = await dm.processHeading(
                course: 0,
                speed: 10,
                timestamp: Date().addingTimeInterval(TimeInterval(i * 10))
            )
            _ = await dm.processHeading(
                course: 50,
                speed: 10,
                timestamp: Date().addingTimeInterval(TimeInterval(i * 10 + 1))
            )
        }

        let totals = await RecordingActor.shared.headingTotals()
        XCTAssertEqual(totals.right, 3, "Three right turns should accumulate")
        XCTAssertEqual(dm.leftTurns, 0)
        XCTAssertEqual(dm.rightTurns, 3)
        XCTAssertEqual(dm.laneChanges, 0)
    }
}
