import XCTest
@testable import FastTrack

final class DriveManagerHeadingTests: XCTestCase {

    @MainActor
    func test_headingTotalsAccumulate() async {
        let dm = DriveManager.forTesting(apiService: APIService())
        dm.isRecording = true

        await RecordingActor.shared.resetHeading()

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
        XCTAssertEqual(dm.recordingController.leftTurns, 0)
        XCTAssertEqual(dm.recordingController.rightTurns, 3)
        XCTAssertEqual(dm.recordingController.laneChanges, 0)
    }
}
