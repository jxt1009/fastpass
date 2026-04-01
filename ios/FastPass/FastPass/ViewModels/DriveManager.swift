import Foundation
import CoreLocation
import Combine

class DriveManager: ObservableObject {
    @Published var isRecording = false
    @Published var currentDrive: Drive?
    @Published var drives: [Drive] = []
    
    private var locationManager: LocationManager?
    private var cancellables = Set<AnyCancellable>()
    private var recordingStartTime: Date?
    private var recordingLocations: [CLLocation] = []
    private var speedReadings: [Double] = []
    
    func setLocationManager(_ manager: LocationManager) {
        self.locationManager = manager
        
        // Subscribe to location updates when recording
        manager.$currentLocation
            .sink { [weak self] location in
                guard let self = self, self.isRecording, let location = location else { return }
                self.recordingLocations.append(location)
                self.speedReadings.append(location.speed >= 0 ? location.speed : 0)
                self.updateCurrentDrive()
            }
            .store(in: &cancellables)
    }
    
    func startRecording() {
        guard !isRecording else { return }
        
        isRecording = true
        recordingStartTime = Date()
        recordingLocations = []
        speedReadings = []
        
        locationManager?.startUpdatingLocation()
        
        // Initialize current drive
        currentDrive = Drive(
            id: nil,
            userID: 0, // Will be set by backend
            startTime: Date(),
            endTime: Date(),
            startLatitude: 0,
            startLongitude: 0,
            endLatitude: 0,
            endLongitude: 0,
            distance: 0,
            duration: 0,
            maxSpeed: 0,
            avgSpeed: 0,
            routeData: nil
        )
    }
    
    func stopRecording() {
        guard isRecording else { return }
        
        isRecording = false
        locationManager?.stopUpdatingLocation()
        
        // Finalize drive
        if var drive = currentDrive, !recordingLocations.isEmpty {
            drive.endTime = Date()
            
            // Save drive to backend
            Task {
                do {
                    let savedDrive = try await APIService.shared.createDrive(drive)
                    await MainActor.run {
                        self.drives.insert(savedDrive, at: 0)
                        self.currentDrive = nil
                    }
                } catch {
                    print("Failed to save drive: \(error.localizedDescription)")
                    // TODO: Queue for retry or save locally
                }
            }
        }
    }
    
    private func updateCurrentDrive() {
        guard var drive = currentDrive else { return }
        guard !recordingLocations.isEmpty else { return }
        
        let startLocation = recordingLocations.first!
        let endLocation = recordingLocations.last!
        
        // Update locations
        drive.startLatitude = startLocation.coordinate.latitude
        drive.startLongitude = startLocation.coordinate.longitude
        drive.endLatitude = endLocation.coordinate.latitude
        drive.endLongitude = endLocation.coordinate.longitude
        
        // Calculate total distance
        var totalDistance: Double = 0
        for i in 1..<recordingLocations.count {
            totalDistance += recordingLocations[i-1].distance(from: recordingLocations[i])
        }
        drive.distance = totalDistance
        
        // Calculate duration
        if let startTime = recordingStartTime {
            drive.duration = Date().timeIntervalSince(startTime)
        }
        
        // Calculate max and avg speed
        if !speedReadings.isEmpty {
            drive.maxSpeed = speedReadings.max() ?? 0
            drive.avgSpeed = speedReadings.reduce(0, +) / Double(speedReadings.count)
        }
        
        currentDrive = drive
    }
    
    func fetchDrives() {
        Task {
            do {
                let fetchedDrives = try await APIService.shared.fetchDrives()
                await MainActor.run {
                    self.drives = fetchedDrives
                }
            } catch {
                print("Failed to fetch drives: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Preview Helpers

extension LocationManager {
    static func preview() -> LocationManager {
        let manager = LocationManager()
        manager.currentSpeed = 25.0 // ~56 mph for preview
        return manager
    }
}

extension DriveManager {
    static func preview() -> DriveManager {
        let manager = DriveManager()
        manager.drives = [Drive.example]
        return manager
    }
}
