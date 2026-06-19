import XCTest
import CoreLocation
@testable import FastTrack

/// Tests that `processLocation` bounds `routeCoordinates` (the live map
/// polyline) at 500 points via RDP decimation with `maxOutput: 500`, so a long
/// drive never produces an unbounded polyline regardless of GPS point count.
final class RouteDecimationBoundingTests: XCTestCase {

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
        return (dm.recordingController, locMgr)
    }

    @MainActor
    func test_routeCoordinatesCappedAt500() {
        let (controller, _locMgr) = makeController()
        controller.startRecording()

        // Feed 1000 points with zigzag latitude noise (~6.7m amplitude, above
        // the 5m RDP tolerance) so decimation can't collapse them to a handful
        // of endpoints — exercising the 500-point hard cap.
        let t0 = Date()
        for i in 0..<1000 {
            let lat = 37.0 + Double(i) * 0.00001 + (i % 2 == 0 ? 0.00006 : 0)
            let loc = CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: lat,
                    longitude: -122.0 + Double(i) * 0.00001
                ),
                altitude: 0,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: 0,
                speed: 10,
                timestamp: t0
            )
            controller.processLocation(loc)
        }

        XCTAssertGreaterThan(controller.routeCoordinates.count, 0,
            "points must be ingested into routeCoordinates")
        XCTAssertLessThanOrEqual(controller.routeCoordinates.count, 500,
            "routeCoordinates must be capped at 500 even for a long drive")
    }
}
