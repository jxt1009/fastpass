import Foundation
import CoreLocation
import Combine

class DriveManager: ObservableObject {
    @Published var isRecording = false
    @Published var currentDrive: Drive?
    @Published var drives: [Drive] = []
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var recordingStartTime: Date?

    private var locationManager: LocationManager?
    private var cancellables = Set<AnyCancellable>()
    private var recordingLocations: [CLLocation] = []
    private var speedReadings: [Double] = []
    private var pollTimer: Timer?

    // Extended tracking state
    private var stoppedSince: Date?
    private var totalStoppedTime: Double = 0
    private var leftTurns: Int = 0
    private var rightTurns: Int = 0
    private var brakeEvents: Int = 0
    private var laneChanges: Int = 0
    private var maxAcceleration: Double = 0
    private var maxDeceleration: Double = 0
    private var peakGForce: Double = 0
    private var topCornerSpeed: Double = 0
    private var best060Time: Double?
    private var currentMaxSpeed: Double = 0  // For real-time UI updates

    // Sub-state for detection algorithms
    private var headingWindow: (course: Double, time: Date)?
    private var lastTurnOrLaneTime: Date?
    private var lastBrakeTime: Date?
    private var zeroStart: Date?
    private var best060Active = false

    func setLocationManager(_ manager: LocationManager) {
        locationManager = manager
        manager.$currentLocation
            .compactMap { $0 }
            .sink { [weak self] location in
                guard let self, self.isRecording else { return }
                self.processLocation(location)
            }
            .store(in: &cancellables)
    }

    // MARK: - Recording control

    func startRecording() {
        guard !isRecording else { return }
        isRecording = true
        recordingStartTime = Date()
        recordingLocations = []
        routeCoordinates = []
        speedReadings = []

        // Reset extended stats
        stoppedSince = nil
        totalStoppedTime = 0
        leftTurns = 0; rightTurns = 0
        brakeEvents = 0; laneChanges = 0
        maxAcceleration = 0; maxDeceleration = 0
        peakGForce = 0; topCornerSpeed = 0
        best060Time = nil; best060Active = false
        currentMaxSpeed = 0  // Reset max speed for new recording
        headingWindow = nil; lastTurnOrLaneTime = nil
        lastBrakeTime = nil; zeroStart = nil

        locationManager?.startUpdatingLocation()

        // Get selected car from profile, with fallbacks
        let profile = ProfileManager.shared.profile
        var selectedCar = profile?.selectedCar
        
        // If no car is selected but garage has cars, select the first one
        if selectedCar == nil, let firstCar = profile?.garage.first {
            selectedCar = firstCar
            // Update profile to remember this selection
            if var updatedProfile = profile {
                updatedProfile.selectedCarId = firstCar.id
                ProfileManager.shared.saveProfile(updatedProfile)
            }
        }
        
        // If still no car, create a placeholder to avoid "Unknown Car"
        if selectedCar == nil {
            selectedCar = UserCar(make: "Unknown", model: "Vehicle", year: nil, trim: "", nickname: "")
        }
        
        print("📱 Starting recording with car: \(selectedCar?.displayString ?? "No car")")

        currentDrive = Drive(
            id: nil,
            userID: AuthManager.shared.getUser()?.id ?? 0,
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
    }

    func stopRecording() {
        guard isRecording else { return }
        isRecording = false
        locationManager?.stopUpdatingLocation()

        // Finalize stopped time
        if let stopStart = stoppedSince {
            totalStoppedTime += Date().timeIntervalSince(stopStart)
            stoppedSince = nil
        }

        guard var drive = currentDrive, !recordingLocations.isEmpty else { return }
        drive.endTime = Date()

        // Serialize route
        let pts = routeCoordinates.map { ["lat": $0.latitude, "lng": $0.longitude] }
        if let data = try? JSONSerialization.data(withJSONObject: pts),
           let json = String(data: data, encoding: .utf8) {
            drive.routeData = json
        }

        // Final extended stats
        drive.stoppedTime = totalStoppedTime
        drive.leftTurns = leftTurns; drive.rightTurns = rightTurns
        drive.brakeEvents = brakeEvents; drive.laneChanges = laneChanges
        drive.maxAcceleration = maxAcceleration; drive.maxDeceleration = maxDeceleration
        drive.peakGForce = peakGForce; drive.topCornerSpeed = topCornerSpeed
        drive.best060Time = best060Time

        Task {
            do {
                let saved = try await APIService.shared.createDrive(drive)
                await MainActor.run {
                    self.drives.insert(saved, at: 0)
                    // Update car statistics
                    CarStatsManager.shared.updateStats(for: saved)
                    self.currentDrive = nil
                    self.recordingStartTime = nil
                    print("✅ Drive saved and car stats updated")
                }
            } catch {
                print("❌ Failed to save drive: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Location processing

    private func processLocation(_ location: CLLocation) {
        // Basic processing on main thread for UI updates
        let speed = max(location.speed, 0)
        let speedMph = speed * 2.23694
        
        recordingLocations.append(location)
        routeCoordinates.append(location.coordinate)
        speedReadings.append(speed)
        
        // Update basic stats immediately for UI responsiveness
        if speedMph > currentMaxSpeed {
            currentMaxSpeed = speedMph
        }
        
        // Offload heavy calculations to background queue to prevent UI freezing
        Task.detached { [weak self] in
            await self?.processLocationHeavy(location, speed: speed, speedMph: speedMph)
        }
        
        // Update drive stats on main thread (lightweight)
        updateCurrentDrive()
    }
    
    private func processLocationHeavy(_ location: CLLocation, speed: Double, speedMph: Double) async {
        let ts = location.timestamp
        
        // Perform heavy calculations on background thread
        var updates: (
            stoppedTime: Double?,
            acceleration: Double?,
            deceleration: Double?,
            brakeCount: Int,
            gForce: Double?,
            cornerSpeed: Double?,
            zeroToSixtyTime: Double?,
            turnData: (left: Int, right: Int, lanes: Int)?
        ) = (nil, nil, nil, 0, nil, nil, nil, nil)
        
        // Stopped time calculation
        var newStoppedTime: Double? = nil
        if speedMph < 1.0 {
            // Will be handled on main thread
        } else if let stoppedStart = await MainActor.run(body: { self.stoppedSince }) {
            newStoppedTime = ts.timeIntervalSince(stoppedStart)
        }
        
        // Get recording data safely
        let recordingCount = await MainActor.run { self.recordingLocations.count }
        guard recordingCount >= 2 else { 
            // Apply updates on main thread
            await MainActor.run {
                if let newTime = newStoppedTime {
                    self.totalStoppedTime += newTime
                    self.stoppedSince = nil
                }
                if speedMph < 1.0 && self.stoppedSince == nil {
                    self.stoppedSince = ts
                }
            }
            return 
        }
        
        let (prev, recordingLocs) = await MainActor.run { 
            (self.recordingLocations[recordingCount - 2], Array(self.recordingLocations))
        }
        
        let dt = ts.timeIntervalSince(prev.timestamp)
        let prevSpeed = max(prev.speed, 0)
        
        // Only process if time delta is reasonable (background calculation)
        guard dt > 0 && dt < 5 else { 
            await MainActor.run {
                if let newTime = newStoppedTime {
                    self.totalStoppedTime += newTime
                    self.stoppedSince = nil
                }
                if speedMph < 1.0 && self.stoppedSince == nil {
                    self.stoppedSince = ts
                }
            }
            return 
        }
        
        // Heavy calculations on background thread
        let accel = (speed - prevSpeed) / dt
        updates.acceleration = accel > await MainActor.run({ self.maxAcceleration }) ? accel : nil
        updates.deceleration = -accel > await MainActor.run({ self.maxDeceleration }) ? -accel : nil
        
        // Brake event detection
        if accel < -2.5 {
            let lastBrake = await MainActor.run { self.lastBrakeTime }
            let gap = lastBrake.map { ts.timeIntervalSince($0) } ?? 100
            if gap > 3 {
                updates.brakeCount = 1
            }
        }
        
        // G-force calculation
        var latAccel = 0.0
        if location.course >= 0 && prev.course >= 0 && speed > 1 {
            var dh = location.course - prev.course
            if dh > 180 { dh -= 360 }
            if dh < -180 { dh += 360 }
            let omega = (dh * .pi / 180) / dt
            latAccel = speed * omega
        }
        
        let lonG = accel / 9.81
        let latG = abs(latAccel) / 9.81
        let totalG = (lonG * lonG + latG * latG).squareRoot()
        
        updates.gForce = totalG
        if latG > 0.15 && speed > await MainActor.run({ self.topCornerSpeed }) {
            updates.cornerSpeed = speed
        }
        
        // 0-60 timing
        if speedMph < 5 {
            updates.zeroToSixtyTime = -1 // Signal to reset
        } else if speedMph >= 60 {
            let zeroStart = await MainActor.run { self.zeroStart }
            let best060Active = await MainActor.run { self.best060Active }
            if let start = zeroStart, !best060Active {
                let elapsed = ts.timeIntervalSince(start)
                if elapsed < 30 {
                    let currentBest = await MainActor.run { self.best060Time }
                    if currentBest == nil || elapsed < currentBest! {
                        updates.zeroToSixtyTime = elapsed
                    }
                }
            }
        }
        
        // Turn detection (background processing)
        if location.course >= 0 && speed > 2.2 {
            updates.turnData = await processHeadingBackground(course: location.course, speed: speed, timestamp: ts)
        }
        
        // Apply all updates atomically on main thread
        await MainActor.run {
            // Stopped time
            if let newTime = newStoppedTime {
                self.totalStoppedTime += newTime
                self.stoppedSince = nil
            }
            if speedMph < 1.0 && self.stoppedSince == nil {
                self.stoppedSince = ts
            }
            
            // Performance metrics
            if let accel = updates.acceleration {
                self.maxAcceleration = accel
            }
            if let decel = updates.deceleration {
                self.maxDeceleration = decel
            }
            if updates.brakeCount > 0 {
                self.brakeEvents += 1
                self.lastBrakeTime = ts
            }
            if let gForce = updates.gForce, gForce > self.peakGForce {
                self.peakGForce = gForce
            }
            if let cornerSpeed = updates.cornerSpeed {
                self.topCornerSpeed = cornerSpeed
            }
            
            // 0-60 timing
            if let zeroSixty = updates.zeroToSixtyTime {
                if zeroSixty == -1 {
                    self.zeroStart = ts
                    self.best060Active = false
                } else {
                    self.best060Time = zeroSixty
                    self.best060Active = true
                    self.zeroStart = nil
                }
            }
            
            // Turns
            if let turnData = updates.turnData {
                self.leftTurns += turnData.left
                self.rightTurns += turnData.right
                self.laneChanges += turnData.lanes
                if turnData.left > 0 || turnData.right > 0 || turnData.lanes > 0 {
                    self.lastTurnOrLaneTime = ts
                }
            } else if speed < 0.5 {
                self.headingWindow = nil
            }
        }
    }

    private func processHeading(course: Double, speed: Double, timestamp: Date) {
        guard let window = headingWindow else {
            headingWindow = (course, timestamp)
            return
        }
        let windowAge = timestamp.timeIntervalSince(window.time)
        guard windowAge >= 2.0 else { return }

        var delta = course - window.course
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }

        let gap = lastTurnOrLaneTime.map { timestamp.timeIntervalSince($0) } ?? 100

        if abs(delta) > 35 && gap > 4 {
            if delta > 0 { rightTurns += 1 } else { leftTurns += 1 }
            lastTurnOrLaneTime = timestamp
        } else if abs(delta) >= 10 && abs(delta) <= 35 && speed > 6.7 && gap > 3 {
            laneChanges += 1
            lastTurnOrLaneTime = timestamp
        }
        headingWindow = (course, timestamp)
    }

    // MARK: - Drive stats update

    private func updateCurrentDrive() {
        guard var drive = currentDrive, !recordingLocations.isEmpty else { return }

        drive.startLatitude  = recordingLocations.first!.coordinate.latitude
        drive.startLongitude = recordingLocations.first!.coordinate.longitude
        drive.endLatitude    = recordingLocations.last!.coordinate.latitude
        drive.endLongitude   = recordingLocations.last!.coordinate.longitude

        var totalDist: Double = 0
        for i in 1..<recordingLocations.count {
            totalDist += recordingLocations[i-1].distance(from: recordingLocations[i])
        }
        drive.distance = totalDist
        if let start = recordingStartTime { drive.duration = Date().timeIntervalSince(start) }

        if !speedReadings.isEmpty {
            drive.maxSpeed = speedReadings.max() ?? 0
            drive.minSpeed = speedReadings.min() ?? 0
            drive.avgSpeed = speedReadings.reduce(0, +) / Double(speedReadings.count)
        }

        drive.stoppedTime = totalStoppedTime
        drive.leftTurns = leftTurns; drive.rightTurns = rightTurns
        drive.brakeEvents = brakeEvents; drive.laneChanges = laneChanges
        drive.maxAcceleration = maxAcceleration; drive.maxDeceleration = maxDeceleration
        drive.peakGForce = peakGForce; drive.topCornerSpeed = topCornerSpeed
        drive.best060Time = best060Time

        currentDrive = drive
    }

    // MARK: - API

    func fetchDrives() {
        Task {
            do {
                let fetched = try await APIService.shared.fetchDrives()
                await MainActor.run { self.drives = fetched }
            } catch {
                print("Failed to fetch drives: \(error.localizedDescription)")
            }
        }
    }

    func startPolling() {
        fetchDrives()
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.fetchDrives()
        }
    }

    func stopPolling() {
        pollTimer?.invalidate()
        pollTimer = nil
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
