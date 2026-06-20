import Foundation
import SwiftUI

// MARK: - Achievement Model

struct Achievement: Identifiable, Codable, Equatable {
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
    var isSecret: Bool = false

    func progressText(with settings: AppSettings) -> String {
        if isUnlocked {
            return "Completed!"
        }
        return requirement.progressDescription(progress, settings: settings)
    }

    var badgeIcon: String {
        return isUnlocked ? icon : "lock.fill"
    }

    var badgeColor: Color {
        return isUnlocked ? category.color : .gray
    }

    enum CodingKeys: String, CodingKey {
        case id, title, description, category, icon, requirement
        case isUnlocked, unlockedDate, progress, sourceDriveId, isSecret
    }

    // Custom decoder so persisted achievements that pre-date `isSecret`
    // (key absent in `user_achievements_v2` UserDefaults data) still decode
    // instead of throwing and wiping a user's unlocked state.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id            = try c.decode(String.self, forKey: .id)
        self.title         = try c.decode(String.self, forKey: .title)
        self.description   = try c.decode(String.self, forKey: .description)
        self.category      = try c.decode(AchievementCategory.self, forKey: .category)
        self.icon          = try c.decode(String.self, forKey: .icon)
        self.requirement   = try c.decode(AchievementRequirement.self, forKey: .requirement)
        self.isUnlocked    = try c.decode(Bool.self, forKey: .isUnlocked)
        self.unlockedDate  = try c.decodeIfPresent(Date.self, forKey: .unlockedDate)
        self.progress      = try c.decode(Double.self, forKey: .progress)
        self.sourceDriveId = try c.decodeIfPresent(Int.self, forKey: .sourceDriveId)
        self.isSecret      = try c.decodeIfPresent(Bool.self, forKey: .isSecret) ?? false
    }

    // Explicit memberwise init — required because `init(from:)` above
    // suppresses the synthesized memberwise init. Defaults mirror the
    // prior synthesized init so existing call sites compile unchanged.
    init(
        id: String,
        title: String,
        description: String,
        category: AchievementCategory,
        icon: String,
        requirement: AchievementRequirement,
        isUnlocked: Bool = false,
        unlockedDate: Date? = nil,
        progress: Double = 0.0,
        sourceDriveId: Int? = nil,
        isSecret: Bool = false
    ) {
        self.id            = id
        self.title         = title
        self.description   = description
        self.category      = category
        self.icon          = icon
        self.requirement   = requirement
        self.isUnlocked    = isUnlocked
        self.unlockedDate  = unlockedDate
        self.progress      = progress
        self.sourceDriveId = sourceDriveId
        self.isSecret      = isSecret
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
        case .speed: return .ftRed
        case .distance: return .ftBlue
        case .consistency: return .ftGreen
        case .performance: return .ftAmber
        case .milestone: return .purple
        case .special: return .ftGold
        }
    }
}

// MARK: - Achievement Requirement

struct AchievementRequirement: Codable, Equatable {
    let type: RequirementType
    let value: Double
    let condition: String?

    func progressDescription(_ progress: Double, settings: AppSettings) -> String {
        let current = Int(progress * value)
        let target = Int(value)
        let s = settings

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
