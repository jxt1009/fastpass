import Foundation
import SwiftUI
import Combine

// MARK: - Achievement Types

enum AchievementCategory: String, CaseIterable, Codable {
    case speed = "Speed"
    case distance = "Distance"
    case consistency = "Consistency"
    case performance = "Performance"
    case milestone = "Milestone"
    case special = "Special"
    
    var icon: String {
        switch self {
        case .speed: return "speedometer"
        case .distance: return "map"
        case .consistency: return "target"
        case .performance: return "bolt"
        case .milestone: return "flag"
        case .special: return "star"
        }
    }
    
    var color: Color {
        switch self {
        case .speed: return .red
        case .distance: return .blue
        case .consistency: return .green
        case .performance: return .orange
        case .milestone: return .purple
        case .special: return .yellow
        }
    }
}

// MARK: - Achievement Model

struct Achievement: Identifiable, Codable {
    let id: String
    let title: String
    let description: String
    let category: AchievementCategory
    let icon: String
    let requirement: AchievementRequirement
    var isUnlocked: Bool = false
    var unlockedDate: Date?
    var progress: Double = 0.0 // 0.0 to 1.0
    
    var progressText: String {
        if isUnlocked {
            return "Completed!"
        }
        return requirement.progressDescription(progress)
    }
    
    var badgeIcon: String {
        return isUnlocked ? icon : "lock.fill"
    }
    
    var badgeColor: Color {
        return isUnlocked ? category.color : .gray
    }
}

// MARK: - Achievement Requirements

struct AchievementRequirement: Codable {
    let type: RequirementType
    let value: Double
    let condition: String?
    
    func progressDescription(_ progress: Double) -> String {
        let current = Int(progress * value)
        let target = Int(value)
        
        switch type {
        case .maxSpeed:
            return "\(Int(progress * value * 2.23694))/\(Int(value * 2.23694)) mph"
        case .driveCount:
            return "\(current)/\(target) drives"
        case .totalDistance:
            return String(format: "%.0f/%.0f miles", progress * value * 0.000621371, value * 0.000621371)
        case .zeroToSixty:
            return String(format: "%.1f/%.1fs", progress > 0 ? value / progress : 0.0, value)
        case .smoothness:
            return String(format: "%.0f/%.0f%%", progress * 100, value)
        case .consecutiveDays:
            return "\(current)/\(target) days"
        }
    }
}

enum RequirementType: String, Codable, CaseIterable {
    case maxSpeed = "max_speed"
    case driveCount = "drive_count"
    case totalDistance = "total_distance"
    case zeroToSixty = "zero_to_sixty"
    case smoothness = "smoothness"
    case consecutiveDays = "consecutive_days"
}

// MARK: - Achievement Manager

class AchievementManager: ObservableObject {
    static let shared = AchievementManager()
    
    @Published var achievements: [Achievement] = []
    @Published var recentUnlocks: [Achievement] = []
    
    private let userDefaultsKey = "user_achievements_v2"
    
    private init() {
        loadAchievements()
        setupDefaultAchievements()
    }
    
    private func setupDefaultAchievements() {
        if achievements.isEmpty {
            achievements = createDefaultAchievements()
            saveAchievements()
        }
    }
    
    func updateProgress(with drives: [Drive]) {
        var hasUpdates = false
        
        for i in 0..<achievements.count {
            if !achievements[i].isUnlocked {
                let oldProgress = achievements[i].progress
                achievements[i].progress = calculateProgress(for: achievements[i], with: drives)
                
                // Check if achievement is now unlocked
                if achievements[i].progress >= 1.0 && !achievements[i].isUnlocked {
                    achievements[i].isUnlocked = true
                    achievements[i].unlockedDate = Date()
                    recentUnlocks.append(achievements[i])
                    hasUpdates = true
                }
            }
        }
        
        if hasUpdates {
            saveAchievements()
        }
    }
    
    private func calculateProgress(for achievement: Achievement, with drives: [Drive]) -> Double {
        switch achievement.requirement.type {
        case .maxSpeed:
            let maxSpeed = drives.map(\.maxSpeed).max() ?? 0
            return min(1.0, maxSpeed / achievement.requirement.value)
            
        case .driveCount:
            let filteredDrives: [Drive]
            if let condition = achievement.requirement.condition {
                filteredDrives = filterDrives(drives, for: condition)
            } else {
                filteredDrives = drives
            }
            return min(1.0, Double(filteredDrives.count) / achievement.requirement.value)
            
        case .totalDistance:
            let totalDistance = drives.reduce(0) { $0 + $1.distance }
            return min(1.0, totalDistance / achievement.requirement.value)
            
        case .zeroToSixty:
            // Would calculate from performance metrics
            // For now, using placeholder
            return 0.0
            
        case .smoothness:
            // Would calculate from performance metrics
            return 0.0
            
        case .consecutiveDays:
            let consecutive = calculateConsecutiveDays(from: drives)
            return min(1.0, Double(consecutive) / achievement.requirement.value)
        }
    }
    
    private func filterDrives(_ drives: [Drive], for condition: String) -> [Drive] {
        let calendar = Calendar.current
        
        return drives.filter { drive in
            switch condition {
            case "weekend":
                let weekday = calendar.component(.weekday, from: drive.startTime)
                return weekday == 1 || weekday == 7 // Sunday = 1, Saturday = 7
                
            case "after_midnight":
                let hour = calendar.component(.hour, from: drive.startTime)
                return hour >= 0 && hour < 6 // 12 AM to 6 AM
                
            default:
                return false
            }
        }
    }
    
    private func calculateConsecutiveDays(from drives: [Drive]) -> Int {
        let sortedDrives = drives.sorted { $0.startTime < $1.startTime }
        guard !sortedDrives.isEmpty else { return 0 }
        
        let calendar = Calendar.current
        var consecutiveDays = 1
        var maxConsecutive = 1
        
        for i in 1..<sortedDrives.count {
            let prevDate = calendar.startOfDay(for: sortedDrives[i-1].startTime)
            let currentDate = calendar.startOfDay(for: sortedDrives[i].startTime)
            
            if calendar.dateComponents([.day], from: prevDate, to: currentDate).day == 1 {
                consecutiveDays += 1
                maxConsecutive = max(maxConsecutive, consecutiveDays)
            } else {
                consecutiveDays = 1
            }
        }
        
        return maxConsecutive
    }
    
    private func loadAchievements() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([Achievement].self, from: data) {
            achievements = decoded
        }
    }
    
    private func saveAchievements() {
        if let data = try? JSONEncoder().encode(achievements) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }
    
    var unlockedAchievements: [Achievement] {
        achievements.filter(\.isUnlocked)
    }
    
    var lockedAchievements: [Achievement] {
        achievements.filter { !$0.isUnlocked }
    }
    
    func clearRecentUnlocks() {
        recentUnlocks.removeAll()
    }
}

// MARK: - Default Achievements

extension AchievementManager {
    private func createDefaultAchievements() -> [Achievement] {
        return [
            // Speed Achievements
            Achievement(
                id: "first_drive",
                title: "First Drive",
                description: "Complete your first recorded drive",
                category: .milestone,
                icon: "car.fill",
                requirement: AchievementRequirement(type: .driveCount, value: 1, condition: nil)
            ),
            
            Achievement(
                id: "speed_50",
                title: "Half Century",
                description: "Reach 50 mph",
                category: .speed,
                icon: "gauge.with.needle",
                requirement: AchievementRequirement(type: .maxSpeed, value: 22.352, condition: nil) // 50 mph in m/s
            ),
            
            Achievement(
                id: "speed_100",
                title: "Century Club",
                description: "Join the elite 100 mph club",
                category: .speed,
                icon: "speedometer",
                requirement: AchievementRequirement(type: .maxSpeed, value: 44.704, condition: nil) // 100 mph in m/s
            ),
            
            Achievement(
                id: "speed_150",
                title: "Speed Demon",
                description: "Hit the legendary 150 mph mark",
                category: .speed,
                icon: "bolt.fill",
                requirement: AchievementRequirement(type: .maxSpeed, value: 67.056, condition: nil) // 150 mph in m/s
            ),
            
            // Distance Achievements
            Achievement(
                id: "distance_10",
                title: "Explorer",
                description: "Drive a total of 10 miles",
                category: .distance,
                icon: "map.fill",
                requirement: AchievementRequirement(type: .totalDistance, value: 16093.4, condition: nil) // 10 miles in meters
            ),
            
            Achievement(
                id: "distance_100",
                title: "Road Warrior",
                description: "Drive a total of 100 miles",
                category: .distance,
                icon: "road.lanes",
                requirement: AchievementRequirement(type: .totalDistance, value: 160934, condition: nil) // 100 miles in meters
            ),
            
            Achievement(
                id: "distance_1000",
                title: "Mile Crusher",
                description: "Drive a total of 1,000 miles",
                category: .distance,
                icon: "globe",
                requirement: AchievementRequirement(type: .totalDistance, value: 1609344, condition: nil) // 1000 miles in meters
            ),
            
            // Milestone Achievements
            Achievement(
                id: "drives_10",
                title: "Getting Started",
                description: "Complete 10 recorded drives",
                category: .milestone,
                icon: "circle.fill",
                requirement: AchievementRequirement(type: .driveCount, value: 10, condition: nil)
            ),
            
            Achievement(
                id: "drives_50",
                title: "Experienced Driver",
                description: "Complete 50 recorded drives",
                category: .milestone,
                icon: "award.fill",
                requirement: AchievementRequirement(type: .driveCount, value: 50, condition: nil)
            ),
            
            Achievement(
                id: "drives_100",
                title: "Dedicated Tracker",
                description: "Complete 100 recorded drives",
                category: .milestone,
                icon: "checkmark.circle.fill",
                requirement: AchievementRequirement(type: .driveCount, value: 100, condition: nil)
            ),
            
            // Consistency Achievements
            Achievement(
                id: "streak_7",
                title: "Week Warrior",
                description: "Drive on 7 consecutive days",
                category: .consistency,
                icon: "calendar",
                requirement: AchievementRequirement(type: .consecutiveDays, value: 7, condition: nil)
            ),
            
            Achievement(
                id: "streak_30",
                title: "Monthly Master",
                description: "Drive on 30 consecutive days",
                category: .consistency,
                icon: "star.fill",
                requirement: AchievementRequirement(type: .consecutiveDays, value: 30, condition: nil)
            ),
            
            // Performance Achievements (placeholders for now)
            Achievement(
                id: "sub_6_club",
                title: "Sub-6-Second Club",
                description: "Achieve 0-60 mph in under 6 seconds",
                category: .performance,
                icon: "timer",
                requirement: AchievementRequirement(type: .zeroToSixty, value: 6.0, condition: nil)
            ),
            
            Achievement(
                id: "smooth_operator",
                title: "Smooth Operator",
                description: "Maintain 90% driving smoothness score",
                category: .consistency,
                icon: "waveform.path",
                requirement: AchievementRequirement(type: .smoothness, value: 90.0, condition: nil)
            ),
            
            // Special Achievements
            Achievement(
                id: "midnight_driver",
                title: "Midnight Driver",
                description: "Complete a drive after midnight",
                category: .special,
                icon: "moon.stars.fill",
                requirement: AchievementRequirement(type: .driveCount, value: 1, condition: "after_midnight")
            ),
            
            Achievement(
                id: "weekend_warrior",
                title: "Weekend Warrior",
                description: "Complete 10 drives on weekends",
                category: .special,
                icon: "sun.max",
                requirement: AchievementRequirement(type: .driveCount, value: 10, condition: "weekend")
            )
        ]
    }
}