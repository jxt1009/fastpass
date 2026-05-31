import Foundation
import CoreLocation
import Combine
import UIKit
import ActivityKit

// Processing logic lives in DriveManager+Processing.swift
// Live Activity lifecycle lives in DriveManager+LiveActivity.swift

class DriveManager: ObservableObject {
    @Published var isRecording = false
    @Published var currentDrive: Drive?
    @Published var drives: [Drive] = []
    @Published var isLoadingDrives = true  // true until first fetch completes
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var recordingStartTime: Date?

    private var locationManager: LocationManager?
    private var cancellables = Set<AnyCancellable>()
    var recordingLocations: [CLLocation] = []
    var speedReadings: [Double] = []
    var latestSpeedSample: SpeedSample?
    private var pollTimer: Timer?

    // Rich route data: each point stores speed+timestamp alongside lat/lng
    var richRoutePoints: [(lat: Double, lng: Double, speed: Double, ts: Double)] = []
    // Event locations for map markers
    var recordedRouteEvents: [(type: String, lat: Double, lng: Double, ts: Double)] = []

    // Extended tracking state
    var stoppedTimeTracker = StoppedTimeTracker()
    var leftTurns: Int = 0
    var rightTurns: Int = 0
    var brakeEvents: Int = 0
    var laneChanges: Int = 0
    var maxAcceleration: Double = 0
    var maxDeceleration: Double = 0
    var peakGForce: Double = 0
    @Published var currentGForce: Double = 0  // Live value for UI / Live Activity updates
    var topCornerSpeed: Double = 0
    var best060Time: Double?
    var currentMaxSpeed: Double = 0  // m/s for real-time UI updates
    var launchTracker = LaunchTracker()

    // Sub-state for detection algorithms
    var headingWindow: (course: Double, time: Date)?
    var lastTurnOrLaneTime: Date?
    var lastBrakeTime: Date?
    /// Rolling 10-second heading history used to detect sustained curves/ramps.
    var headingHistory: [(course: Double, time: Date)] = []

    // Live Activity
    var liveActivity: Activity<DriveActivityAttributes>?
    private let authManager: AuthManager
    private let profileManager: ProfileManager
    private let settings: AppSettings
    private let apiService: APIService
    private let carStatsManager: CarStatsManager

    init(
        authManager: AuthManager = .shared,
        profileManager: ProfileManager = .shared,
        settings: AppSettings = .shared,
        apiService: APIService = .shared,
        carStatsManager: CarStatsManager = .shared
    ) {
        self.authManager = authManager
        self.profileManager = profileManager
        self.settings = settings
        self.apiService = apiService
        self.carStatsManager = carStatsManager
    }

    func setLocationManager(_ manager: LocationManager) {
        locationManager = manager
        manager.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                guard let self, self.isRecording else { return }
                self.processLocation(location)
            }
            .store(in: &cancellables)

        manager.$currentSpeedSample
            .compactMap { $0 }
            .sink { [weak self] sample in
                guard let self, self.isRecording else { return }
                self.processSpeedSample(sample)
            }
            .store(in: &cancellables)
    }

    // MARK: - Recording control

    func startRecording() {
        guard !isRecording else { return }
        #if DEBUG
        print("🚗 Starting drive recording...")
        #endif
        
        recordingStartTime = Date()  // set before isRecording so onChange sees it immediately
        isRecording = true
        recordingLocations = []
        routeCoordinates = []
        richRoutePoints = []
        recordedRouteEvents = []
        speedReadings = []

        #if DEBUG
        print("⏰ Recording start time: \(recordingStartTime!)")
        #endif

        // Reset extended stats
        stoppedTimeTracker.reset()
        leftTurns = 0; rightTurns = 0
        brakeEvents = 0; laneChanges = 0
        maxAcceleration = 0; maxDeceleration = 0
        peakGForce = 0; topCornerSpeed = 0
        best060Time = nil
        launchTracker.reset()
        currentMaxSpeed = 0  // Reset max speed for new recording
        headingWindow = nil; lastTurnOrLaneTime = nil
        lastBrakeTime = nil
        latestSpeedSample = nil
        headingHistory = []

        locationManager?.startUpdatingLocation()
        #if DEBUG
        print("📍 Location manager started")
        #endif
        #if DEBUG
        print("🔒 Location authorization: \(locationManager?.authorizationStatus.rawValue ?? -1)")
        #endif

        // Keep screen on while recording if the setting is enabled
        if settings.keepScreenOn {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        // Get selected car from profile, with fallbacks
        let profile = profileManager.profile
        var selectedCar = profile?.selectedCar
        
        // If no car is selected but garage has cars, select the first one
        if selectedCar == nil, let firstCar = profile?.garage.first {
            selectedCar = firstCar
            // Update profile to remember this selection
            if var updatedProfile = profile {
                updatedProfile.selectedCarId = firstCar.id
                profileManager.saveProfile(updatedProfile)
            }
        }
        
        // If still no car, create a placeholder to avoid "Unknown Car"
        if selectedCar == nil {
            selectedCar = UserCar(make: "Unknown", model: "Vehicle", year: nil, trim: "", nickname: "")
        }
        
        #if DEBUG
        print("📱 Starting recording with car: \(selectedCar?.displayString ?? "No car")")
        #endif

        currentDrive = Drive(
            id: nil,
            userID: authManager.getUser()?.id ?? 0,
            startTime: Date(), endTime: Date(),
            startLatitude: 0, startLongitude: 0,
            endLatitude: 0, endLongitude: 0,
            distance: 0, duration: 0,
            maxSpeed: 0, minSpeed: 0, avgSpeed: 0,
            routeData: nil,
            carId: selectedCar?.id,
            carMake: selectedCar?.make,
            carModel: selectedCar?.model,
            carYear: selectedCar?.year,
            carTrim: selectedCar?.trim,
            carNickname: selectedCar?.nickname,
            stoppedTime: 0, leftTurns: 0, rightTurns: 0,
            brakeEvents: 0, laneChanges: 0,
            maxAcceleration: 0, maxDeceleration: 0,
            peakGForce: 0, topCornerSpeed: 0,
            best060Time: nil
        )
        startLiveActivity()
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        locationManager?.stopUpdatingLocation()
        endLiveActivity()
        // Re-enable normal screen sleep
        UIApplication.shared.isIdleTimerDisabled = false

        guard var drive = currentDrive, !recordingLocations.isEmpty else { return }
        let endTime = Date()
        stoppedTimeTracker.finalize(at: endTime)
        drive.endTime = endTime

        // Serialize route as v2 format: {v:2, points:[{lat,lng,speed,ts}], events:[{type,lat,lng,ts}]}
        let pointDicts = richRoutePoints.map { p -> [String: Any] in
            ["lat": p.lat, "lng": p.lng, "speed": p.speed, "ts": p.ts]
        }
        let eventDicts = recordedRouteEvents.map { e -> [String: Any] in
            ["type": e.type, "lat": e.lat, "lng": e.lng, "ts": e.ts]
        }
        let routePayload: [String: Any] = ["v": 2, "points": pointDicts, "events": eventDicts]
        if let data = try? JSONSerialization.data(withJSONObject: routePayload),
           let json = String(data: data, encoding: .utf8) {
            drive.routeData = json
        }

        // Final extended stats
        drive.stoppedTime = stoppedTimeTracker.totalStoppedTime
        drive.leftTurns = leftTurns; drive.rightTurns = rightTurns
        drive.brakeEvents = brakeEvents; drive.laneChanges = laneChanges
        drive.maxAcceleration = maxAcceleration; drive.maxDeceleration = maxDeceleration
        drive.peakGForce = peakGForce; drive.topCornerSpeed = topCornerSpeed
        drive.best060Time = best060Time

        Task {
            do {
                let saved = try await apiService.createDrive(drive)
                await MainActor.run {
                    self.drives.insert(saved, at: 0)
                    // Update car statistics
                    self.carStatsManager.updateStats(for: saved)
                    self.currentDrive = nil
                    self.recordingStartTime = nil
                    #if DEBUG
                    print("✅ Drive saved and car stats updated")
                    #endif
                }
            } catch {
                #if DEBUG
                print("❌ Failed to save drive: \(error.localizedDescription)")
                #endif
            }
        }
    }

    // MARK: - API

    func fetchDrives() {
        Task {
            do {
                let fetched = try await apiService.fetchDrives()
                await MainActor.run {
                    self.drives = fetched
                    self.isLoadingDrives = false
                }
            } catch {
                await MainActor.run { self.isLoadingDrives = false }
                #if DEBUG
                print("Failed to fetch drives: \(error.localizedDescription)")
                #endif
            }
        }
    }

    func startPolling() {
        guard pollTimer == nil else { return }   // already running
        fetchDrives()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.fetchDrives()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
    }

    @MainActor
    func clearLocalData() {
        stopPolling()
        isRecording = false
        currentDrive = nil
        drives = []
        isLoadingDrives = false
        routeCoordinates = []
        recordingStartTime = nil
        recordingLocations = []
        speedReadings = []
        latestSpeedSample = nil
        richRoutePoints = []
        recordedRouteEvents = []
        stoppedTimeTracker.reset()
        leftTurns = 0
        rightTurns = 0
        brakeEvents = 0
        laneChanges = 0
        maxAcceleration = 0
        maxDeceleration = 0
        peakGForce = 0
        currentGForce = 0
        topCornerSpeed = 0
        best060Time = nil
        launchTracker.reset()
        currentMaxSpeed = 0
        headingWindow = nil
        lastTurnOrLaneTime = nil
        lastBrakeTime = nil
        headingHistory = []
    }
}

// MARK: - Preview Helper

extension DriveManager {
    static func preview() -> DriveManager {
        let m = DriveManager()
        m.drives = [Drive.example]
        return m
    }
}

