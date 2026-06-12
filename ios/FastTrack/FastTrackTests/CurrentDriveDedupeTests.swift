import XCTest
import Combine
@testable import FastTrack

final class CurrentDriveDedupeTests: XCTestCase {
    var cancellables: Set<AnyCancellable> = []
    override func tearDown() {
        cancellables.removeAll()
    }

    private func makeDrive() -> Drive {
        Drive(
            id: nil, userID: 0,
            startTime: Date(), endTime: Date(),
            startLatitude: 0, startLongitude: 0,
            endLatitude: 0, endLongitude: 0,
            distance: 0, duration: 0,
            maxSpeed: 0, minSpeed: 0, avgSpeed: 0,
            stoppedTime: 0, leftTurns: 0, rightTurns: 0,
            brakeEvents: 0, laneChanges: 0,
            maxAcceleration: 0, maxDeceleration: 0,
            peakGForce: 0, topCornerSpeed: 0
        )
    }

    func test_noFiringWhenDriveUnchanged() {
        let mgr = DriveManager()
        let drive = makeDrive()
        mgr.currentDrive = drive
        var count = 0
        mgr.objectWillChange.sink { _ in count += 1 }.store(in: &cancellables)
        let initial = count
        mgr.currentDrive = drive
        XCTAssertEqual(count, initial)
    }
}
