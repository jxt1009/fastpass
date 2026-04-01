import Foundation

// MARK: - Leaderboard Types

struct LeaderboardEntry: Identifiable, Decodable {
    let rank: Int
    let userId: Int
    let username: String
    let country: String
    let value: Double

    enum CodingKeys: String, CodingKey {
        case rank
        case userId = "user_id"
        case username
        case country
        case value
    }
}

enum LeaderboardCategory: String, CaseIterable {
    case topSpeed      = "top_speed"
    case totalDistance = "total_distance"
    case best060       = "best_060"
    case driveCount    = "drive_count"

    var displayName: String {
        switch self {
        case .topSpeed:      return "Top Speed"
        case .totalDistance: return "Distance"
        case .best060:       return "0-60"
        case .driveCount:    return "Drives"
        }
    }

    var icon: String {
        switch self {
        case .topSpeed:      return "speedometer"
        case .totalDistance: return "map.fill"
        case .best060:       return "timer"
        case .driveCount:    return "flag.fill"
        }
    }

    /// Lower value is better (used for 0-60).
    var isAscending: Bool { self == .best060 }

    func formattedValue(_ value: Double) -> String {
        switch self {
        case .topSpeed:
            return String(format: "%.0f mph", value * 2.23694)
        case .totalDistance:
            return String(format: "%.1f mi", value * 0.000621371)
        case .best060:
            return String(format: "%.2fs", value)
        case .driveCount:
            return "\(Int(value))"
        }
    }
}

enum LeaderboardScope: String, CaseIterable {
    case global    = "global"
    case following = "following"

    var displayName: String {
        switch self {
        case .global:    return "Global"
        case .following: return "Following"
        }
    }
}

enum LeaderboardPeriod: String, CaseIterable {
    case week    = "week"
    case allTime = "all_time"

    var displayName: String {
        switch self {
        case .week:    return "This Week"
        case .allTime: return "All Time"
        }
    }
}

// MARK: - Public Profile

struct PublicProfile: Decodable {
    let username: String
    let fullName: String
    let country: String
    let memberSince: Date
    let topSpeed: Double       // m/s
    let totalDistance: Double  // meters
    let driveCount: Int
    let best060Time: Double?   // seconds; nil if never reached 60 mph
    let followerCount: Int
    let followingCount: Int
    let isFollowedByMe: Bool

    enum CodingKeys: String, CodingKey {
        case username
        case fullName       = "full_name"
        case country
        case memberSince    = "member_since"
        case topSpeed       = "top_speed"
        case totalDistance  = "total_distance"
        case driveCount     = "drive_count"
        case best060Time    = "best_060_time"
        case followerCount  = "follower_count"
        case followingCount = "following_count"
        case isFollowedByMe = "is_followed_by_me"
    }
}

// MARK: - Follow list entry

struct FollowUserEntry: Identifiable, Decodable {
    let userId: Int
    let username: String
    let country: String

    var id: Int { userId }

    enum CodingKeys: String, CodingKey {
        case userId  = "user_id"
        case username
        case country
    }
}
