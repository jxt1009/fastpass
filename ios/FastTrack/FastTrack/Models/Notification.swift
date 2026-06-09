import Foundation

struct NotificationActor: Codable, Equatable, Hashable {
    let id: Int
    let username: String
    let avatarUrl: String

    enum CodingKeys: String, CodingKey {
        case id
        case username
        case avatarUrl = "avatar_url"
    }
}

struct InAppNotification: Codable, Identifiable, Equatable, Hashable {
    let id: Int
    let kind: String
    let actor: NotificationActor?
    let driveId: Int?
    let achievementId: String?
    let message: String
    let readAt: Date?
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case kind
        case actor
        case driveId = "drive_id"
        case achievementId = "achievement_id"
        case message
        case readAt = "read_at"
        case createdAt = "created_at"
    }
}

struct InAppNotificationsListResponse: Codable {
    let notifications: [InAppNotification]
    let nextCursor: String?
    let unreadCount: Int

    enum CodingKeys: String, CodingKey {
        case notifications
        case nextCursor = "next_cursor"
        case unreadCount = "unread_count"
    }
}
