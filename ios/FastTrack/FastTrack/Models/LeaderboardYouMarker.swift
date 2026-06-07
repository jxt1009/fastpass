import Foundation

/// Pure predicate for "is this leaderboard row the current user?".
///
/// The car-centric leaderboard can show the same user up to three times
/// (once per car in their garage). The "You" marker must therefore be
/// driven by the row's `userId`, not its `carId` — a user with three cars
/// on the board should see the badge on all three of their rows.
///
/// Extracted from `SocialView` so the rule is testable in isolation.
enum LeaderboardYouMarker {
    static func isCurrentUser(entry: LeaderboardEntry, currentUserId: Int?) -> Bool {
        guard let currentUserId else { return false }
        return entry.userId == currentUserId
    }
}
