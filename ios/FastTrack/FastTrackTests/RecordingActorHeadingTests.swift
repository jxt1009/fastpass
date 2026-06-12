import XCTest
@testable import FastTrack

final class RecordingActorHeadingTests: XCTestCase {

    @MainActor
    func test_firstSampleDoesNotClassify() async {
        let actor = RecordingActor.shared
        await actor.resetHeading()
        let r = await actor.ingestHeading(course: 0, speed: 10, timestamp: 1000)
        XCTAssertFalse(r.hasAny)
    }

    @MainActor
    func test_rightTurnAbove35Degrees() async {
        let actor = RecordingActor.shared
        await actor.resetHeading()
        _ = await actor.ingestHeading(course: 0, speed: 10, timestamp: 1000)
        let r = await actor.ingestHeading(course: 50, speed: 10, timestamp: 1003)
        XCTAssertEqual(r.rightTurns, 1)
        XCTAssertEqual(r.leftTurns, 0)
    }

    @MainActor
    func test_laneChangeBelow35Degrees() async {
        let actor = RecordingActor.shared
        await actor.resetHeading()
        _ = await actor.ingestHeading(course: 0, speed: 10, timestamp: 1000)
        let r = await actor.ingestHeading(course: 20, speed: 10, timestamp: 1003)
        XCTAssertEqual(r.laneChanges, 1)
    }

    @MainActor
    func test_sustainedCurveGatesLaneChange() async {
        let actor = RecordingActor.shared
        await actor.resetHeading()
        _ = await actor.ingestHeading(course: 0, speed: 10, timestamp: 1000)
        for i in 1...5 {
            _ = await actor.ingestHeading(course: Double(i) * 5, speed: 10, timestamp: 1000 + Double(i))
        }
        let r = await actor.ingestHeading(course: 30, speed: 10, timestamp: 1008)
        XCTAssertEqual(r.laneChanges, 0)
    }

    @MainActor
    func test_gapResetSuppressesDoubleCount() async {
        let actor = RecordingActor.shared
        await actor.resetHeading()
        _ = await actor.ingestHeading(course: 0, speed: 10, timestamp: 1000)
        let r1 = await actor.ingestHeading(course: 50, speed: 10, timestamp: 1003)
        XCTAssertEqual(r1.rightTurns, 1)
        let r2 = await actor.ingestHeading(course: 110, speed: 10, timestamp: 1004)
        XCTAssertFalse(r2.hasAny)
    }
}
