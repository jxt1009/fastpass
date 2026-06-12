import XCTest
import CoreLocation
@testable import FastTrack

final class DriveManagerConcurrencyTests: XCTestCase {
    @MainActor
    func test_concurrentProcessLocationAndSpeedSample() async {
        let mgr = DriveManager()
        mgr.isRecording = true
        mgr.recordingStartTime = Date()
        mgr.currentDrive = Drive(
            id: nil, userID: 1,
            startTime: Date(), endTime: Date(),
            startLatitude: 37, startLongitude: -122,
            endLatitude: 37.001, endLongitude: -122,
            distance: 0, duration: 0,
            maxSpeed: 0, minSpeed: 0, avgSpeed: 0,
            routeData: nil,
            stoppedTime: 0, leftTurns: 0, rightTurns: 0,
            brakeEvents: 0, laneChanges: 0,
            maxAcceleration: 0, maxDeceleration: 0,
            peakGForce: 0, topCornerSpeed: 0,
            best060Time: nil
        )

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<500 {
                group.addTask { @MainActor in
                    let loc = CLLocation(latitude: 37, longitude: -122)
                    mgr.processLocation(loc)
                }
                group.addTask { @MainActor in
                    let sample = SpeedSample(
                        speed: 10, rawGPSSpeed: 9.5, speedAccuracy: 0.5,
                        timestamp: Date(), isZeroLocked: false, stationaryConfidence: 0
                    )
                    mgr.processSpeedSample(sample)
                }
            }
        }
    }
}
