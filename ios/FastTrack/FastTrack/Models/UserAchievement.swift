import Foundation

// MARK: - Unlocked Achievement (server-authoritative)

struct UserAchievement: Codable, Identifiable, Equatable, Hashable {
    let achievementId: String
    let unlockedAt: Date
    let sourceDriveId: Int?
    let sourceKind: String
    let sourceValue: Double

    var id: String { achievementId }

    enum CodingKeys: String, CodingKey {
        case achievementId  = "achievement_id"
        case unlockedAt     = "unlocked_at"
        case sourceDriveId  = "source_drive_id"
        case sourceKind     = "source_kind"
        case sourceValue    = "source_value"
    }
}

// MARK: - Catalog Entry (server-authoritative)

struct AchievementCatalogEntry: Codable, Identifiable, Equatable, Hashable {
    let id: String
    let title: String
    let description: String
    let category: String
    let icon: String
    let requirement: AchievementRequirementPayload

    enum CodingKeys: String, CodingKey {
        case id
        case title
        case description
        case category
        case icon
        case requirement
    }
}

struct AchievementRequirementPayload: Codable, Equatable, Hashable {
    let type: String
    let value: Double
    let condition: String?
    let unit: String?

    enum CodingKeys: String, CodingKey {
        case type
        case value
        case condition
        case unit
    }
}

// MARK: - Wire response

struct UserAchievementsResponse: Codable, Equatable {
    let catalog: [AchievementCatalogEntry]
    let unlocked: [UserAchievement]
}
