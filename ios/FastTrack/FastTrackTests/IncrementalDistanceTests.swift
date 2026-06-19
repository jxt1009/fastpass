import XCTest
import CoreLocation
@testable import FastTrack

final class IncrementalDistanceTests: XCTestCase {

    func test_incrementalDistanceMatchesFullSweep() {
        var coords: [CLLocationCoordinate2D] = []
        for i in 0..<10 {
            coords.append(CLLocationCoordinate2D(latitude: 37.0 + Double(i) * 0.0009, longitude: -122.0))
        }
        let locs = coords.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        var reference: Double = 0
        for i in 1..<locs.count {
            reference += locs[i-1].distance(from: locs[i])
        }

        var cumulative: Double = 0
        var last: CLLocation?
        for loc in locs {
            if let last = last {
                cumulative += last.distance(from: loc)
            }
            last = loc
        }
        XCTAssertEqual(cumulative, reference, accuracy: 0.5)
    }

    func test_zeroDistanceForSinglePoint() {
        let loc = CLLocation(latitude: 0, longitude: 0)
        var cumulative: Double = 0
        var last: CLLocation?
        if let last = last {
            cumulative += last.distance(from: loc)
        }
        last = loc
        XCTAssertEqual(cumulative, 0)
    }

    // MARK: - Controller-level accumulator

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
        // Keep locMgr alive: the controller holds it weakly, so it must
        // outlive the controller or startRecording()'s permission guard
        // fails and currentDrive is never created.
        return (dm.recordingController, locMgr)
    }

    /// Drives the real `DriveRecordingController` accumulator through
    /// `processLocation` and confirms `currentDrive.distance` matches a
    /// full O(n) recompute of `recordingLocations` — i.e. the incremental
    /// accumulator is wired and reset correctly.
    @MainActor
    func test_controllerAccumulatorMatchesFullRecompute() {
        let (controller, _locMgr) = makeController()
        controller.startRecording()

        let t0 = Date()
        var locs: [CLLocation] = []
        for i in 0..<200 {
            let loc = CLLocation(
                coordinate: CLLocationCoordinate2D(
                    latitude: 37.0 + Double(i) * 0.0003,
                    longitude: -122.0
                ),
                altitude: 0,
                horizontalAccuracy: 5,
                verticalAccuracy: 5,
                course: 0,
                speed: 10,
                timestamp: t0.addingTimeInterval(-Double(i) * 0.01)
            )
            locs.append(loc)
            controller.processLocation(loc)
        }

        var reference: Double = 0
        for i in 1..<locs.count {
            reference += locs[i - 1].distance(from: locs[i])
        }

        XCTAssertEqual(controller.currentDrive?.distance ?? -1, reference, accuracy: 1.0)
    }

    /// After a reset via `clearLocalData`, the accumulator must start from
    /// zero so a second drive does not inherit the first drive's distance.
    @MainActor
    func test_controllerAccumulatorResetsAfterClear() {
        let (controller, _locMgr) = makeController()
        controller.startRecording()

        let t0 = Date()
        let first = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.0, longitude: -122.0),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            course: 0, speed: 10, timestamp: t0
        )
        let second = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 37.001, longitude: -122.0),
            altitude: 0, horizontalAccuracy: 5, verticalAccuracy: 5,
            course: 0, speed: 10, timestamp: t0.addingTimeInterval(-0.5)
        )
        controller.processLocation(first)
        controller.processLocation(second)
        XCTAssertGreaterThan(controller.currentDrive?.distance ?? 0, 0)

        controller.clearLocalData()
        controller.startRecording()
        controller.processLocation(first)
        XCTAssertEqual(controller.currentDrive?.distance ?? -1, 0, accuracy: 0.001)
    }
}
