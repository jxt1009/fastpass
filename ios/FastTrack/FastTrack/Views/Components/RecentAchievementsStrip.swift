import SwiftUI

/// A horizontal scroll of the user's most recently unlocked achievements.
/// Designed to sit directly under the profile header so achievements are
/// above the fold on iPhone 15 Pro-class devices.
///
/// The "View All" affordance stays in the card; tapping a single tile
/// deep-links to the achievement's `sourceDriveId` when available. The
/// same component is reused by the in-app notification feed (Phase 3,
/// Track H) to render "X just hit sub-6" celebrations.
struct RecentAchievementsStrip: View {
    @ObservedObject var achievementManager: AchievementManager
    @ObservedObject var driveManager: DriveManager
    let maxCount: Int

    init(achievementManager: AchievementManager = .shared,
         driveManager: DriveManager,
         maxCount: Int = 5) {
        self.achievementManager = achievementManager
        self.driveManager = driveManager
        self.maxCount = maxCount
    }

    private var recent: [Achievement] {
        RecentAchievementsStripLogic.recentUnlocks(
            from: achievementManager.achievements,
            maxCount: maxCount
        )
    }

    var body: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Achievements")
                        .font(.title3)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                    Spacer()
                    NavigationLink(destination: AchievementsView()) {
                        Text("View All")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.ftBlue)
                    }
                }

                if recent.isEmpty {
                    Text("Complete a drive to start unlocking achievements")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 6)
                } else {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(recent, id: \.id) { achievement in
                                NavigationLink {
                                    destination(for: achievement)
                                } label: {
                                    RecentAchievementCard(achievement: achievement)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for achievement: Achievement) -> some View {
        switch RecentAchievementsStripLogic.resolveSourceDrive(
            for: achievement,
            in: driveManager.drives
        ) {
        case .local(let drive):
            DriveDetailView(drive: drive)
        case .remote(let driveId):
            RemoteDriveDetailLoader(driveId: driveId)
        case .none:
            AchievementsView()
        }
    }
}

// MARK: - Card

/// A single horizontal-scroll tile for `RecentAchievementsStrip`. Kept
/// as a separate view so it can be reused by the notification feed
/// (Phase 3, Track H) without bringing the strip's chrome along.
struct RecentAchievementCard: View {
    let achievement: Achievement

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: achievement.icon)
                .font(.system(size: 40))
                .foregroundColor(achievement.category.color)
                .frame(maxWidth: .infinity, alignment: .leading)
            Text(achievement.title)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
                .lineLimit(1)
            Text(achievement.description)
                .font(.caption)
                .foregroundColor(.secondary)
                .lineLimit(1)
        }
        .frame(width: 160, height: 110, alignment: .leading)
        .padding(10)
        .background(achievement.category.color.opacity(0.12))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(achievement.category.color.opacity(0.35), lineWidth: 1)
        )
        .cornerRadius(10)
    }
}

// MARK: - Pure helpers (testable)

/// Pure, view-free helpers used by `RecentAchievementsStrip` and exercised
/// directly from the unit-test target so the recent-unlocks ordering and
/// source-drive resolution can be regression-guarded without a SwiftUI
/// snapshot harness.
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
