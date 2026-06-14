import Foundation
import CoreLocation
import Combine
import UIKit

// MARK: - RingBuffer

struct RingBuffer<Element> {
    let capacity: Int
    private var storage: [Element?]

    init(capacity: Int) {
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    private(set) var head: Int = 0
    private(set) var count: Int = 0

    var isEmpty: Bool { count == 0 }
    var isFull: Bool { count == capacity }

    mutating func append(_ element: Element) {
        let writeIndex = (head + count) % capacity
        storage[writeIndex] = element
        if isFull {
            head = (head + 1) % capacity
        } else {
            count += 1
        }
    }

    mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        head = 0
        count = 0
    }

    func snapshot() -> [Element] {
        guard count > 0 else { return [] }
        var out: [Element] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let idx = (head + i) % capacity
            if let v = storage[idx] { out.append(v) }
        }
        return out
    }
}

final class PublishThrottler {
    private let minInterval: TimeInterval
    private var lastPublishedAt: Date?

    init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    func shouldPublish(now: Date = Date()) -> Bool {
        if let last = lastPublishedAt, now.timeIntervalSince(last) < minInterval {
            return false
        }
        lastPublishedAt = now
        return true
    }

    func reset() { lastPublishedAt = nil }
}

@MainActor
class DriveRecordingController: ObservableObject {
    @Published var isRecording = false
    @Published var currentDrive: Drive?
    @Published var routeCoordinates: [CLLocationCoordinate2D] = []
    @Published var recordingStartTime: Date?
    @Published var lastError: APIError?
    @Published var currentGForce: Double = 0

    var recordingLocations: [CLLocation] = []
    var speedReadings: RingBuffer<Double> = RingBuffer(capacity: 1500)
    var runningSpeedStats = RunningSpeedStats()
    var latestSpeedSample: SpeedSample?
    let publishThrottler = PublishThrottler(minInterval: 0.1)
    var richRoutePoints: [(lat: Double, lng: Double, speed: Double, ts: Double)] = []
    var recordedRouteEvents: [(type: String, lat: Double, lng: Double, ts: Double)] = []
    var stoppedTimeTracker = StoppedTimeTracker()
    var leftTurns: Int = 0
    var rightTurns: Int = 0
    var brakeEvents: Int = 0
    var laneChanges: Int = 0
    var maxAcceleration: Double = 0
    var maxDeceleration: Double = 0
    var peakGForce: Double = 0
    var topCornerSpeed: Double = 0
    var currentMaxSpeed: Double = 0
    var launchTracker = LaunchTracker()
    var attempts060: [ZeroToSixtyAttempt] = []
    var headingWindow: (course: Double, time: Date)?
    var lastTurnOrLaneTime: Date?
    var lastBrakeTime: Date?
    var headingHistory: [(course: Double, time: Date)] = []
    var best060Time: Double?
    var speedStream: [(TimeInterval, Double, Bool, Double)] = []
    private var lastSeenGpsAccuracy: Double = 0

    private weak var locationManager: LocationManager?
    private let authManager: AuthManager
    private let profileManager: ProfileManager
    private let settings: AppSettings
    private let apiService: DriveAPI
    private let carStatsManager: CarStatsManager
    private var cancellables = Set<AnyCancellable>()

    init(
        authManager: AuthManager,
        profileManager: ProfileManager,
        settings: AppSettings,
        apiService: DriveAPI,
        carStatsManager: CarStatsManager
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

    func startRecording() {
        guard !isRecording else { return }
        lastError = nil

        locationManager?.requestAlwaysIfNeeded()

        guard locationManager?.hasRecordingPermission == true else {
            lastError = .locationPermissionDenied
            return
        }

        recordingStartTime = Date()
        isRecording = true
        recordingLocations = []
        routeCoordinates = []
        richRoutePoints = []
        recordedRouteEvents = []
        speedReadings.removeAll()
        runningSpeedStats.reset()
        publishThrottler.reset()
        attempts060 = []
        speedStream = []

        stoppedTimeTracker.reset()
        leftTurns = 0; rightTurns = 0
        brakeEvents = 0; laneChanges = 0
        maxAcceleration = 0; maxDeceleration = 0
        peakGForce = 0; topCornerSpeed = 0
        best060Time = nil
        launchTracker.reset()
        currentMaxSpeed = 0
        headingWindow = nil; lastTurnOrLaneTime = nil
        lastBrakeTime = nil
        latestSpeedSample = nil
        headingHistory = []

        locationManager?.startUpdatingLocation()

        if settings.keepScreenOn {
            UIApplication.shared.isIdleTimerDisabled = true
        }

        let profile = profileManager.profile
        var selectedCar = profile?.selectedCar

        if selectedCar == nil, let firstCar = profile?.garage.first {
            selectedCar = firstCar
            if var updatedProfile = profile {
                updatedProfile.selectedCarId = firstCar.id
                profileManager.saveProfile(updatedProfile)
            }
        }

        if selectedCar == nil {
            selectedCar = UserCar(make: "Unknown", model: "Vehicle", year: nil, trim: "", nickname: "")
        }

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
    }

    func stopRecording() async {
        guard isRecording else { return }
        isRecording = false
        locationManager?.stopUpdatingLocation()
        UIApplication.shared.isIdleTimerDisabled = false

        guard var drive = currentDrive, !recordingLocations.isEmpty else { return }
        let endTime = Date()
        stoppedTimeTracker.finalize(at: endTime)
        drive.endTime = endTime

        let attemptsResolved: [ZeroToSixtyAttempt] = attempts060.enumerated().map { _, attempt in
            var resolved = attempt
            if let startIdx = richRoutePoints.firstIndex(where: { abs($0.ts - attempt.startTimestamp) < 0.5 }) {
                resolved.startIndex = startIdx
                resolved.startLatitude = richRoutePoints[startIdx].lat
                resolved.startLongitude = richRoutePoints[startIdx].lng
            } else if !richRoutePoints.isEmpty {
                resolved.startIndex = 0
                resolved.startLatitude = richRoutePoints[0].lat
                resolved.startLongitude = richRoutePoints[0].lng
            }
            if let endIdx = richRoutePoints.firstIndex(where: { abs($0.ts - attempt.endTimestamp) < 0.5 }) {
                resolved.endIndex = endIdx
                resolved.endLatitude = richRoutePoints[endIdx].lat
                resolved.endLongitude = richRoutePoints[endIdx].lng
            } else if let last = richRoutePoints.last {
                resolved.endIndex = richRoutePoints.count - 1
                resolved.endLatitude = last.lat
                resolved.endLongitude = last.lng
            }
            return resolved
        }

        let analyzer = LaunchAnalyzer()
        let postHocAttempts = analyzer.analyze(stream: speedStream)
        let resolvedAttempts = postHocAttempts.isEmpty ? attemptsResolved : postHocAttempts
        let bestPostHoc = resolvedAttempts.min(by: { $0.elapsedSeconds < $1.elapsedSeconds })
        drive.best060Time = bestPostHoc?.elapsedSeconds ?? best060Time
        drive.zeroToSixtyAttempts = resolvedAttempts

        let topSpeedResult = TopSpeedComputer.compute(
            speedStream: speedStream,
            gpsMaxSpeed: currentMaxSpeed,
            nearestGpsAccuracyMeters: lastSeenGpsAccuracy
        )
        drive.fusedMaxSpeed = topSpeedResult.fusedMaxSpeed
        drive.gpsMaxSpeed = topSpeedResult.gpsMaxSpeed
        drive.maxSpeed = topSpeedResult.maxSpeed

        let routeSnapshot = RouteSerializationSnapshot(
            richRoutePoints: richRoutePoints,
            recordedRouteEvents: recordedRouteEvents,
            attempts: resolvedAttempts,
            speedStream: speedStream,
            speedPeaks: []
        )
        if let json = RouteSerializer.encodeV3(snapshot: routeSnapshot) {
            drive.routeData = json
        }

        drive.stoppedTime = stoppedTimeTracker.totalStoppedTime
        drive.leftTurns = leftTurns; drive.rightTurns = rightTurns
        drive.brakeEvents = brakeEvents; drive.laneChanges = laneChanges
        drive.maxAcceleration = maxAcceleration; drive.maxDeceleration = maxDeceleration
        drive.peakGForce = peakGForce; drive.topCornerSpeed = topCornerSpeed

        let inFlightURL = inFlightTempFileURL(for: drive)
        if let encoded = try? Self.driveEncoder.encode(drive) {
            do {
                try encoded.write(to: inFlightURL, options: .atomic)
            } catch {
                lastError = .invalidResponse
            }
        } else {
            lastError = .invalidResponse
        }

        await RecordingActor.shared.reset()

        var bgTaskID = UIBackgroundTaskIdentifier.invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "DriveUpload") {
            UIApplication.shared.endBackgroundTask(bgTaskID)
        }
        defer {
            if bgTaskID != UIBackgroundTaskIdentifier.invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
        }

        do {
            let saved = try await apiService.createDrive(drive)
            currentDrive = drive
            currentDrive = nil
            recordingStartTime = nil
            attempts060 = []
            try? FileManager.default.removeItem(at: inFlightURL)
        } catch {
            let surfaced = (error as? APIError) ?? APIError.invalidResponse
            lastError = surfaced
        }
    }

    func dismissLastError() {
        lastError = nil
    }

    private static let driveEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    func inFlightTempFileURL(
        for drive: Drive,
        in directory: URL = FileManager.default.temporaryDirectory
    ) -> URL {
        let stamp = Int(drive.startTime.timeIntervalSince1970)
        return directory
            .appendingPathComponent("in_flight_drive_\(drive.userID)_\(stamp).json")
    }

    // MARK: - Location processing

    func processLocation(_ location: CLLocation) {
        let age = abs(location.timestamp.timeIntervalSinceNow)
        if age > 5.0 { return }

        let speed = routePointSpeed(for: location)
        let speedMph = speed * 2.23694

        recordingLocations.append(location)
        routeCoordinates.append(location.coordinate)
        richRoutePoints.append((
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            speed: speed,
            ts: location.timestamp.timeIntervalSince1970
        ))

        if speed > currentMaxSpeed {
            currentMaxSpeed = speed
        }

        Task.detached { [weak self] in
            await self?.processLocationHeavy(location, speed: speed, speedMph: speedMph)
        }

        updateCurrentDrive()
    }

    func processSpeedSample(_ sample: SpeedSample) {
        latestSpeedSample = sample
        speedReadings.append(sample.speed)
        runningSpeedStats.ingest(sample.speed)
        stoppedTimeTracker.ingest(sample)
        speedStream.append((sample.timestamp.timeIntervalSince1970, sample.speed, sample.isZeroLocked, sample.stationaryConfidence))
        lastSeenGpsAccuracy = sample.speedAccuracy

        if sample.speed > currentMaxSpeed {
            currentMaxSpeed = sample.speed
        }

        let priorAttemptCount = launchTracker.attempts.count
        if let newBest = launchTracker.ingest(sample) {
            best060Time = newBest
        }
        if launchTracker.attempts.count > priorAttemptCount {
            let newOnes = launchTracker.attempts[priorAttemptCount...]
            attempts060.append(contentsOf: newOnes)
        }

        guard var drive = currentDrive else { return }
        drive.stoppedTime = stoppedTimeTracker.totalStoppedTime(at: sample.timestamp)
        drive.best060Time = best060Time
        if publishThrottler.shouldPublish() {
            currentDrive = drive
        }
    }

    func routePointSpeed(for location: CLLocation) -> Double {
        guard let latestSpeedSample,
              abs(latestSpeedSample.timestamp.timeIntervalSince(location.timestamp)) <= 1.0 else {
            return max(location.speed, 0)
        }
        return latestSpeedSample.speed
    }

    func processLocationHeavy(_ location: CLLocation, speed: Double, speedMph: Double) async {
        let ts = location.timestamp
        let prevRecord = await RecordingActor.shared.previousRoutePoint()
        guard let prev = prevRecord.location else { return }
        let prevSpeed = prevRecord.speed

        let dt = ts.timeIntervalSince(prev.timestamp)
        guard dt > 0 && dt < 5 else { return }

        let speedAccuracyOK = location.speedAccuracy > 0 && location.speedAccuracy < 2.0
                           && prev.speedAccuracy > 0 && prev.speedAccuracy < 2.0

        let rawAccel = (speed - prevSpeed) / dt
        let maxPhysicalAccelMS2 = 5.0 * 9.81
        let accel = max(-maxPhysicalAccelMS2, min(maxPhysicalAccelMS2, rawAccel))

        let update = RecordingActorUpdate(
            coordinate: location.coordinate,
            speed: speed,
            timestamp: ts.timeIntervalSince1970,
            acceleration: speedAccuracyOK && accel > 0 ? accel : nil,
            deceleration: speedAccuracyOK && -accel > 0 ? -accel : nil,
            brakeDetected: accel < -2.5,
            gForce: speedAccuracyOK ? computedGForce(accel: accel, location: location, prev: prev, speed: speed, dt: dt) : nil,
            cornerSpeed: speedAccuracyOK ? speed : nil
        )
        await RecordingActor.shared.ingest(update)
    }

    func processHeading(course: Double, speed: Double, timestamp: Date) async -> (left: Int, right: Int, lanes: Int)? {
        let result = await RecordingActor.shared.ingestHeading(
            course: course,
            speed: speed,
            timestamp: timestamp.timeIntervalSince1970
        )
        if result.hasAny {
            leftTurns += result.leftTurns
            rightTurns += result.rightTurns
            laneChanges += result.laneChanges
            let totals = await RecordingActor.shared.headingTotals()
            return (totals.left, totals.right, totals.lane)
        }
        return nil
    }

    func processHeadingBackground(course: Double, speed: Double, timestamp: Date) async -> (left: Int, right: Int, lanes: Int)? {
        let window = headingWindow
        guard let window = window else {
            headingWindow = (course, timestamp)
            headingHistory.append((course, timestamp))
            return nil
        }

        let windowAge = timestamp.timeIntervalSince(window.time)
        guard windowAge >= 2.0 else { return nil }

        var delta = course - window.course
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }

        let lastTurnTime = lastTurnOrLaneTime
        let gap = lastTurnTime.map { timestamp.timeIntervalSince($0) } ?? 100

        headingHistory.append((course, timestamp))
        let cutoff = timestamp.addingTimeInterval(-10)
        headingHistory.removeAll { $0.time < cutoff }
        let inCurve = isSustainedCurve(upTo: timestamp)

        var resultLeft = 0, resultRight = 0, resultLanes = 0

        if abs(delta) > 35 && gap > 4 {
            if delta > 0 { resultRight = 1 } else { resultLeft = 1 }
        } else if abs(delta) >= 10 && abs(delta) <= 35 && speed > 6.7 && gap > 3 && !inCurve {
            resultLanes = 1
        }

        headingWindow = (course, timestamp)

        return resultLeft + resultRight + resultLanes > 0 ? (resultLeft, resultRight, resultLanes) : nil
    }

    func isSustainedCurve(upTo timestamp: Date) -> Bool {
        let windowStart = timestamp.addingTimeInterval(-8)
        let window = headingHistory.filter { $0.time >= windowStart }
        guard window.count >= 4 else { return false }

        var cumulative = 0.0
        var signs: [Double] = []
        for i in 1..<window.count {
            var d = window[i].course - window[i-1].course
            if d > 180 { d -= 360 }
            if d < -180 { d += 360 }
            if abs(d) > 0.5 {
                cumulative += abs(d)
                signs.append(d > 0 ? 1 : -1)
            }
        }
        guard cumulative > 40, signs.count >= 3 else { return false }
        let allSame = signs.allSatisfy { $0 == signs[0] }
        return allSame
    }

    func updateCurrentDrive() {
        guard var drive = currentDrive,
              let firstLoc = recordingLocations.first,
              let lastLoc  = recordingLocations.last else {
            return
        }

        drive.startLatitude  = firstLoc.coordinate.latitude
        drive.startLongitude = firstLoc.coordinate.longitude
        drive.endLatitude    = lastLoc.coordinate.latitude
        drive.endLongitude   = lastLoc.coordinate.longitude

        var totalDist: Double = 0
        for i in 1..<recordingLocations.count {
            totalDist += recordingLocations[i-1].distance(from: recordingLocations[i])
        }
        drive.distance = totalDist
        if let start = recordingStartTime {
            drive.duration = Date().timeIntervalSince(start)
        }

        if runningSpeedStats.count > 0 {
            drive.maxSpeed = runningSpeedStats.max
            drive.minSpeed = runningSpeedStats.min
            drive.avgSpeed = runningSpeedStats.avg
        }

        drive.stoppedTime = stoppedTimeTracker.totalStoppedTime(at: Date())
        drive.leftTurns = leftTurns; drive.rightTurns = rightTurns
        drive.brakeEvents = brakeEvents; drive.laneChanges = laneChanges
        drive.maxAcceleration = maxAcceleration; drive.maxDeceleration = maxDeceleration
        drive.peakGForce = peakGForce; drive.topCornerSpeed = topCornerSpeed
        drive.best060Time = best060Time

        currentDrive = drive
    }

    func clearLocalData() {
        isRecording = false
        currentDrive = nil
        routeCoordinates = []
        recordingStartTime = nil
        recordingLocations = []
        speedReadings.removeAll()
        runningSpeedStats.reset()
        publishThrottler.reset()
        latestSpeedSample = nil
        richRoutePoints = []
        recordedRouteEvents = []
        attempts060 = []
        speedStream = []
        lastSeenGpsAccuracy = 0
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

private func computedGForce(
    accel: Double,
    location: CLLocation,
    prev: CLLocation,
    speed: Double,
    dt: TimeInterval
) -> Double {
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
    return (lonG * lonG + latG * latG).squareRoot()
}
