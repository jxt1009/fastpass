import CoreLocation
import Combine

class LocationManager: NSObject, ObservableObject {
    private let locationManager = CLLocationManager()
    
    @Published var currentSpeed: Double = 0.0  // meters per second
    @Published var currentLocation: CLLocation?
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5  // Update every 5 meters
        
        // Background location updates are OPTIONAL
        // They require "Background Modes" capability with "Location updates" enabled in Xcode
        // If not configured, the app works fine but only tracks in foreground
        #if !targetEnvironment(simulator)
        // Only attempt on real device, and only if INFO.plist has UIBackgroundModes
        if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") != nil {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.pausesLocationUpdatesAutomatically = false
            print("✅ Background location updates enabled")
        } else {
            print("ℹ️ Background location not configured - app will track in foreground only")
        }
        #else
        print("ℹ️ Simulator detected - background location disabled")
        #endif
    }
    
    func requestPermission() {
        locationManager.requestAlwaysAuthorization()
    }
    
    func startUpdatingLocation() {
        locationManager.startUpdatingLocation()
    }
    
    func stopUpdatingLocation() {
        locationManager.stopUpdatingLocation()
    }
}

extension LocationManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        currentLocation = location
        
        // speed is in meters per second, -1 if invalid
        if location.speed >= 0 {
            currentSpeed = location.speed
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        DispatchQueue.main.async {
            self.authorizationStatus = status
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }
}

// MARK: - Preview Helper

extension LocationManager {
    static func preview() -> LocationManager {
        let manager = LocationManager()
        manager.currentSpeed = 25.0 // ~56 mph for preview
        manager.currentLocation = CLLocation(latitude: 37.7749, longitude: -122.4194)
        manager.authorizationStatus = .authorizedAlways
        return manager
    }
}
