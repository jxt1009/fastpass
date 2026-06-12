import XCTest
@testable import FastTrack
import CoreLocation

/// Tests for the Cluster A recording-reliability changes:
///   - A-1: createDrive failures surface as `lastError`
///   - A-2: not exercised here (lives in `FastTrackApp.swift`)
///   - A-3: `startRecording` refuses without `.authorizedAlways`
///   - A-4: `recoverPendingDrives` reads temp files, retries, and
///           cleans up on success
///
/// `APIService` is a singleton with a private init. To test DriveManager
/// in isolation we introduced a `DriveAPI` protocol that the production
/// `APIService` conforms to; `DriveManager` now holds a `DriveAPI`. Tests
/// inject a `MockDriveAPI` here.
final class DriveManagerErrorSurfaceTests: XCTestCase {

    // MARK: - Mock API

    /// Configurable mock that conforms to `DriveAPI`. Each method has a
    /// closure the test can set to control behavior. Call counts are
    /// tracked so tests can assert the recovery path actually ran.
    final class MockDriveAPI: DriveAPI {
        var createDriveImpl: ((Drive) async throws -> Drive)?
        var createDriveCallCount = 0
        var lastCreateDriveInput: Drive?

        var fetchDrivesImpl: (() async throws -> [Drive])?
        var fetchDrivesCallCount = 0

        var deleteDriveImpl: ((Int) async throws -> Void)?
        var deleteDriveCallCount = 0

        var fetchMyAchievementsImpl: (() async throws -> UserAchievementsResponse)?
        var fetchMyAchievementsCallCount = 0

        func createDrive(_ drive: Drive) async throws -> Drive {
            createDriveCallCount += 1
            lastCreateDriveInput = drive
            if let impl = createDriveImpl { return try await impl(drive) }
            // Default: succeed by round-tripping the input with id set.
            return Drive(
                id: 1,
                userID: drive.userID,
                startTime: drive.startTime,
                endTime: drive.endTime,
                startLatitude: drive.startLatitude,
                startLongitude: drive.startLongitude,
                endLatitude: drive.endLatitude,
                endLongitude: drive.endLongitude,
                distance: drive.distance,
                duration: drive.duration,
                maxSpeed: drive.maxSpeed,
                minSpeed: drive.minSpeed,
                avgSpeed: drive.avgSpeed,
                routeData: drive.routeData,
                carId: drive.carId,
                carMake: drive.carMake,
                carModel: drive.carModel,
                carYear: drive.carYear,
                carTrim: drive.carTrim,
                carNickname: drive.carNickname,
                stoppedTime: drive.stoppedTime,
                leftTurns: drive.leftTurns,
                rightTurns: drive.rightTurns,
                brakeEvents: drive.brakeEvents,
                laneChanges: drive.laneChanges,
                maxAcceleration: drive.maxAcceleration,
                maxDeceleration: drive.maxDeceleration,
                peakGForce: drive.peakGForce,
                topCornerSpeed: drive.topCornerSpeed,
                best060Time: drive.best060Time
            )
        }

        func fetchDrives() async throws -> [Drive] {
            fetchDrivesCallCount += 1
            if let impl = fetchDrivesImpl { return try await impl() }
            return []
        }

        func deleteDrive(id: Int) async throws {
            deleteDriveCallCount += 1
            if let impl = deleteDriveImpl { try await impl(id) }
        }

        func fetchMyAchievements() async throws -> UserAchievementsResponse {
            fetchMyAchievementsCallCount += 1
            if let impl = fetchMyAchievementsImpl { return try await impl() }
            return UserAchievementsResponse(catalog: [], unlocked: [])
        }
    }

    // MARK: - Helpers

    private func makeDrive(
        id: Int? = nil,
        userID: Int = 1,
        startTime: Date = Date(timeIntervalSince1970: 1_700_000_000),
        endTime: Date = Date(timeIntervalSince1970: 1_700_000_600),
        withRouteData: Bool = true
    ) -> Drive {
        Drive(
            id: id,
            userID: userID,
            startTime: startTime,
            endTime: endTime,
            startLatitude: 37.0,
            startLongitude: -122.0,
            endLatitude: 37.001,
            endLongitude: -122.0,
            distance: 1000,
            duration: 600,
            maxSpeed: 30,
            minSpeed: 0,
            avgSpeed: 15,
            routeData: withRouteData ? "{\"v\":2,\"points\":[]}" : nil,
            carId: "car-A",
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

    /// Builds a `DriveManager` primed for `stopRecording`: `isRecording`
    /// is true, `currentDrive` is set, `richRoutePoints` is non-empty
    /// (so the `guard` past serialization doesn't return).
    @MainActor
    private func makeManagers(api: MockDriveAPI) -> (APIService, AuthManager) {
        let realAPI = APIService()
        let authMgr = AuthManager(apiService: realAPI)
        realAPI.authManager = authMgr
        return (realAPI, authMgr)
    }

    @MainActor
    private func makeRecordingManager(
        api: MockDriveAPI,
        drive: Drive
    ) -> DriveManager {
        let (realAPI, authMgr) = makeManagers(api: api)
        let dm = DriveManager(
            authManager: authMgr,
            profileManager: ProfileManager(apiService: realAPI),
            settings: AppSettings(apiService: realAPI),
            apiService: api,
            carStatsManager: CarStatsManager(apiService: realAPI),
            achievementManager: AchievementManager()
        )
        dm.isRecording = true
        dm.currentDrive = drive
        dm.richRoutePoints = [
            (lat: 37.0, lng: -122.0, speed: 0, ts: Date().timeIntervalSince1970)
        ]
        return dm
    }

    // MARK: - A-1: lastError is set when createDrive throws

    @MainActor
    func testStopRecording_setsLastError_whenCreateDriveThrows() async {
        let mock = MockDriveAPI()
        mock.createDriveImpl = { _ in throw APIError.serverError(500) }
        let drive = makeDrive()
        let dm = makeRecordingManager(api: mock, drive: drive)

        XCTAssertNil(dm.lastError, "precondition: no prior error")
        await dm.stopRecording()

        guard case .serverError(500)? = dm.lastError else {
            XCTFail("lastError must be .serverError(500); got \(String(describing: dm.lastError))")
            return
        }
        XCTAssertEqual(mock.createDriveCallCount, 1,
                       "createDrive should have been attempted exactly once")
    }

    @MainActor
    func testStopRecording_setsLastError_whenCreateDriveTimesOut() async {
        // Simulate a timeout-style throw (URLError). The catch block must
        // surface it as `lastError` so the view layer can show a banner.
        let mock = MockDriveAPI()
        mock.createDriveImpl = { _ in throw APIError.invalidResponse }
        let drive = makeDrive()
        let dm = makeRecordingManager(api: mock, drive: drive)

        await dm.stopRecording()
        guard case .invalidResponse? = dm.lastError else {
            XCTFail("lastError must be .invalidResponse; got \(String(describing: dm.lastError))")
            return
        }
    }

    @MainActor
    func testStopRecording_doesNotAutoClearStaleLastErrorOnSuccess() async {
        // A successful upload of a NEW drive does not auto-clear a stale
        // lastError from a previous failure. The user must explicitly
        // dismiss it (dismissLastError) or start a new recording, per the
        // spec — so they can still see "your last drive failed" even after
        // a subsequent drive uploads successfully.
        let mock = MockDriveAPI()
        let drive = makeDrive()
        let dm = makeRecordingManager(api: mock, drive: drive)
        dm.lastError = .serverError(503)  // stale from a prior failure

        await dm.stopRecording()
        guard case .serverError(503)? = dm.lastError else {
            XCTFail("a successful upload must not auto-clear a prior lastError; got \(String(describing: dm.lastError))")
            return
        }
    }

    @MainActor
    func testStartRecording_clearsLastError() {
        // The next startRecording should clear any stale failure from a
        // previous drive, so the UI doesn't show a banner that no longer
        // applies.
        let mock = MockDriveAPI()
        let (realAPI, authMgr) = makeManagers(api: mock)
        let dm = DriveManager(authManager: authMgr, profileManager: ProfileManager(apiService: realAPI), settings: AppSettings(apiService: realAPI), apiService: mock, carStatsManager: CarStatsManager(apiService: realAPI), achievementManager: AchievementManager())
        let locMgr = LocationManager()
        locMgr.authorizationStatus = .authorizedAlways
        dm.setLocationManager(locMgr)
        dm.lastError = .serverError(503)  // stale from a prior failure

        dm.startRecording()

        XCTAssertNil(dm.lastError, "startRecording must clear any prior lastError")
    }

    @MainActor
    func testDismissLastError_clearsLastError() async {
        let mock = MockDriveAPI()
        let drive = makeDrive()
        let dm = makeRecordingManager(api: mock, drive: drive)
        dm.lastError = .serverError(500)

        dm.dismissLastError()

        XCTAssertNil(dm.lastError)
    }

    // MARK: - A-3: startRecording refuses without Always permission

    @MainActor
    func testStartRecording_refusesWhenHasRecordingPermissionIsFalse() {
        let mock = MockDriveAPI()
        let (realAPI, authMgr) = makeManagers(api: mock)
        let dm = DriveManager(authManager: authMgr, profileManager: ProfileManager(apiService: realAPI), settings: AppSettings(apiService: realAPI), apiService: mock, carStatsManager: CarStatsManager(apiService: realAPI), achievementManager: AchievementManager())
        let locMgr = LocationManager()
        // Default value is .notDetermined; explicit here for clarity.
        locMgr.authorizationStatus = .notDetermined
        dm.setLocationManager(locMgr)

        dm.startRecording()

        guard case .locationPermissionDenied? = dm.lastError else {
            XCTFail("lastError must be .locationPermissionDenied; got \(String(describing: dm.lastError))")
            return
        }
        XCTAssertFalse(dm.isRecording,
                       "isRecording must remain false when start is refused")
        XCTAssertNil(dm.currentDrive,
                     "currentDrive must remain nil when start is refused")
    }

    @MainActor
    func testStartRecording_refusesWhenAuthorizedWhenInUseOnly() {
        // The user previously granted only WhenInUse (the HIG-friendly
        // path); we still require .authorizedAlways to actually record.
        let mock = MockDriveAPI()
        let (realAPI, authMgr) = makeManagers(api: mock)
        let dm = DriveManager(authManager: authMgr, profileManager: ProfileManager(apiService: realAPI), settings: AppSettings(apiService: realAPI), apiService: mock, carStatsManager: CarStatsManager(apiService: realAPI), achievementManager: AchievementManager())
        let locMgr = LocationManager()
        locMgr.authorizationStatus = .authorizedWhenInUse
        dm.setLocationManager(locMgr)

        dm.startRecording()

        guard case .locationPermissionDenied? = dm.lastError else {
            XCTFail("lastError must be .locationPermissionDenied; got \(String(describing: dm.lastError))")
            return
        }
        XCTAssertFalse(dm.isRecording)
    }

    // MARK: - A-4: recoverPendingDrives retries and cleans up

    @MainActor
    func testRecoverPendingDrives_retriesAndDeletesOnSuccess() async throws {
        let mock = MockDriveAPI()
        // Default createDrive impl succeeds.
        let (realAPI, authMgr) = makeManagers(api: mock)
        let dm = DriveManager(authManager: authMgr, profileManager: ProfileManager(apiService: realAPI), settings: AppSettings(apiService: realAPI), apiService: mock, carStatsManager: CarStatsManager(apiService: realAPI), achievementManager: AchievementManager())

        // Create a temp dir + a valid in-flight file.
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("drive_recover_test_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let drive = makeDrive(userID: 0, startTime: Date(timeIntervalSince1970: 1_700_000_000))
        let url = dm.inFlightTempFileURL(for: drive, in: dir)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(drive)
        try data.write(to: url, options: .atomic)

        await dm.recoverPendingDrives(in: dir)

        XCTAssertEqual(mock.createDriveCallCount, 1,
                       "recoverPendingDrives must call createDrive once per pending file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "recoverPendingDrives must delete the file after a successful upload")
        XCTAssertEqual(dm.drives.first?.id, 1,
                       "recovered drive should be inserted at the top of the local drives list")
    }

    @MainActor
    func testRecoverPendingDrives_leavesFileOnFailure() async throws {
        let mock = MockDriveAPI()
        mock.createDriveImpl = { _ in throw APIError.serverError(503) }
        let (realAPI, authMgr) = makeManagers(api: mock)
        let dm = DriveManager(authManager: authMgr, profileManager: ProfileManager(apiService: realAPI), settings: AppSettings(apiService: realAPI), apiService: mock, carStatsManager: CarStatsManager(apiService: realAPI), achievementManager: AchievementManager())

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("drive_recover_fail_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let drive = makeDrive(userID: 0)
        let url = dm.inFlightTempFileURL(for: drive, in: dir)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(drive).write(to: url, options: .atomic)

        await dm.recoverPendingDrives(in: dir)

        XCTAssertEqual(mock.createDriveCallCount, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path),
                      "file must remain in place so the next poll can retry")
    }

    @MainActor
    func testRecoverPendingDrives_isNoOpWhenNoPendingFiles() async {
        let mock = MockDriveAPI()
        let (realAPI, authMgr) = makeManagers(api: mock)
        let dm = DriveManager(authManager: authMgr, profileManager: ProfileManager(apiService: realAPI), settings: AppSettings(apiService: realAPI), apiService: mock, carStatsManager: CarStatsManager(apiService: realAPI), achievementManager: AchievementManager())

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("drive_recover_empty_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        await dm.recoverPendingDrives(in: dir)

        XCTAssertEqual(mock.createDriveCallCount, 0,
                       "no in-flight files means no createDrive calls")
    }

    @MainActor
    func testRecoverPendingDrives_dropsUnreadableFiles() async throws {
        // A file with the right prefix but garbage contents would otherwise
        // wedge the recovery loop forever. Verify we drop it instead.
        let mock = MockDriveAPI()
        let (realAPI, authMgr) = makeManagers(api: mock)
        let dm = DriveManager(authManager: authMgr, profileManager: ProfileManager(apiService: realAPI), settings: AppSettings(apiService: realAPI), apiService: mock, carStatsManager: CarStatsManager(apiService: realAPI), achievementManager: AchievementManager())

        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("drive_recover_corrupt_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("\(DriveManager.inFlightFilePrefix)99_1.json")
        try "not valid json".data(using: .utf8)!.write(to: url, options: .atomic)

        await dm.recoverPendingDrives(in: dir)

        XCTAssertEqual(mock.createDriveCallCount, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path),
                       "undecodable in-flight files must be dropped, not retried")
    }
}
