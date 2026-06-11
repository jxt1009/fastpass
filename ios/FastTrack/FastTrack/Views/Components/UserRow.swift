import SwiftUI

/// Reusable avatar + name + secondary text row. Used for search results,
/// follower lists, and notifications. The trailing slot is left to the
/// caller (FollowButton, unread dot, etc.).
struct UserRow<Avatar: View, Trailing: View>: View {
    let avatarSize: CGFloat
    let primary: String
    let secondary: Text?
    let isYou: Bool
    @ViewBuilder let avatar: () -> Avatar
    @ViewBuilder let trailing: () -> Trailing

    init(
        avatarSize: CGFloat = 42,
        primary: String,
        secondary: Text? = nil,
        isYou: Bool = false,
        @ViewBuilder avatar: @escaping () -> Avatar,
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.avatarSize = avatarSize
        self.primary = primary
        self.secondary = secondary
        self.isYou = isYou
        self.avatar = avatar
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            avatar()
                .frame(width: avatarSize, height: avatarSize)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(primary).font(.body)
                    if isYou {
                        BadgePill("You", style: .you)
                    }
                }
                if let secondary {
                    secondary
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()
            trailing()
        }
        .padding(.vertical, 4)
    }
}
