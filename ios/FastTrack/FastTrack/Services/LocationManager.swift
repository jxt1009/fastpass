import CoreLocation
import CoreMotion
import Combine

class LocationManager: NSObject, ObservableObject {

    // MARK: - Published

    /// Fused speed in m/s, updated at ~25 Hz. Use this for display and recording.
    @Published var currentSpeed: Double = 0.0
    /// Raw GPS speed in m/s (Doppler). Useful for comparison / debug.
    @Published var rawGPSSpeed: Double = 0.0
    /// GPS speed accuracy from CLLocation (m/s std dev). -1 = unavailable.
    @Published var speedAccuracy: Double = -1
    /// Rich fused speed sample, published on IMU ticks and GPS updates.
    @Published var currentSpeedSample: SpeedSample?
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    /// Fires with the timestamp of the moment zero-lock broke (car started moving from confirmed stop).
    /// Kept available for downstream consumers that care about launch transitions or debugging.
    @Published var zeroLockBrokeAt: Date? = nil

    // MARK: - Private

    private let clManager = CLLocationManager()
    private let motionManager = CMMotionManager()
    private let fusion = SpeedFusion()
    private static let imuUpdateInterval: TimeInterval = 1.0 / 100.0
    private let imuQueue: OperationQueue = {
        let q = OperationQueue()
        q.name = "com.fasttrack.location.imu"
        q.maxConcurrentOperationCount = 1
        q.qualityOfService = .userInitiated
        return q
    }()

    /// Latest GPS course (degrees clockwise from true north). -1 = unavailable.
    private var currentCourse: Double = -1

    /// Weak reference to DriveManager so heading processing can be triggered
    /// from the GPS callback path. Set externally during wiring.
    weak var driveManager: DriveManager?

    // MARK: - Init

    override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        clManager.distanceFilter = kCLDistanceFilterNone
        clManager.activityType = .automotiveNavigation
        clManager.pausesLocationUpdatesAutomatically = true
    }

    // MARK: - Public API

    /// UserDefaults key tracking whether we've ever asked the user to upgrade
    /// from WhenInUse to Always. We only ask once, and only at the moment the
    /// user actually starts a drive — not on first launch — so the upgrade
    /// prompt is contextual and Apple-HIG friendly.
    private static let hasRequestedAlwaysLocationKey = "FastTrack.hasRequestedAlwaysLocation"

    /// Request location permission, preferring WhenInUse. We only escalate to
    /// Always at the moment the user taps Start (see `requestAlwaysIfNeeded`)
    /// so we never ambush the user with the more invasive prompt on first
    /// launch.
    func requestPermission() {
        switch clManager.authorizationStatus {
         case .notDetermined:
            clManager.requestWhenInUseAuthorization()
        case .authorizedAlways, .denied, .restricted:
            break
        @unknown default:
            break
        }
    }

    /// Escalate to Always authorization if the user currently has WhenInUse
    /// and we have never asked for Always before. Sets a UserDefaults flag so
    /// the prompt only appears once per install. Wired into
    /// `DriveManager.startRecording` so the prompt fires the first time the
    /// user starts a drive, not on first launch.
    func requestAlwaysIfNeeded() {
        guard clManager.authorizationStatus == .authorizedWhenInUse else { return }
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: Self.hasRequestedAlwaysLocationKey) else { return }
        defaults.set(true, forKey: Self.hasRequestedAlwaysLocationKey)
        clManager.requestAlwaysAuthorization()
    }

    /// Whether the user has granted the Always authorization we require to
    /// record a drive. We deliberately require `.authorizedAlways` (not
    /// `.authorizedWhenInUse`) because background location is essential for
    /// drives that continue past the app being backgrounded.
    var hasRecordingPermission: Bool {
        authorizationStatus == .authorizedAlways
    }

    func startUpdatingLocation() {
        #if DEBUG
        print("📍 Starting location updates...")
        #endif
        // Only enable background updates while actively recording. We toggle the
        // flag here (not in init) so the app never claims background location
        // capability outside an active drive, which Apple HIG and App Review
        // expect.
        #if !targetEnvironment(simulator)
        if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") != nil {
            clManager.allowsBackgroundLocationUpdates = true
            clManager.pausesLocationUpdatesAutomatically = false
            #if DEBUG
            print("✅ Background location updates enabled")
            #endif
        } else {
            #if DEBUG
            print("ℹ️ Background location not configured – foreground only")
            #endif
        }
        #else
        #if DEBUG
        print("ℹ️ Simulator: background location disabled")
        #endif
        #endif
        // Start with good accuracy for faster initial fix
        clManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        clManager.startUpdatingLocation()
        
        // After a few seconds, switch to best accuracy
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.clManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
            #if DEBUG
            print("📍 Switched to high accuracy mode")
            #endif
        }
        
        startIMU()
    }

    func stopUpdatingLocation() {
        clManager.stopUpdatingLocation()
        // Drop background-location capability now that the drive has ended, and
        // restore the safe "pause automatically" default so the system can
        // suspend updates if the app is backgrounded without an active drive.
        clManager.allowsBackgroundLocationUpdates = false
        clManager.pausesLocationUpdatesAutomatically = true
        stopIMU()
        fusion.reset()
        currentSpeed = 0
        rawGPSSpeed = 0
        speedAccuracy = -1
        zeroLockBrokeAt = nil
        currentSpeedSample = nil
    }

    // MARK: - CoreMotion at 100 Hz

    private func startIMU() {
        guard motionManager.isDeviceMotionAvailable else {
            #if DEBUG
            print("ℹ️ Device motion unavailable")
            #endif
            return
        }
        motionManager.deviceMotionUpdateInterval = Self.imuUpdateInterval
        // XTrueNorthZVertical: X=North, Y=East, Z=Up — lets us project onto GPS course
        motionManager.startDeviceMotionUpdates(
            using: .xTrueNorthZVertical,
            to: imuQueue
        ) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            self.handleMotionUpdate(motion)
        }
        #if DEBUG
        print("✅ IMU fusion started at 100 Hz")
        #endif
    }

    private func stopIMU() {
        motionManager.stopDeviceMotionUpdates()
    }

    private func handleMotionUpdate(_ motion: CMDeviceMotion) {
        let dt = Self.imuUpdateInterval
        let timestamp = measurementDate(forMotionTimestamp: motion.timestamp)
        let course = currentCourse
        let rawGps = rawGPSSpeed
        fusion.updateCourse(course)

        let longG: Double
        if let projected = IMUProjector.longitudinalAccelG(from: motion, course: course) {
            longG = projected
        } else {
            let speedTrend = rawGps - fusion.speed
            longG = IMUProjector.fallbackAccelG(from: motion, speedTrend: speedTrend)
        }

        let wasLocked = fusion.isZeroLocked
        fusion.predict(longAccelG: longG, dt: dt)

        let shouldBreakLock = wasLocked && !fusion.isZeroLocked
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if shouldBreakLock {
                self.zeroLockBrokeAt = timestamp
            }
            self.publishSpeedState(at: timestamp)
        }
    }

    private func publishSpeedState(at timestamp: Date, forceSpeedUpdate: Bool = false) {
        let sample = SpeedSample(
            speed: fusion.speed,
            rawGPSSpeed: rawGPSSpeed,
            speedAccuracy: speedAccuracy,
            timestamp: timestamp,
            isZeroLocked: fusion.isZeroLocked,
            stationaryConfidence: fusion.stationaryConfidence
        )
        currentSpeedSample = sample

        let fused = sample.speed
        if forceSpeedUpdate || abs(fused - currentSpeed) > 0.03 || fused == 0 || sample.isZeroLocked {
            currentSpeed = fused
        }
    }

    private func measurementDate(forMotionTimestamp motionTimestamp: TimeInterval) -> Date {
        Date().addingTimeInterval(motionTimestamp - ProcessInfo.processInfo.systemUptime)
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        // NOTE: exact coordinates are intentionally not logged in release builds
        #if DEBUG
        print("📍 Location update: lat=\(location.coordinate.latitude), lon=\(location.coordinate.longitude), speed=\(location.speed)")
        #endif
        
        currentLocation = location
        currentCourse = location.course  // -1 if invalid

        guard location.speed >= 0 else {
            #if DEBUG
            print("⚠️ Negative speed filtered out: \(location.speed)")
            #endif
            return
        }

        rawGPSSpeed = location.speed
        speedAccuracy = location.speedAccuracy  // m/s std dev (iOS 10+)

        // Feed GPS into Kalman filter
        let wasLocked = fusion.isZeroLocked
        fusion.update(gpsSpeed: location.speed, gpsSpeedAccuracy: location.speedAccuracy)
        if wasLocked && !fusion.isZeroLocked {
            zeroLockBrokeAt = location.timestamp
        }
        publishSpeedState(at: location.timestamp, forceSpeedUpdate: true)

        // Invoke heading detection on every valid GPS sample
        if location.course >= 0, let driveManager = driveManager, driveManager.isRecording {
            Task { [weak driveManager] in
                _ = await driveManager?.processHeading(
                    course: location.course,
                    speed: max(location.speed, 0),
                    timestamp: location.timestamp
                )
            }
        }

        #if DEBUG
        print("🔄 Speed updated: GPS=\(location.speed), Fused=\(fusion.speed)")
        #endif
    }

    func locationManager(_ manager: CLLocationManager,
                         didChangeAuthorization status: CLAuthorizationStatus) {
        #if DEBUG
        print("📱 Location authorization changed to: \(status.rawValue)")
        #endif
        DispatchQueue.main.async { self.authorizationStatus = status }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        #if DEBUG
        print("Location error: \(error.localizedDescription)")
        #endif
    }
}

// MARK: - Preview Helper

extension LocationManager {
    static func preview() -> LocationManager {
        let m = LocationManager()
        m.currentSpeed = 25.0
        m.rawGPSSpeed = 25.0
        m.currentLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        m.authorizationStatus = .authorizedAlways
        m.currentSpeedSample = SpeedSample(
            speed: 25.0,
            rawGPSSpeed: 25.0,
            speedAccuracy: 0.5,
            timestamp: Date(),
            isZeroLocked: false,
            stationaryConfidence: 0
        )
        return m
    }
}
