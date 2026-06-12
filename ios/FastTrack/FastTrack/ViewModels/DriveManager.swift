import Foundation
import CoreLocation
import Combine
import UIKit
import ActivityKit

// Processing logic lives in DriveManager+Processing.swift
// Live Activity lifecycle lives in DriveManager+LiveActivity.swift

class DriveManager: ObservableObject {
    @Published var isRecording = false
    private var _currentDrive: Drive?
    var currentDrive: Drive? {
        get { _currentDrive }
        set {
            if let new = newValue, let old = _currentDrive, new == old {
                return
            }
            _currentDrive = newValue
            objectWillChange.send()
        }
    }
    @Published var drives: [Drive] = []
    @Published var isLoadingDrives = true  // true until first fetch completes
    @Published var lastRouteCoordinate: CLLocationCoordinate2D?
    @Published var recordingStartTime: Date?
    /// Most recent error surfaced from a failed `createDrive` upload or from
    /// a refused `startRecording` (e.g. missing location permission). Views
    /// observe this to show a banner / alert so the user is never told a
    /// drive was saved when it wasn't. Cleared on the next `startRecording`
    /// and by `dismissLastError()` once the user has acknowledged it.
    @Published var lastError: APIError?
    /// Server-authoritative achievements cache. Repopulated on profile appear,
    /// after each drive save, and on app foreground.
    @Published var userAchievements: [UserAchievement] = []
    @Published var achievementsCatalog: [AchievementCatalogEntry] = []
    @Published var isLoadingAchievements = false

    private var locationManager: LocationManager?
    private var cancellables = Set<AnyCancellable>()
    /// Bounded ring buffer of the most recent speed samples (default
    /// capacity: 1500 ≈ 1 min at 25 Hz). Used only for "recent speed"
    /// UI smoothing during the active drive. Final saved-drive stats
    /// are computed once at stop from `recordingLocations` /
    /// `richRoutePoints` (not from this buffer).
    var speedReadings: RingBuffer<Double> = RingBuffer(capacity: 1500)
    /// O(1) running min/max/avg/count over every speed sample observed
    /// during the active drive. Replaces the O(N) `reduce` / `.max` /
    /// `.min` calls in the old `updateCurrentDrive`.
    var runningSpeedStats = RunningSpeedStats()
    var latestSpeedSample: SpeedSample?
    private var pollTimer: Timer?
    /// Caps view-facing @Published re-renders at 10 Hz. Updated
    /// fields (currentMaxSpeed, currentGForce, etc.) stay current
    /// regardless; only the SwiftUI re-render is suppressed.
    let publishThrottler = PublishThrottler(minInterval: 0.1)

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
    var runningDistanceMeters: Double = 0
    var lastDistanceTickLocation: CLLocation?
    var launchTracker = LaunchTracker()
    /// The set of 0-60 attempts captured during the current drive, augmented
    /// with route-point indices and start/end coordinates at flush time.
    /// Reset by `startRecording` / `clearLocalData`.
    var attempts060: [ZeroToSixtyAttempt] = []

    // Sub-state for detection algorithms
    var lastBrakeTime: Date?

    // Live Activity
    var liveActivity: Activity<DriveActivityAttributes>?
    var lastLiveActivityUpdate: Date?
    private let authManager: AuthManager
    private let profileManager: ProfileManager
    private let settings: AppSettings
    private let apiService: DriveAPI
    private let carStatsManager: CarStatsManager

    init(
        authManager: AuthManager = .shared,
        profileManager: ProfileManager = .shared,
        settings: AppSettings = .shared,
        apiService: DriveAPI = APIService.shared,
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
        manager.driveManager = self
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
        // Clear any prior upload failure so a new recording doesn't show a
        // stale error from the previous drive.
        lastError = nil

        // First time the user actually starts a drive, escalate to Always
        // authorization. We deliberately do this on Start (not on launch) so
        // the prompt is contextual — by the time the user sees it, they have
        // already chosen to record a drive. If they had previously granted
        // only WhenInUse, this fires the system upgrade prompt.
        locationManager?.requestAlwaysIfNeeded()

        // If we still don't have Always authorization, refuse to start so
        // we don't silently produce a 0-distance drive (startUpdatingLocation
        // would no-op under denied / restricted / WhenInUse). The user can
        // grant Always in Settings and tap Start again. The
        // requestAlwaysIfNeeded() call above handles the WhenInUse →
        // .authorizedAlways upgrade.
        guard locationManager?.hasRecordingPermission == true else {
            #if DEBUG
            print("🚫 Refusing to start recording: location permission not .authorizedAlways")
            #endif
            lastError = .locationPermissionDenied
            return
        }

        #if DEBUG
        print("🚗 Starting drive recording...")
        #endif
        
        recordingStartTime = Date()  // set before isRecording so onChange sees it immediately
        isRecording = true
        richRoutePoints = []
        recordedRouteEvents = []
        speedReadings.removeAll()
        runningSpeedStats.reset()
        publishThrottler.reset()
        attempts060 = []

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
        runningDistanceMeters = 0
        lastDistanceTickLocation = nil
        lastBrakeTime = nil
        latestSpeedSample = nil

        Task { await RecordingActor.shared.resetHeading() }
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

    @MainActor
    func stopRecording() async {
        guard isRecording else { return }
        isRecording = false
        locationManager?.stopUpdatingLocation()
        endLiveActivity()
        // Re-enable normal screen sleep
        UIApplication.shared.isIdleTimerDisabled = false

        guard var drive = currentDrive, !richRoutePoints.isEmpty else { return }
        let endTime = Date()
        stoppedTimeTracker.finalize(at: endTime)
        drive.endTime = endTime

        // Backfill per-attempt route-point indices + start/end coordinates by
        // matching against the rich route. Attempts with no matching point
        // (very rare — typically only on edge cases where the active launch
        // began before a route point was recorded) get the first/last route
        // point as a fallback.
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

        // Snapshot the route inputs on main, then build the JSON off
        // main so the user's "Stop" tap doesn't hitch on serialization
        // of 600+ route points and events.
        let routeSnapshot = RouteSerializationSnapshot(
            richRoutePoints: richRoutePoints,
            recordedRouteEvents: recordedRouteEvents,
            attempts: attemptsResolved
        )
        if let json = RouteSerializer.encodeV2(snapshot: routeSnapshot) {
            drive.routeData = json
        }

        // Final extended stats
        drive.stoppedTime = stoppedTimeTracker.totalStoppedTime
        drive.leftTurns = leftTurns; drive.rightTurns = rightTurns
        drive.brakeEvents = brakeEvents; drive.laneChanges = laneChanges
        drive.maxAcceleration = maxAcceleration; drive.maxDeceleration = maxDeceleration
        drive.peakGForce = peakGForce; drive.topCornerSpeed = topCornerSpeed
        drive.best060Time = best060Time
        drive.zeroToSixtyAttempts = attemptsResolved

        // Persist the fully-built in-flight Drive to a temp file BEFORE the
        // upload attempt. The 30-second background task may expire mid-
        // upload on slow networks, killing the request before it lands. If
        // that happens (or the upload throws for any other reason), the
        // temp file is left in place so `recoverPendingDrives` can pick it
        // up on next app launch and re-upload. On upload success we delete
        // the file. The filename encodes userID + startTime so concurrent
        // drives from different accounts don't collide, and so a manual
        // scrub is identifiable.
        let inFlightURL = inFlightTempFileURL(for: drive)
        if let encoded = try? Self.driveEncoder.encode(drive) {
            do {
                try encoded.write(to: inFlightURL, options: .atomic)
            } catch {
                #if DEBUG
                print("⚠️ Failed to write in-flight drive to \(inFlightURL.lastPathComponent): \(error.localizedDescription)")
                #endif
                lastError = .invalidResponse
            }
        } else {
            #if DEBUG
            print("⚠️ Failed to encode in-flight drive JSON")
            #endif
            lastError = .invalidResponse
        }

        // Reset actor state for the next drive.
        await RecordingActor.shared.reset()

        var bgTaskID = UIBackgroundTaskIdentifier.invalid
        bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "DriveUpload") {
            // Expiration handler: the OS is about to suspend us.
            // Nothing useful we can do — just release the identifier
            // so we don't leak it.
            UIApplication.shared.endBackgroundTask(bgTaskID)
        }
        defer {
            if bgTaskID != UIBackgroundTaskIdentifier.invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
        }

        do {
            let saved = try await apiService.createDrive(drive)
            self.drives.insert(saved, at: 0)
            self.carStatsManager.updateStats(for: saved)
            self.currentDrive = nil
            self.recordingStartTime = nil
            self.attempts060 = []
            // Upload succeeded — drop the in-flight temp file so the next
            // recovery cycle doesn't re-upload this drive.
            try? FileManager.default.removeItem(at: inFlightURL)
            #if DEBUG
            print("✅ Drive saved and car stats updated")
            #endif
            await self.refreshAchievementsFromServer()
        } catch {
            #if DEBUG
            print("❌ Failed to save drive: \(error.localizedDescription)")
            #endif
            // Leave the in-flight temp file in place. The next call to
            // `recoverPendingDrives` (via `startPolling` or app launch)
            // will pick it up and re-attempt the upload.
            let surfaced = (error as? APIError) ?? APIError.invalidResponse
            self.lastError = surfaced
        }
    }

    /// Clears the published `lastError`. Call from the view when the user
    /// dismisses the error banner, or from `startRecording` so a new
    /// recording doesn't show a stale failure from the previous one.
    func dismissLastError() {
        lastError = nil
    }

    // MARK: - In-flight drive persistence (A-4)

    /// JSON encoder used to write in-flight Drives to disk. Uses iso8601
    /// dates to match the wire format the backend expects.
    private static let driveEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    /// JSON decoder used to read in-flight Drives back from disk. Uses
    /// iso8601 dates to match the encoder.
    private static let driveDecoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// Filename prefix for in-flight temp files. Recovery scans the
    /// configured directory for files matching `in_flight_drive_*.json`.
    static let inFlightFilePrefix = "in_flight_drive_"

    /// Computes the on-disk path for an in-flight Drive's temp file. The
    /// directory is injectable so tests can point at a temp dir without
    /// touching the real one.
    func inFlightTempFileURL(
        for drive: Drive,
        in directory: URL = FileManager.default.temporaryDirectory
    ) -> URL {
        let stamp = Int(drive.startTime.timeIntervalSince1970)
        return directory
            .appendingPathComponent("\(Self.inFlightFilePrefix)\(drive.userID)_\(stamp).json")
    }

    /// Scans `directory` for `in_flight_drive_*.json` files and re-attempts
    /// `createDrive` on each. On success the file is deleted; on failure
    /// it is left in place so the next call (next poll, next app launch)
    /// can try again. Called once on app start (via `startPolling`) and
    /// every 10 seconds thereafter.
    ///
    /// `directory` is injectable so tests can point at a custom temp dir.
    func recoverPendingDrives(
        in directory: URL = FileManager.default.temporaryDirectory
    ) async {
        let fm = FileManager.default
        let entries: [URL]
        do {
            entries = try fm.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil
            )
        } catch {
            #if DEBUG
            print("recoverPendingDrives: failed to list \(directory.path): \(error.localizedDescription)")
            #endif
            return
        }
        let candidates = entries.filter { url in
            url.lastPathComponent.hasPrefix(Self.inFlightFilePrefix) &&
            url.pathExtension == "json"
        }
        for url in candidates {
            await recoverOnePendingDrive(at: url)
        }
    }

    /// Recovers a single in-flight Drive file. Decodes the Drive from the
    /// JSON blob, retries `createDrive`, and deletes the file on success.
    /// If the file can't be decoded (e.g. corrupted, schema drift) we
    /// delete it anyway so it doesn't wedge future recovery cycles.
    private func recoverOnePendingDrive(at url: URL) async {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            #if DEBUG
            print("recoverPendingDrives: failed to read \(url.lastPathComponent): \(error.localizedDescription)")
            #endif
            // Unreadable — drop it so we don't loop forever.
            try? FileManager.default.removeItem(at: url)
            return
        }
        let drive: Drive
        do {
            drive = try Self.driveDecoder.decode(Drive.self, from: data)
        } catch {
            #if DEBUG
            print("recoverPendingDrives: failed to decode \(url.lastPathComponent): \(error.localizedDescription)")
            #endif
            // Corrupt / wrong schema — drop it.
            try? FileManager.default.removeItem(at: url)
            return
        }
        // Cross-user guard: a pending drive from a previous sign-in must not
        // be uploaded under the current user's JWT. Skip (don't delete) so the
        // original owner can recover it if they sign back in.
        let currentUserID = authManager.getUser()?.id ?? 0
        if drive.userID != currentUserID {
            return
        }
        do {
            let saved = try await apiService.createDrive(drive)
            // Success — insert into local list and drop the temp file.
            self.drives.insert(saved, at: 0)
            self.carStatsManager.updateStats(for: saved)
            try? FileManager.default.removeItem(at: url)
            #if DEBUG
            print("✅ recoverPendingDrives: recovered \(url.lastPathComponent)")
            #endif
        } catch {
            // Leave the file in place for next cycle. If it's a 4xx error
            // (bad data) the file will keep retrying forever; log so a
            // user can scrub the temp dir manually.
            #if DEBUG
            print("recoverPendingDrives: upload failed for \(url.lastPathComponent): \(error.localizedDescription)")
            #endif
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

    /// Deletes a drive the user owns. Network first; on success the drive is
    /// removed from the local array, per-car stats are rebuilt, and the
    /// server-authoritative achievement cache is refreshed so any
    /// `sourceDriveId` that was NULL-ed server-side is reflected locally.
    /// A 404 is treated as success: the goal state (drive gone) is already
    /// achieved, and the local array is updated unconditionally.
    @MainActor
    func deleteDrive(id: Int) async throws {
        do {
            try await apiService.deleteDrive(id: id)
        } catch let error as APIError {
            if case .serverError(404) = error { /* treat as success */ }
            else { throw error }
        }
        drives.removeAll { $0.id == id }
        CarStatsManager.shared.rebuildStats(from: drives)
        await refreshAchievementsFromServer()
    }

    /// Re-upload a previously deleted drive. Used by the Undo affordance
    /// on the delete-drive toast. Best-effort: if the server rejects the
    /// re-create (e.g. the drive's id has been hard-deleted), we treat
    /// the restore as a no-op.
    @MainActor
    func restoreDrive(_ drive: Drive) async {
        do {
            _ = try await apiService.createDrive(drive)
            drives.insert(drive, at: 0)
            CarStatsManager.shared.rebuildStats(from: drives)
        } catch {
            // Silent: a failed restore is rare and the user can re-record.
        }
    }

    // MARK: - Achievements

    /// Pulls the server-authoritative achievements list. Safe to call from
    /// any thread; results are published on the main actor.
    func refreshAchievementsFromServer() async {
        await MainActor.run { self.isLoadingAchievements = true }
        do {
            let resp = try await apiService.fetchMyAchievements()
            await MainActor.run {
                self.userAchievements = resp.unlocked
                self.achievementsCatalog = resp.catalog
                self.isLoadingAchievements = false
                // Server is source of truth — push the unlocks into the local
                // AchievementManager so the profile row can link to the
                // source drive.
                AchievementManager.shared.applyServerUnlocks(
                    resp.unlocked,
                    catalog: resp.catalog
                )
            }
        } catch {
            await MainActor.run { self.isLoadingAchievements = false }
            #if DEBUG
            print("Failed to fetch achievements: \(error.localizedDescription)")
            #endif
        }
    }

    /// The id of the drive that set the user's all-time best 0-60 mph time.
    /// Prefers the server's authoritative `sub_6_club` source drive; falls
    /// back to the most recent drive matching the all-time minimum if the
    /// user has unlocked sub_6 but the source drive is missing for any
    /// reason. Returns nil if no drive has a 0-60 recorded.
    var pb060DriveId: Int? {
        // 1) Server-authoritative sub-6 club (most reliable)
        if let sub6 = userAchievements.first(where: { $0.achievementId == "sub_6_club" }),
           let driveId = sub6.sourceDriveId {
            return driveId
        }
        // 2) Server-authoritative sub-5 club
        if let sub5 = userAchievements.first(where: { $0.achievementId == "sub_5_club" }),
           let driveId = sub5.sourceDriveId {
            return driveId
        }
        // 3) Fallback: the most recent drive whose best_060_time equals the
        //    all-time min.
        let recorded = drives.compactMap { drive -> (Drive, Double)? in
            guard let t = drive.best060Time, t > 0 else { return nil }
            return (drive, t)
        }
        guard let minTime = recorded.map(\.1).min() else { return nil }
        let matches = recorded.filter { $0.1 == minTime }.map(\.0)
        return matches.max(by: { $0.startTime < $1.startTime })?.id
    }

    /// The id of the drive that set the user's all-time best top speed.
    /// Prefers the server's authoritative `speed_150` source drive, then
    /// `speed_100` (Century Club), and finally falls back to the most
    /// recent drive with the all-time maximum top speed. Returns nil if
    /// the user has no drives, or if the all-time max speed is
    /// non-positive (incomplete/legacy drives with no meaningful speed
    /// data are never crowned as a top-speed PB).
    ///
    /// The 100 mph unlock uses the server-side id `speed_100`
    /// (`UserAchievement.achievementId` is the source of truth — the local
    /// `Achievement` catalog in `Models/Achievement.swift` uses the same
    /// id).
    var pbTopSpeedDriveId: Int? {
        // 1) Server-authoritative speed_150 (most reliable — both the
        //    source drive and the threshold are pinned by the server).
        if let s150 = userAchievements.first(where: { $0.achievementId == "speed_150" }),
           let driveId = s150.sourceDriveId {
            return driveId
        }
        // 2) Server-authoritative speed_100 (Century Club).
        if let s100 = userAchievements.first(where: { $0.achievementId == "speed_100" }),
           let driveId = s100.sourceDriveId {
            return driveId
        }
        // 3) Fallback: the most recent drive whose maxSpeed equals the
        //    all-time max (lex tie-break on startTime). Ignore
        //    non-positive maxes so incomplete/legacy drives don't get
        //    crowned (mirrors pb060DriveId's `t > 0` filter).
        let maxSpeed = drives.map(\.maxSpeed).max() ?? 0
        guard maxSpeed > 0 else { return nil }
        let matches = drives.filter { $0.maxSpeed == maxSpeed }
        return matches.max(by: { $0.startTime < $1.startTime })?.id
    }

    func startPolling() {
        guard pollTimer == nil else { return }   // already running
        fetchDrives()
        // Sweep in-flight temp files on app start (in case the user crashed
        // or background-task expired mid-upload last session) and every 10s
        // thereafter. Recovery is a no-op if there are no pending files.
        Task { [weak self] in await self?.recoverPendingDrives() }
        pollTimer = Timer.scheduledTimer(withTimeInterval: 10, repeats: true) { [weak self] _ in
            self?.fetchDrives()
            Task { [weak self] in await self?.recoverPendingDrives() }
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
        recordingStartTime = nil
        speedReadings.removeAll()
        runningSpeedStats.reset()
        publishThrottler.reset()
        latestSpeedSample = nil
        richRoutePoints = []
        recordedRouteEvents = []
        attempts060 = []
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
        runningDistanceMeters = 0
        lastDistanceTickLocation = nil
        lastBrakeTime = nil
        userAchievements = []
        achievementsCatalog = []
    }
}

// MARK: - RingBuffer

/// Fixed-capacity FIFO ring buffer. When full, the oldest element is
/// overwritten on the next `append`. Iteration is in insertion order
/// (oldest → newest). Used for the per-tick speed buffer to keep
/// memory bounded over a 10+ min drive.
struct RingBuffer<Element> {
    let capacity: Int
    private var storage: [Element?]

    init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be > 0")
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    private(set) var head: Int = 0     // index of the oldest element
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

    /// Iterate in insertion order (oldest → newest). Returns a
    /// snapshot array so callers can use the values after the buffer
    /// is mutated.
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

// MARK: - PublishThrottler

/// Caps the rate at which a main-thread caller publishes a value to
/// the view layer. The first call always publishes (so the first
/// post-start state isn't lost). Subsequent calls within
/// `minInterval` are skipped — the underlying value is updated, but
/// the SwiftUI re-render is suppressed.
///
/// Used to drop 25 Hz IMU ticks down to 10 Hz for @Published
/// view-facing fields during recording. The underlying state
/// (runningSpeedStats, currentMaxSpeed, etc.) is always up to date.
final class PublishThrottler {
    private let minInterval: TimeInterval
    private var lastPublishedAt: Date?

    init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    /// Returns `true` if the caller should publish now, `false` if
    /// the publish should be skipped (the value will be re-published
    /// on the next call outside the window).
    func shouldPublish(now: Date = Date()) -> Bool {
        if let last = lastPublishedAt, now.timeIntervalSince(last) < minInterval {
            return false
        }
        lastPublishedAt = now
        return true
    }

    func reset() { lastPublishedAt = nil }
}

// MARK: - Preview Helper

extension DriveManager {
    static func preview() -> DriveManager {
        let m = DriveManager()
        m.drives = [Drive.example]
        return m
    }
}

