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
        headingWindow = nil; lastTurnOrLaneTime = nil
        lastBrakeTime = nil; zeroStart = nil

        locationManager?.startUpdatingLocation()

        currentDrive = Drive(
            id: nil,
            userID: AuthManager.shared.getUser()?.id ?? 0,
            startTime: Date(), endTime: Date(),
            startLatitude: 0, startLongitude: 0,
            endLatitude: 0, endLongitude: 0,
            distance: 0, duration: 0,
            maxSpeed: 0, minSpeed: 0, avgSpeed: 0,
            routeData: nil,
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
                    self.currentDrive = nil
                    self.recordingStartTime = nil
                }
            } catch {
                print("Failed to save drive: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - Location processing

    private func processLocation(_ location: CLLocation) {
        let speed = max(location.speed, 0)
        let ts = location.timestamp

        recordingLocations.append(location)
        routeCoordinates.append(location.coordinate)
        speedReadings.append(speed)

        let speedMph = speed * 2.23694

        // Stopped time
        if speedMph < 1.0 {
            if stoppedSince == nil { stoppedSince = ts }
        } else if let start = stoppedSince {
            totalStoppedTime += ts.timeIntervalSince(start)
            stoppedSince = nil
        }

        // Accel / Decel / G-Force (needs at least 2 points)
        if recordingLocations.count >= 2 {
            let prev = recordingLocations[recordingLocations.count - 2]
            let dt = ts.timeIntervalSince(prev.timestamp)
            let prevSpeed = max(prev.speed, 0)

            if dt > 0 && dt < 5 {
                let accel = (speed - prevSpeed) / dt

                if accel > maxAcceleration { maxAcceleration = accel }
                if -accel > maxDeceleration { maxDeceleration = -accel }

                // Brake event (decel > 2.5 m/s², 3-second debounce)
                if accel < -2.5 {
                    let gap = lastBrakeTime.map { ts.timeIntervalSince($0) } ?? 100
                    if gap > 3 { brakeEvents += 1; lastBrakeTime = ts }
                }

                // Lateral G from centripetal acceleration
                var latAccel = 0.0
                if location.course >= 0 && prev.course >= 0 && speed > 1 {
                    var dh = location.course - prev.course
                    if dh > 180 { dh -= 360 }
                    if dh < -180 { dh += 360 }
                    let omega = (dh * .pi / 180) / dt  // rad/s
                    latAccel = speed * omega             // centripetal a = v·ω
                }

                let lonG = accel / 9.81
                let latG = abs(latAccel) / 9.81
                let totalG = (lonG * lonG + latG * latG).squareRoot()
                if totalG > peakGForce { peakGForce = totalG }
                if latG > 0.15 && speed > topCornerSpeed { topCornerSpeed = speed }
            }
        }

        // 0-60 mph timing
        if speedMph < 5 {
            zeroStart = ts
            best060Active = false
        } else if speedMph >= 60, let start = zeroStart, !best060Active {
            let elapsed = ts.timeIntervalSince(start)
            if elapsed < 30 {  // sanity
                if best060Time == nil || elapsed < best060Time! { best060Time = elapsed }
            }
            best060Active = true
            zeroStart = nil
        }

        // Turns & lane changes
        if location.course >= 0 && speed > 2.2 {
            processHeading(course: location.course, speed: speed, timestamp: ts)
        } else if speed < 0.5 {
            headingWindow = nil
        }

        updateCurrentDrive()
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
