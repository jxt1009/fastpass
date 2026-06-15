import XCTest
import CoreLocation
@testable import FastTrack

@MainActor
final class LiveActivityCoordinationTests: XCTestCase {

    final class MockLiveActivity: LiveActivityController {
        struct Call: Equatable {
            enum Kind: Equatable { case start, update, end, sweep }
            let kind: Kind
        }
        private(set) var calls: [Call] = []
        private(set) var lastEndedWithLinger: TimeInterval?
        private(set) var lastEndedWithFinalState: DriveActivityAttributes.DriveActivityState?

        func start(recordingStartTime: Date?) { calls.append(.init(kind: .start)) }
        func update(speedMph: Double, distanceMiles: Double, currentGForce: Double, currentMaxSpeed: Double) async {
            calls.append(.init(kind: .update))
        }
        func end(finalState: DriveActivityAttributes.DriveActivityState?, lingerSeconds: TimeInterval) async {
            calls.append(.init(kind: .end))
            lastEndedWithLinger = lingerSeconds
            lastEndedWithFinalState = finalState
        }
        func dismissAllOrphans() async { calls.append(.init(kind: .sweep)) }
    }

    func test_stopRecording_awaitsLiveActivityEnd() async {
        let mock = MockLiveActivity()
        let dm = DriveManager.forTesting(apiService: APIService(), liveActivity: mock)
        dm.isRecording = true
        dm.recordingLocations = [CLLocation(latitude: 37.0, longitude: -122.0)]
        await dm.stopRecording()
        XCTAssertTrue(mock.calls.contains(.init(kind: .end)))
    }

    func test_stopRecording_endsWithLingerForSummary() async {
        let mock = MockLiveActivity()
        let dm = DriveManager.forTesting(apiService: APIService(), liveActivity: mock)
        dm.isRecording = true
        dm.recordingLocations = [CLLocation(latitude: 37.0, longitude: -122.0)]
        await dm.stopRecording()
        XCTAssertEqual(mock.lastEndedWithLinger, 4)
    }

    func test_stopRecording_marksFinalStateAsEnded() async {
        let mock = MockLiveActivity()
        let dm = DriveManager.forTesting(apiService: APIService(), liveActivity: mock)
        dm.isRecording = true
        dm.recordingLocations = [CLLocation(latitude: 37.0, longitude: -122.0)]
        dm.recordingController.currentDrive = Drive.example
        await dm.stopRecording()
        XCTAssertEqual(mock.lastEndedWithFinalState?.phase, .ended)
    }

    func test_recordingUpdates_pushedToLiveActivity() async {
        let mock = MockLiveActivity()
        let dm = DriveManager.forTesting(apiService: APIService(), liveActivity: mock)
        dm.recordingController.isRecording = true
        dm.recordingController.currentDrive = Drive.example
        // Allow the unstructured Task inside the sink to run.
        try? await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertTrue(mock.calls.contains(.init(kind: .update)))
    }

    // Backward-compat: an in-flight Live Activity payload from an older app
    // build (no `phase`, no `elapsedSeconds`) must still decode and default
    // to `.recording` with `elapsedSeconds == 0`. Locks the contract added in
    // Task 4 — if anyone removes the `decodeIfPresent` defaults this trips.
    func test_contentState_decodesOldShapeWithDefaults() throws {
        let oldShape: [String: Any] = [
            "speedMph": 42.0,
            "gForce": 0.3,
            "distanceMiles": 1.25,
            "maxSpeedMph": 65.0
        ]
        let data = try JSONSerialization.data(withJSONObject: oldShape)
        let decoded = try JSONDecoder().decode(
            DriveActivityAttributes.DriveActivityState.self,
            from: data
        )
        XCTAssertEqual(decoded.phase, .recording)
        XCTAssertEqual(decoded.elapsedSeconds, 0)
        XCTAssertEqual(decoded.speedMph, 42.0)
        XCTAssertEqual(decoded.maxSpeedMph, 65.0)
    }
}
