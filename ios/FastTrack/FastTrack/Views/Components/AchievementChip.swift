import SwiftUI

/// Small pill chip for achievement surfaces in Profile and Car Detail strips.
struct AchievementChip: View {
    let achievement: Achievement

    var body: some View {
        Text(achievement.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(achievement.category.color)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(achievement.category.color.opacity(0.10))
            .overlay(Capsule().stroke(achievement.category.color.opacity(0.25), lineWidth: 1))
            .clipShape(Capsule())
    }
}
