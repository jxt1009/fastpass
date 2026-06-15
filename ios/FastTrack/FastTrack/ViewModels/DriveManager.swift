import Foundation
import CoreLocation
import Combine
import UIKit

@MainActor
final class DriveManager: ObservableObject {
    let recordingController: DriveRecordingController
    let liveActivityCoordinator: LiveActivityCoordinator
    let drivePoller: DrivePoller

    @Published var isRecording = false
    @Published var currentDrive: Drive? {
        didSet { if currentDrive == nil { recordingStartTime = nil } }
    }
    @Published var drives: [Drive] = []
    @Published var isLoadingDrives = true
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var recordingStartTime: Date?
    @Published var lastError: APIError?
    @Published var userAchievements: [UserAchievement] = []
    @Published var achievementsCatalog: [AchievementCatalogEntry] = []
    @Published var isLoadingAchievements = false
    @Published var currentGForce: Double = 0
    private let authManager: AuthManager
    private let profileManager: ProfileManager
    private let settings: AppSettings
    private let apiService: DriveAPI
    private let carStatsManager: CarStatsManager
    private let achievementManager: AchievementManager
    private var cancellables = Set<AnyCancellable>()

    init(
        authManager: AuthManager,
        profileManager: ProfileManager,
        settings: AppSettings,
        apiService: DriveAPI,
        carStatsManager: CarStatsManager,
        achievementManager: AchievementManager
    ) {
        self.authManager = authManager
        self.profileManager = profileManager
        self.settings = settings
        self.apiService = apiService
        self.carStatsManager = carStatsManager
        self.achievementManager = achievementManager

        let recordingController = DriveRecordingController(
            authManager: authManager,
            profileManager: profileManager,
            settings: settings,
            apiService: apiService,
            carStatsManager: carStatsManager
        )
        self.recordingController = recordingController

        let liveActivityCoordinator = LiveActivityCoordinator()
        self.liveActivityCoordinator = liveActivityCoordinator

        let drivePoller = DrivePoller(
            apiService: apiService,
            carStatsManager: carStatsManager
        )
        self.drivePoller = drivePoller

        recordingController.$isRecording
            .assign(to: &$isRecording)
        recordingController.$currentDrive
            .assign(to: &$currentDrive)
        recordingController.$routeCoordinates
            .assign(to: &$routeCoordinates)
        recordingController.$recordingStartTime
            .assign(to: &$recordingStartTime)
        recordingController.$lastError
            .assign(to: &$lastError)
        recordingController.$currentGForce
            .assign(to: &$currentGForce)

        drivePoller.$drives
            .assign(to: &$drives)
        drivePoller.$isLoadingDrives
            .assign(to: &$isLoadingDrives)
    }

    static let inFlightFilePrefix = "in_flight_drive_"

    func inFlightTempFileURL(for drive: Drive, in directory: URL = FileManager.default.temporaryDirectory) -> URL {
        recordingController.inFlightTempFileURL(for: drive, in: directory)
    }

    func recoverPendingDrives(in directory: URL = FileManager.default.temporaryDirectory) async {
        await drivePoller.recoverPendingDrives(in: directory)
    }

    func processHeading(course: Double, speed: Double, timestamp: Date) async -> (left: Int, right: Int, lanes: Int)? {
        await recordingController.processHeading(course: course, speed: speed, timestamp: timestamp)
    }

    var recordingLocations: [CLLocation] {
        get { recordingController.recordingLocations }
        set { recordingController.recordingLocations = newValue }
    }

    func setLocationManager(_ manager: LocationManager) {
        recordingController.setLocationManager(manager)
    }

    // MARK: - Recording control

    func startRecording() {
        recordingController.startRecording()
        liveActivityCoordinator.startLiveActivity(recordingStartTime: recordingController.recordingStartTime)
    }

    @MainActor
    func stopRecording() async {
        await recordingController.stopRecording()
        liveActivityCoordinator.endLiveActivity()
        if let savedDrive = recordingController.currentDrive {
            carStatsManager.updateStats(for: savedDrive)
        }
        await refreshAchievementsFromServer()
    }

    func dismissLastError() {
        recordingController.dismissLastError()
    }

    // MARK: - API

    func fetchDrives() {
        drivePoller.fetchDrives()
    }

    @MainActor
    func deleteDrive(id: Int) async throws {
        // Capture the drive before deleting for stale-file tracking.
        let deletedDrive = drives.first(where: { $0.id == id })

        do {
            try await apiService.deleteDrive(id: id)
        } catch let error as APIError {
            if case .serverError(404) = error { }
            else { throw error }
        }
        drives.removeAll { $0.id == id }
        carStatsManager.rebuildStats(from: drives)

        if let drive = deletedDrive {
            drivePoller.noteDriveDeleted(userID: drive.userID, startTime: drive.startTime)
        }

        await refreshAchievementsFromServer()
    }

    @MainActor
    func restoreDrive(_ drive: Drive) async {
        do {
            _ = try await apiService.createDrive(drive)
            drives.insert(drive, at: 0)
            carStatsManager.rebuildStats(from: drives)
        } catch {
            await ToastManager.shared.show(ToastMessage(text: "Couldn't restore drive: \(error.diagnosticDescription)"))
        }
    }

    // MARK: - Achievements

    func refreshAchievementsFromServer() async {
        await MainActor.run { self.isLoadingAchievements = true }
        do {
            let resp = try await apiService.fetchMyAchievements()
            await MainActor.run {
                self.userAchievements = resp.unlocked
                self.achievementsCatalog = resp.catalog
                self.isLoadingAchievements = false
                self.achievementManager.applyServerUnlocks(
                    resp.unlocked,
                    catalog: resp.catalog
                )
            }
        } catch {
            await MainActor.run { self.isLoadingAchievements = false }
        }
    }

    var pb060DriveId: Int? {
        if let sub6 = userAchievements.first(where: { $0.achievementId == "sub_6_club" }),
           let driveId = sub6.sourceDriveId {
            return driveId
        }
        if let sub5 = userAchievements.first(where: { $0.achievementId == "sub_5_club" }),
           let driveId = sub5.sourceDriveId {
            return driveId
        }
        let recorded = drives.compactMap { drive -> (Drive, Double)? in
            guard let t = drive.best060Time, t > 0 else { return nil }
            return (drive, t)
        }
        guard let minTime = recorded.map(\.1).min() else { return nil }
        let matches = recorded.filter { $0.1 == minTime }.map(\.0)
        return matches.max(by: { $0.startTime < $1.startTime })?.id
    }

    var pbTopSpeedDriveId: Int? {
        if let s150 = userAchievements.first(where: { $0.achievementId == "speed_150" }),
           let driveId = s150.sourceDriveId {
            return driveId
        }
        if let s100 = userAchievements.first(where: { $0.achievementId == "speed_100" }),
           let driveId = s100.sourceDriveId {
            return driveId
        }
        let maxSpeed = drives.map(\.maxSpeed).max() ?? 0
        guard maxSpeed > 0 else { return nil }
        let matches = drives.filter { $0.maxSpeed == maxSpeed }
        return matches.max(by: { $0.startTime < $1.startTime })?.id
    }

    func startPolling() {
        drivePoller.startPolling()
    }

    func stopPolling() {
        drivePoller.stopPolling()
    }

    func clearLocalData() {
        recordingController.clearLocalData()
        drivePoller.stopPolling()
        drivePoller.clearDrives()
        userAchievements = []
        achievementsCatalog = []
    }
}

extension DriveManager {
    static func forTesting(apiService: DriveAPI) -> DriveManager {
        let realAPI = APIService()
        let authMgr = AuthManager(apiService: realAPI)
        realAPI.authManager = authMgr
        return DriveManager(
            authManager: authMgr,
            profileManager: ProfileManager(apiService: realAPI),
            settings: AppSettings(apiService: realAPI),
            apiService: apiService,
            carStatsManager: CarStatsManager(apiService: realAPI),
            achievementManager: AchievementManager()
        )
    }

    static func preview() -> DriveManager {
        let apiService = APIService()
        let authManager = AuthManager(apiService: apiService)
        apiService.authManager = authManager
        let m = DriveManager(
            authManager: authManager,
            profileManager: ProfileManager(apiService: apiService),
            settings: AppSettings(apiService: apiService),
            apiService: apiService,
            carStatsManager: CarStatsManager(apiService: apiService),
            achievementManager: AchievementManager()
        )
        m.drives = [Drive.example]
        return m
    }
}
