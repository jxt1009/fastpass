import Foundation

// MARK: - Leaderboard Types

/// One row on the leaderboard. With the car-centric backend, the same user
/// can appear on the board up to three times — once per car. The optional
/// car fields are decoded additively so an older server that doesn't emit
/// them (e.g. an interim deploy during a backend cutover) still decodes.
struct LeaderboardEntry: Identifiable, Codable {
    let rank: Int
    let userId: Int
    let username: String
    let country: String
    let avatarURL: String
    let value: Double
    let carId: String?
    let carKey: String
    let carMake: String
    let carModel: String
    let carYear: Int?
    let carTrim: String?
    let carNickname: String?
    let carPhotoUrl: String?

    /// Stable, unique id for SwiftUI ForEach — same user with multiple cars
    /// gets multiple distinct rows, so userId alone is not unique.
    var id: String { "\(userId)-\(carKey)" }

    /// "2024 BMW M3" — or "BMW M3" when year is nil. Empty when both make
    /// and model are blank.
    var carDisplayString: String {
        let parts: [String] = [
            carYear.map { String($0) } ?? "",
            carMake,
            carModel
        ].filter { !$0.isEmpty }
        return parts.joined(separator: " ")
    }

    /// "2024 BMW M3 \"Track Toy\"" — nickname appended in straight quotes
    /// when present. Falls back to `carDisplayString` when nickname is nil
    /// or blank.
    var carDisplayStringWithNickname: String {
        let base = carDisplayString
        let nick = carNickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if nick.isEmpty { return base }
        return base.isEmpty ? "\"\(nick)\"" : "\(base) \"\(nick)\""
    }

    enum CodingKeys: String, CodingKey {
        case rank
        case userId        = "user_id"
        case username
        case country
        case avatarURL     = "avatar_url"
        case value
        case carId         = "car_id"
        case carKey        = "car_key"
        case carMake       = "car_make"
        case carModel      = "car_model"
        case carYear       = "car_year"
        case carTrim       = "car_trim"
        case carNickname   = "car_nickname"
        case carPhotoUrl   = "car_photo_url"
    }
}

enum LeaderboardCategory: String, CaseIterable, Codable {
    case topSpeed      = "top_speed"
    case best060       = "best_060"
    case totalDistance = "total_distance"

    var displayName: String {
        switch self {
        case .topSpeed:      return "Top Speed"
        case .best060:       return "0-60"
        case .totalDistance: return "Total Distance"
        }
    }

    var icon: String {
        switch self {
        case .topSpeed:      return "speedometer"
        case .best060:       return "timer"
        case .totalDistance: return "map.fill"
        }
    }

    /// Lower value is better (used for 0-60).
    var isAscending: Bool { self == .best060 }

    func formattedValue(_ value: Double) -> String {
        let s = AppSettings.shared
        switch self {
        case .topSpeed:
            return s.speedDisplay(value)
        case .totalDistance:
            return s.distanceDisplay(value)
        case .best060:
            return String(format: "%.2fs", value)
        }
    }
}

enum LeaderboardScope: String, CaseIterable, Codable {
    case global    = "global"
    case following = "following"

    var displayName: String {
        switch self {
        case .global:    return "Global"
        case .following: return "Following"
        }
    }
}

enum LeaderboardPeriod: String, CaseIterable, Codable {
    case last24Hours = "last_24h"
    case last7Days   = "last_7_days"
    case allTime     = "all_time"

    var displayName: String {
        switch self {
        case .last24Hours: return "Last 24h"
        case .last7Days:   return "Last 7 Days"
        case .allTime:     return "All Time"
        }
    }
}

// MARK: - Public Profile

struct PublicProfile: Decodable {
    let username: String
    let fullName: String
    let country: String
    let avatarURL: String
    let memberSince: Date
    let topSpeed: Double
    let totalDistance: Double
    let driveCount: Int
    let best060Time: Double?
    let followerCount: Int
    let followingCount: Int
    let isFollowedByMe: Bool

    enum CodingKeys: String, CodingKey {
        case username
        case fullName       = "full_name"
        case country
        case avatarURL      = "avatar_url"
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

// MARK: - User search result

struct UserSearchResult: Identifiable, Decodable {
    let userId: Int
    let username: String
    let fullName: String
    let country: String
    let avatarURL: String
    var isFollowedByMe: Bool

    var id: Int { userId }

    enum CodingKeys: String, CodingKey {
        case userId         = "user_id"
        case username
        case fullName       = "full_name"
        case country
        case avatarURL      = "avatar_url"
        case isFollowedByMe = "is_followed_by_me"
    }
}
