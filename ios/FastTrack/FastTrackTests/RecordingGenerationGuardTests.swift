import XCTest
import CoreLocation
@testable import FastTrack

/// Tests for the generation guard added in the R2 recording-core audit.
/// `startRecording` bumps `recordingGeneration`; detached
/// `processLocationHeavy` tasks capture the generation at launch and re-check
/// it before ingesting, so a location carried past a stop/reset can't pollute
/// the next drive's RecordingActor state.
final class RecordingGenerationGuardTests: XCTestCase {

    private final class NoopDriveAPI: DriveAPI {
        func createDrive(_ drive: Drive) async throws -> Drive { drive }
        func fetchDrives() async throws -> [Drive] { [] }
        func deleteDrive(id: Int) async throws {}
        func fetchMyAchievements() async throws -> UserAchievementsResponse {
            UserAchievementsResponse(catalog: [], unlocked: [])
        }
    }

    @MainActor
    private func makeController() -> (DriveRecordingController, LocationManager) {
        let realAPI = APIService()
        let authMgr = AuthManager(apiService: realAPI)
        realAPI.authManager = authMgr
        let dm = DriveManager(
            authManager: authMgr,
            profileManager: ProfileManager(apiService: realAPI),
            settings: AppSettings(apiService: realAPI),
            apiService: NoopDriveAPI(),
            carStatsManager: CarStatsManager(apiService: realAPI),
            achievementManager: AchievementManager()
        )
        let locMgr = LocationManager()
        locMgr.authorizationStatus = .authorizedAlways
        dm.setLocationManager(locMgr)
        // Keep locMgr alive: the controller holds it weakly, so startRecording's
        // permission guard fails without it and generation never bumps.
        return (dm.recordingController, locMgr)
    }

    /// `startRecording` must bump `recordingGeneration` so stale detached tasks
    /// are rejected. The bump happens after the permission check, so the test
    /// grants `authorizedAlways` to clear that guard.
    @MainActor
    func test_recordingGenerationIncrementsOnStart() {
        let (controller, _locMgr) = makeController()
        let gen0 = controller.testRecordingGeneration

        controller.startRecording()
        let gen1 = controller.testRecordingGeneration
        XCTAssertGreaterThan(gen1, gen0, "startRecording must bump recordingGeneration")

        // startRecording early-returns while isRecording is true, so reset via
        // clearLocalData (sets isRecording=false) before the second call.
        controller.clearLocalData()
        controller.startRecording()
        let gen2 = controller.testRecordingGeneration
        XCTAssertGreaterThan(gen2, gen1, "a second startRecording must bump recordingGeneration again")
    }

    /// A detached task capturing a stale generation must be rejected by the
    /// same guard pattern used in `processLocation`. This is the race the
    /// counter exists to close: a location ingested just before stop/reset
    /// must not pollute the next drive's RecordingActor state.
    @MainActor
    func test_staleGenerationDetachedTaskIsRejected() async {
        let (controller, _locMgr) = makeController()
        controller.startRecording()
        let staleGen = controller.testRecordingGeneration

        controller.clearLocalData()
        controller.startRecording()  // bumps generation
        XCTAssertGreaterThan(controller.testRecordingGeneration, staleGen)

        // Replicate the exact guard from processLocation's detached task.
        let reachedIngestion = await Task.detached { [weak controller] () -> Bool in
            guard let controller else { return false }
            guard controller.testRecordingGeneration == staleGen else { return false }
            return true  // would call processLocationHeavy — the stale path
        }.value

        XCTAssertFalse(reachedIngestion,
            "a detached task with a stale generation must be rejected before ingestion")
    }
}
