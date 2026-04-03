import Foundation
import Combine

// MARK: - Car Statistics Model

struct CarStats: Codable {
    let carId: String
    var totalDrives: Int = 0
    var totalDistance: Double = 0  // meters
    var totalTime: Double = 0      // seconds
    var bestTopSpeed: Double = 0   // m/s
    var bestZeroToSixty: Double?   // seconds
    var avgSpeed: Double = 0       // m/s
    var bestAcceleration: Double = 0
    var bestDeceleration: Double = 0
    var bestLateralG: Double = 0
    var totalBrakeEvents: Int = 0
    var totalTurns: Int = 0
    var smoothnessScore: Double = 0
    var lastDriveDate: Date?
    
    // Computed properties
    var totalDistanceMiles: Double { totalDistance * 0.000621371 }
    var bestTopSpeedMph: Double { bestTopSpeed * 2.23694 }
    var avgSpeedMph: Double { avgSpeed * 2.23694 }
    
    var drivesPerWeek: Double {
        guard let lastDrive = lastDriveDate else { return 0 }
        let weeksSinceFirstDrive = max(1, Date().timeIntervalSince(lastDrive) / (7 * 24 * 3600))
        return Double(totalDrives) / weeksSinceFirstDrive
    }
    
    var avgTripDistance: Double {
        guard totalDrives > 0 else { return 0 }
        return totalDistanceMiles / Double(totalDrives)
    }
    
    var performanceCategory: String {
        switch bestTopSpeedMph {
        case 150...: return "Supercar"
        case 120..<150: return "Sports Car"
        case 90..<120: return "Performance"
        case 60..<90: return "Economy"
        default: return "City Car"
        }
    }
}

// MARK: - Car Statistics Manager

class CarStatsManager: ObservableObject {
    static let shared = CarStatsManager()
    
    @Published var carStats: [String: CarStats] = [:]
    
    private let userDefaultsKey = "car_stats_v1"
    
    private init() {
        loadCarStats()
    }
    
    func updateStats(for drive: Drive) {
        guard let carId = drive.carId, !carId.isEmpty else {
            print("⚠️ Drive has no car ID, skipping stats update")
            return
        }
        
        var stats = carStats[carId] ?? CarStats(carId: carId)
        
        // Update basic stats
        stats.totalDrives += 1
        stats.totalDistance += drive.distance
        stats.totalTime += drive.duration
        stats.lastDriveDate = drive.endTime
        
        // Update best performances
        if drive.maxSpeed > stats.bestTopSpeed {
            stats.bestTopSpeed = drive.maxSpeed
        }
        
        if let driveZeroSixty = drive.best060Time {
            if stats.bestZeroToSixty == nil || driveZeroSixty < stats.bestZeroToSixty! {
                stats.bestZeroToSixty = driveZeroSixty
            }
        }
        
        // Update performance metrics
        stats.bestAcceleration = max(stats.bestAcceleration, drive.maxAcceleration ?? 0)
        stats.bestDeceleration = max(stats.bestDeceleration, drive.maxDeceleration ?? 0)
        stats.bestLateralG = max(stats.bestLateralG, drive.peakGForce ?? 0)
        
        // Update aggregate stats
        stats.totalBrakeEvents += drive.brakeEvents ?? 0
        stats.totalTurns += (drive.leftTurns ?? 0) + (drive.rightTurns ?? 0)
        
        // Calculate average speed
        stats.avgSpeed = stats.totalDistance / max(1, stats.totalTime)
        
        // Calculate smoothness score (simplified)
        stats.smoothnessScore = calculateSmoothnessScore(stats)
        
        carStats[carId] = stats
        saveCarStats()
        
        print("📊 Updated stats for car \(carId): \(stats.totalDrives) drives, \(String(format: "%.1f", stats.totalDistanceMiles)) miles")
    }
    
    func getStats(for carId: String) -> CarStats? {
        return carStats[carId]
    }
    
    func getAllStats() -> [CarStats] {
        return Array(carStats.values).sorted { $0.totalDrives > $1.totalDrives }
    }
    
    func getTopPerformers() -> (fastestCar: CarStats?, mostDriven: CarStats?, bestAcceleration: CarStats?) {
        let allStats = getAllStats()
        
        let fastestCar = allStats.max { $0.bestTopSpeed < $1.bestTopSpeed }
        let mostDriven = allStats.max { $0.totalDrives < $1.totalDrives }
        let bestAcceleration = allStats.filter { $0.bestZeroToSixty != nil }
                                     .min { $0.bestZeroToSixty! < $1.bestZeroToSixty! }
        
        return (fastestCar, mostDriven, bestAcceleration)
    }
    
    func resetStats(for carId: String) {
        carStats.removeValue(forKey: carId)
        saveCarStats()
    }
    
    func resetAllStats() {
        carStats.removeAll()
        saveCarStats()
    }

    /// Rebuilds all per-car stats from scratch using the provided drive list.
    /// Call this after a drive's car assignment changes so counts stay accurate.
    func rebuildStats(from drives: [Drive]) {
        carStats.removeAll()
        for drive in drives {
            updateStats(for: drive)
        }
    }
    
    private func calculateSmoothnessScore(_ stats: CarStats) -> Double {
        // Simplified smoothness calculation based on brake events per mile
        guard stats.totalDistanceMiles > 0 else { return 100 }
        
        let brakeEventsPerMile = Double(stats.totalBrakeEvents) / stats.totalDistanceMiles
        
        // Score from 0-100, lower brake events = higher score
        switch brakeEventsPerMile {
        case 0..<0.5: return 95
        case 0.5..<1.0: return 85
        case 1.0..<2.0: return 75
        case 2.0..<3.0: return 65
        case 3.0..<5.0: return 55
        default: return 45
        }
    }
    
    private func loadCarStats() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([String: CarStats].self, from: data) {
            carStats = decoded
        }
    }

    private func saveCarStats() {
        if let encoded = try? JSONEncoder().encode(carStats) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            // Sync to server in background so data survives reinstall/device switch
            if let json = String(data: encoded, encoding: .utf8) {
                Task {
                    try? await APIService.shared.uploadCarStats(json)
                }
            }
        }
    }

    /// Restores car stats from the server. Call after sign-in or token refresh.
    func restoreFromServer() async {
        do {
            let json = try await APIService.shared.fetchCarStats()
            guard let data = json.data(using: .utf8),
                  let decoded = try? JSONDecoder().decode([String: CarStats].self, from: data),
                  !decoded.isEmpty else { return }
            await MainActor.run {
                // Merge: server wins only for cars not yet present locally
                for (carId, stats) in decoded where carStats[carId] == nil {
                    carStats[carId] = stats
                }
                // If local is empty, take everything from server
                if carStats.isEmpty { carStats = decoded }
            }
            // Persist merged result locally
            if let encoded = try? JSONEncoder().encode(carStats) {
                UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
            }
            print("✅ Car stats restored from server")
        } catch {
            print("⚠️ Could not restore car stats from server: \(error)")
        }
    }
}

// MARK: - Car Comparison

extension CarStatsManager {
    func comparePerformance(carId1: String, carId2: String) -> CarComparison? {
        guard let stats1 = carStats[carId1],
              let stats2 = carStats[carId2] else { return nil }
        
        return CarComparison(car1: stats1, car2: stats2)
    }
}

struct CarComparison {
    let car1: CarStats
    let car2: CarStats
    
    var topSpeedWinner: String {
        car1.bestTopSpeed > car2.bestTopSpeed ? car1.carId : car2.carId
    }
    
    var accelerationWinner: String? {
        guard let time1 = car1.bestZeroToSixty,
              let time2 = car2.bestZeroToSixty else { return nil }
        return time1 < time2 ? car1.carId : car2.carId
    }
    
    var smoothnessWinner: String {
        car1.smoothnessScore > car2.smoothnessScore ? car1.carId : car2.carId
    }
    
    var efficiencyWinner: String {
        // Based on average speed vs brake events
        let efficiency1 = car1.avgSpeedMph / max(1, Double(car1.totalBrakeEvents))
        let efficiency2 = car2.avgSpeedMph / max(1, Double(car2.totalBrakeEvents))
        return efficiency1 > efficiency2 ? car1.carId : car2.carId
    }
}

// MARK: - Drive Extension

extension Drive {
    func updateCarStats() {
        CarStatsManager.shared.updateStats(for: self)
    }
}