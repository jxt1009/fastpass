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

    /// Latest GPS course (degrees clockwise from true north). -1 = unavailable.
    private var currentCourse: Double = -1

    // MARK: - Init

    override init() {
        super.init()
        clManager.delegate = self
        clManager.desiredAccuracy = kCLLocationAccuracyBestForNavigation
        clManager.distanceFilter = kCLDistanceFilterNone
        clManager.pausesLocationUpdatesAutomatically = true
    }

    // MARK: - Public API

    func requestPermission() {
        clManager.requestAlwaysAuthorization()
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

    // MARK: - CoreMotion at 25 Hz

    private func startIMU() {
        guard motionManager.isDeviceMotionAvailable else {
            #if DEBUG
            print("ℹ️ Device motion unavailable")
            #endif
            return
        }
        motionManager.deviceMotionUpdateInterval = 1.0 / 25.0
        // XTrueNorthZVertical: X=North, Y=East, Z=Up — lets us project onto GPS course
        motionManager.startDeviceMotionUpdates(
            using: .xTrueNorthZVertical,
            to: .main
        ) { [weak self] motion, error in
            guard let self, let motion, error == nil else { return }
            self.handleMotionUpdate(motion)
        }
        #if DEBUG
        print("✅ IMU fusion started at 25 Hz")
        #endif
    }

    private func stopIMU() {
        motionManager.stopDeviceMotionUpdates()
    }

    private func handleMotionUpdate(_ motion: CMDeviceMotion) {
        let dt = 1.0 / 25.0
        let timestamp = measurementDate(forMotionTimestamp: motion.timestamp)
        fusion.updateCourse(currentCourse)

        // Project IMU acceleration onto travel direction
        let longG: Double
        if let projected = IMUProjector.longitudinalAccelG(from: motion, course: currentCourse) {
            longG = projected
        } else {
            // Course unknown (stationary / just started): use horizontal magnitude
            let speedTrend = rawGPSSpeed - fusion.speed
            longG = IMUProjector.fallbackAccelG(from: motion, speedTrend: speedTrend)
        }

        let wasLocked = fusion.isZeroLocked
        fusion.predict(longAccelG: longG, dt: dt)

        // Detect zero-lock break: the moment the car starts moving from a confirmed stop.
        // Publish the timestamp so DriveManager can anchor the 0-60 timer here.
        if wasLocked && !fusion.isZeroLocked {
            zeroLockBrokeAt = timestamp
        }
        publishSpeedState(at: timestamp)
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
