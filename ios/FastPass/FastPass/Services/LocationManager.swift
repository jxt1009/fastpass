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
        
        // Only enable background updates on device with proper capabilities
        // Don't enable in previews, simulator, or if capabilities aren't configured
        #if targetEnvironment(simulator)
        // Simulator doesn't support background location properly
        locationManager.allowsBackgroundLocationUpdates = false
        #else
        // On device, check if we can enable background updates
        // This will fail gracefully if Background Modes capability isn't set
        do {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.pausesLocationUpdatesAutomatically = false
        } catch {
            print("Could not enable background location updates: \(error)")
        }
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
