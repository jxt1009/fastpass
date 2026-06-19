import XCTest
@testable import FastTrack

/// Tests for the fetchVersion gate in `DrivePoller.pollCycle`. A delete during
/// an in-flight poll bumps `fetchVersion` via `invalidateStaleFetches`; the
/// gate prevents the stale fetch result from overwriting post-delete state
/// (i.e. resurrecting a deleted drive).
final class DrivePollerFetchVersionTests: XCTestCase {

    /// Mock `DriveAPI` whose `fetchDrives()` suspends on a continuation until
    /// the test resumes it, letting us inject a delete while a poll is in flight.
    private final class DelayedFetchDriveAPI: DriveAPI {
        private var continuation: CheckedContinuation<[Drive], Error>?
        var fetchDrivesCallCount = 0
        var drivesToReturn: [Drive] = []

        func createDrive(_ drive: Drive) async throws -> Drive { drive }

        func fetchDrives() async throws -> [Drive] {
            fetchDrivesCallCount += 1
            return try await withCheckedThrowingContinuation { cont in
                continuation = cont
            }
        }

        func resumeFetch() {
            continuation?.resume(returning: drivesToReturn)
            continuation = nil
        }

        func deleteDrive(id: Int) async throws {}
        func fetchMyAchievements() async throws -> UserAchievementsResponse {
            UserAchievementsResponse(catalog: [], unlocked: [])
        }
    }

    override func setUp() {
        super.setUp()
        // Ensure no leftover in-flight files trip recoverPendingDrives into a
        // second fetchDrives call (which would suspend on a fresh continuation).
        let fm = FileManager.default
        if let entries = try? fm.contentsOfDirectory(
            at: .temporaryDirectory, includingPropertiesForKeys: nil) {
            for url in entries where url.lastPathComponent.hasPrefix("in_flight_drive_")
                && url.pathExtension == "json" {
                try? fm.removeItem(at: url)
            }
        }
    }

    @MainActor
    private func makePoller(api: DriveAPI) -> DrivePoller {
        DrivePoller(
            apiService: api,
            carStatsManager: CarStatsManager(apiService: APIService())
        )
    }

    private func makeDrive(id: Int) -> Drive {
        Drive(
            id: id, userID: 1,
            startTime: Date(timeIntervalSince1970: 1_000_000),
            endTime: Date(timeIntervalSince1970: 1_000_600),
            startLatitude: 37.0, startLongitude: -122.0,
            endLatitude: 37.001, endLongitude: -122.0,
            distance: 1000, duration: 600,
            maxSpeed: 30, minSpeed: 0, avgSpeed: 15,
            carId: "car-A",
            stoppedTime: 0, leftTurns: 0, rightTurns: 0,
            brakeEvents: 0, laneChanges: 0,
            maxAcceleration: 0, maxDeceleration: 0,
            peakGForce: 0, topCornerSpeed: 0
        )
    }

    /// Control: with no delete during the fetch, pollCycle applies the result.
    @MainActor
    func test_pollCycle_appliesResultWhenNoDelete() async {
        let api = DelayedFetchDriveAPI()
        let drive = makeDrive(id: 1)
        api.drivesToReturn = [drive]
        let poller = makePoller(api: api)

        let pollTask = Task { await poller.pollCycle() }
        while api.fetchDrivesCallCount == 0 { await Task.yield() }
        api.resumeFetch()
        await pollTask.value

        XCTAssertEqual(poller.drives.count, 1)
        XCTAssertEqual(poller.drives.first?.id, 1)
    }

    /// A delete during an in-flight poll bumps fetchVersion; pollCycle must
    /// drop the stale result instead of resurrecting the deleted drive.
    @MainActor
    func test_pollCycle_dropsStaleResultAfterDelete() async {
        let api = DelayedFetchDriveAPI()
        let drive = makeDrive(id: 1)
        api.drivesToReturn = [drive]
        let poller = makePoller(api: api)

        let pollTask = Task { await poller.pollCycle() }
        // Wait for pollCycle to reach the in-flight fetchDrives call.
        while api.fetchDrivesCallCount == 0 { await Task.yield() }

        // Simulate a user delete while the fetch is in flight — this bumps
        // fetchVersion via invalidateStaleFetches().
        poller.noteDriveDeleted(userID: 1, startTime: drive.startTime)

        // Resume the fetch; pollCycle must reject the now-stale result.
        api.resumeFetch()
        await pollTask.value

        XCTAssertTrue(poller.drives.isEmpty,
            "stale fetch result must be dropped after a delete bumps fetchVersion")
    }
}
