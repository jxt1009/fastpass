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
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined

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

        #if !targetEnvironment(simulator)
        if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") != nil {
            clManager.allowsBackgroundLocationUpdates = true
            clManager.pausesLocationUpdatesAutomatically = false
            print("✅ Background location updates enabled")
        } else {
            print("ℹ️ Background location not configured – foreground only")
        }
        #else
        print("ℹ️ Simulator: background location disabled")
        #endif
    }

    // MARK: - Public API

    func requestPermission() {
        clManager.requestAlwaysAuthorization()
    }

    func startUpdatingLocation() {
        clManager.startUpdatingLocation()
        startIMU()
    }

    func stopUpdatingLocation() {
        clManager.stopUpdatingLocation()
        stopIMU()
        fusion.reset()
    }

    // MARK: - CoreMotion at 25 Hz

    private func startIMU() {
        guard motionManager.isDeviceMotionAvailable else {
            print("ℹ️ Device motion unavailable")
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
        print("✅ IMU fusion started at 25 Hz")
    }

    private func stopIMU() {
        motionManager.stopDeviceMotionUpdates()
    }

    private func handleMotionUpdate(_ motion: CMDeviceMotion) {
        let dt = 1.0 / 25.0
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

        fusion.predict(longAccelG: longG, dt: dt)

        // Publish fused speed
        let fused = fusion.speed
        if abs(fused - currentSpeed) > 0.01 {
            currentSpeed = fused
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationManager: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        currentCourse = location.course  // -1 if invalid

        guard location.speed >= 0 else { return }

        rawGPSSpeed = location.speed
        speedAccuracy = location.speedAccuracy  // m/s std dev (iOS 10+)

        // Feed GPS into Kalman filter
        fusion.update(gpsSpeed: location.speed, gpsSpeedAccuracy: location.speedAccuracy)
        currentSpeed = fusion.speed
    }

    func locationManager(_ manager: CLLocationManager,
                         didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async { self.authorizationStatus = status }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
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
        return m
    }
}
