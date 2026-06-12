import Foundation
import SwiftUI

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
    var progress: Double = 0.0
    var sourceDriveId: Int?

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

// MARK: - Achievement Category

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

// MARK: - Achievement Requirement

struct AchievementRequirement: Codable {
    let type: RequirementType
    let value: Double
    let condition: String?

    func progressDescription(_ progress: Double) -> String {
        let current = Int(progress * value)
        let target = Int(value)
        let s = AppSettings.shared

        switch type {
        case .maxSpeed:
            return "\(Int(progress * value * s.speedFactor))/\(Int(value * s.speedFactor)) \(s.speedUnit)"
        case .driveCount:
            return "\(current)/\(target) drives"
        case .totalDistance:
            return String(format: "%.0f/%.0f %@", progress * value * s.distanceFactor, value * s.distanceFactor, s.distanceUnit)
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
