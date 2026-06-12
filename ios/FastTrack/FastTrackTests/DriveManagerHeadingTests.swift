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

        // Monotonic heading: baseline (0°) → right turn (50°) → settle → right (100°) → settle → right (150°)
        let samples: [(course: Double, ts: TimeInterval)] = [
            (0, 0),
            (50, 3),
            (50, 13),
            (100, 16),
            (100, 26),
            (150, 29),
        ]
        for s in samples {
            _ = await dm.processHeading(
                course: s.course,
                speed: 10,
                timestamp: Date().addingTimeInterval(s.ts)
            )
        }

        let totals = await RecordingActor.shared.headingTotals()
        XCTAssertEqual(totals.right, 3, "Three right turns should accumulate")
        XCTAssertEqual(dm.leftTurns, 0)
        XCTAssertEqual(dm.rightTurns, 3)
        XCTAssertEqual(dm.laneChanges, 0)
    }
}
