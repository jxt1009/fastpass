import Foundation

// MARK: - Pure helpers (testable)

/// Pure, view-free helpers for achievement sorting and source-drive resolution.
/// Used by `ProfileView` (achievementsSection) and exercised directly from the
/// unit-test target so the recent-unlocks ordering and source-drive resolution
/// can be regression-guarded without a SwiftUI snapshot harness.
enum RecentAchievementsStripLogic {

    /// The `maxCount` most recently unlocked achievements, newest first.
    /// Achievements with a nil `unlockedDate` are sorted last so the
    /// deterministic `id` ordering is preserved. When two achievements
    /// share the same `unlockedDate` (including the `nil`/`nil` case),
    /// `id` breaks the tie so the order is stable across runs and not
    /// at the mercy of `sorted`'s non-stable partitioning.
    static func recentUnlocks(from achievements: [Achievement], maxCount: Int) -> [Achievement] {
        let sorted = achievements
            .filter(\.isUnlocked)
            .sorted { lhs, rhs in
                switch (lhs.unlockedDate, rhs.unlockedDate) {
                case let (l?, r?):
                    if l != r { return l > r }
                    return lhs.id < rhs.id
                case (_?, nil):    return true
                case (nil, _?):    return false
                case (nil, nil):   return lhs.id < rhs.id
                }
            }
        return Array(sorted.prefix(maxCount))
    }

    /// Resolves the destination for an achievement tap. Local drives win
    /// over remote; achievements with no `sourceDriveId` return `.none`
    /// (the caller decides what to fall back to, e.g. `AchievementsView`).
    static func resolveSourceDrive(for achievement: Achievement, in drives: [Drive]) -> SourceDriveResolution {
        guard let driveId = achievement.sourceDriveId else { return .none }
        if let local = drives.first(where: { $0.id == driveId }) {
            return .local(local)
        }
        return .remote(driveId: driveId)
    }
}

enum SourceDriveResolution: Equatable {
    case local(Drive)
    case remote(driveId: Int)
    case none
}
