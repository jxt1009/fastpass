import SwiftUI

/// Compact badge card with three visual states: unlocked, locked-with-progress, unknown.
struct AchievementBadgeCard: View {
    let achievement: Achievement

    var body: some View {
        switch badgeState {
        case .unlocked: unlockedCard
        case .locked:   lockedCard
        case .unknown:  unknownCard
        }
    }

    private enum BadgeState { case unlocked, locked, unknown }

    private var badgeState: BadgeState {
        if achievement.isUnlocked { return .unlocked }
        if achievement.progress > 0 { return .locked }
        return .unknown
    }

    private var accentColor: Color { achievement.category.color }

    private var unlockedCard: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(accentColor.opacity(0.20))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: achievement.icon)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentColor)
                )
            Text(achievement.title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accentColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(accentColor.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(accentColor.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }

    private var lockedCard: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 32, height: 32)
                Circle()
                    .trim(from: 0, to: max(0.0001, achievement.progress))
                    .stroke(accentColor.opacity(0.70), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 32, height: 32)
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.35))
            }
            Text(achievement.title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(white: 0.27))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text("\(Int(achievement.progress * 100))%")
                .font(.system(size: 8))
                .foregroundStyle(Color(white: 0.20))
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(Color.ftGlassCardFill)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.ftGlassCardStroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }

    private var unknownCard: some View {
        VStack(spacing: 6) {
            Text("???")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(white: 0.20))
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity, minHeight: 60)
        .background(Color.ftGlassCardFill.opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.ftGlassCardStroke.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }
}
