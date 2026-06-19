import XCTest
@testable import FastTrack

/// Tests that restoreDrive inserts the server-returned Drive (with the
/// server-assigned id), not the original client Drive. Uses a MockDriveAPI
/// that conforms to the DriveAPI protocol (per the project's DI pattern).
final class DriveRestoreTests: XCTestCase {

    /// Mock that returns a pre-configured Drive from createDrive, simulating
    /// the server assigning a new id. All other methods are stubbed.
    private final class MockDriveAPI: DriveAPI {
        var createDriveResult: Drive?

        func createDrive(_ drive: Drive) async throws -> Drive {
            return createDriveResult ?? drive
        }
        func fetchDrives() async throws -> [Drive] { [] }
        func deleteDrive(id: Int) async throws {}
        func fetchMyAchievements() async throws -> UserAchievementsResponse {
            UserAchievementsResponse(catalog: [], unlocked: [])
        }
    }

    private func makeDrive(id: Int?, carId: String? = "car-A") -> Drive {
        Drive(
            id: id,
            userID: 1,
            startTime: Date(timeIntervalSince1970: 1_000_000),
            endTime: Date(timeIntervalSince1970: 1_000_600),
            startLatitude: 37.0,
            startLongitude: -122.0,
            endLatitude: 37.001,
            endLongitude: -122.0,
            distance: 1000,
            duration: 600,
            maxSpeed: 30,
            minSpeed: 0,
            avgSpeed: 15,
            carId: carId,
            stoppedTime: 0,
            leftTurns: 0,
            rightTurns: 0,
            brakeEvents: 0,
            laneChanges: 0,
            maxAcceleration: 0,
            maxDeceleration: 0,
            peakGForce: 0,
            topCornerSpeed: 0
        )
    }

    @MainActor
    func testRestoreDrive_usesServerReturnedId() async {
        let mockAPI = MockDriveAPI()
        // The server creates a new record and returns it with id=999.
        mockAPI.createDriveResult = makeDrive(id: 999)

        let dm = DriveManager.forTesting(apiService: mockAPI)

        // The client drive has id=nil.
        let clientDrive = makeDrive(id: nil)

        await dm.restoreDrive(clientDrive)

        XCTAssertEqual(dm.drives.count, 1,
            "One drive should be inserted after restore")
        XCTAssertEqual(dm.drives.first?.id, 999,
            "The restored drive must use the server-returned id, not the original nil id")
    }
}
