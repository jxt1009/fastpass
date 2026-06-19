import XCTest
import CoreLocation
@testable import FastTrack

final class DriveRecordingControllerPostHocAnalysisTests: XCTestCase {
    final class MockDriveAPI: DriveAPI {
        var createDriveCallCount = 0
        var lastCreateDriveInput: Drive?
        var createDriveImpl: ((Drive) async throws -> Drive)?

        func createDrive(_ drive: Drive) async throws -> Drive {
            createDriveCallCount += 1
            lastCreateDriveInput = drive
            if let impl = createDriveImpl { return try await impl(drive) }
            return drive
        }

        func fetchDrives() async throws -> [Drive] { [] }
        func deleteDrive(id: Int) async throws {}
        func fetchMyAchievements() async throws -> UserAchievementsResponse {
            UserAchievementsResponse(catalog: [], unlocked: [])
        }
    }

    @MainActor
    private func makeManager(api: DriveAPI) -> DriveManager {
        let realAPI = APIService()
        let authMgr = AuthManager(apiService: realAPI)
        realAPI.authManager = authMgr
        return DriveManager(
            authManager: authMgr,
            profileManager: ProfileManager(apiService: realAPI),
            settings: AppSettings(apiService: realAPI),
            apiService: api,
            carStatsManager: CarStatsManager(apiService: realAPI),
            achievementManager: AchievementManager()
        )
    }

    @MainActor
    func test_stopRecording_invokesPostHocAnalyzer() async {
        let mock = MockDriveAPI()
        let dm = makeManager(api: mock)
        let locMgr = LocationManager()
        locMgr.authorizationStatus = .authorizedAlways
        dm.setLocationManager(locMgr)
        let controller = dm.recordingController
        controller.startRecording()
        let t0 = Date()
        // Stationary period
        for i in 0..<200 {
            controller.processSpeedSample(SpeedSample(
                speed: 0.0, rawGPSSpeed: 0.0, speedAccuracy: 0.5,
                timestamp: t0.addingTimeInterval(Double(i) * 0.01),
                isZeroLocked: true, stationaryConfidence: 1.0
            ))
        }
        // Launch ramp
        for i in 0..<250 {
            let frac = Double(i) / 250.0
            controller.processSpeedSample(SpeedSample(
                speed: 27.0 * frac,
                rawGPSSpeed: 27.0 * frac,
                speedAccuracy: 0.5,
                timestamp: t0.addingTimeInterval(2.0 + Double(i) * 0.01),
                isZeroLocked: false,
                stationaryConfidence: 0.0
            ))
        }
        // Add a location so stopRecording doesn't short-circuit
        controller.recordingLocations = [CLLocation(latitude: 37.0, longitude: -122.0)]
        await controller.stopRecording()
        XCTAssertNotNil(mock.lastCreateDriveInput)
        XCTAssertGreaterThan(mock.lastCreateDriveInput?.zeroToSixtyAttempts.count ?? 0, 0)
        XCTAssertNotNil(mock.lastCreateDriveInput?.fusedMaxSpeed)
    }

    // MARK: - stopRecording return-value contract (car-stats correctness)

    /// On a successful upload, `stopRecording` must return the SERVER-persisted
    /// drive (with a real id) so `DriveManager` can update car stats from it —
    /// not from the client drive (nil id) or from `currentDrive` (which is
    /// nilled on success).
    @MainActor
    func test_stopRecording_returnsServerDriveOnSuccess() async {
        let mock = MockDriveAPI()
        mock.createDriveImpl = { drive in
            var server = drive
            server.id = 999  // server assigns the id
            return server
        }
        let dm = makeManager(api: mock)
        let locMgr = LocationManager()
        locMgr.authorizationStatus = .authorizedAlways
        dm.setLocationManager(locMgr)
        let controller = dm.recordingController
        controller.startRecording()
        // Give stopRecording something to serialize so it doesn't short-circuit.
        controller.recordingLocations = [CLLocation(latitude: 37.0, longitude: -122.0)]

        let saved = await controller.stopRecording()

        XCTAssertEqual(saved?.id, 999, "stopRecording must return the server-persisted drive on success")
        XCTAssertNil(controller.currentDrive, "currentDrive is nilled on success; stats must come from the return value, not currentDrive")
        XCTAssertEqual(mock.createDriveCallCount, 1)
    }

    /// On upload failure, `stopRecording` must return nil so `DriveManager`
    /// skips car stats now (the in-flight file is retried by
    /// `recoverPendingDrives`, which applies stats once on retry — avoiding a
    /// double count).
    @MainActor
    func test_stopRecording_returnsNilOnFailureAndSurfacesError() async {
        let mock = MockDriveAPI()
        mock.createDriveImpl = { _ in throw APIError.serverError(500) }
        let dm = makeManager(api: mock)
        let locMgr = LocationManager()
        locMgr.authorizationStatus = .authorizedAlways
        dm.setLocationManager(locMgr)
        let controller = dm.recordingController
        controller.startRecording()
        controller.recordingLocations = [CLLocation(latitude: 37.0, longitude: -122.0)]

        let saved = await controller.stopRecording()

        XCTAssertNil(saved, "stopRecording must return nil on upload failure so stats are deferred to recovery")
        guard case .serverError(500)? = controller.lastError else {
            XCTFail("lastError must be .serverError(500); got \(String(describing: controller.lastError))")
            return
        }
        XCTAssertEqual(mock.createDriveCallCount, 1)
    }
}
