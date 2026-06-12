import SwiftUI

/// Reusable avatar + name + secondary text row. Used for search results,
/// follower lists, and notifications. The trailing slot is left to the
/// caller (FollowButton, unread dot, etc.).
///
/// The `primaryContent` and `secondaryContent` are `@ViewBuilder`
/// closures so each call site can supply its own styling (e.g. bold for
/// unread notifications, two-line secondary for fullName + country).
struct UserRow<Avatar: View, Primary: View, Secondary: View, Trailing: View>: View {
    let avatarSize: CGFloat
    let isYou: Bool
    @ViewBuilder let avatar: () -> Avatar
    @ViewBuilder let primaryContent: () -> Primary
    @ViewBuilder let secondaryContent: () -> Secondary
    @ViewBuilder let trailing: () -> Trailing

    init(
        avatarSize: CGFloat = 42,
        isYou: Bool = false,
        @ViewBuilder avatar: @escaping () -> Avatar,
        @ViewBuilder primaryContent: @escaping () -> Primary,
        @ViewBuilder secondaryContent: @escaping () -> Secondary = { EmptyView() },
        @ViewBuilder trailing: @escaping () -> Trailing
    ) {
        self.avatarSize = avatarSize
        self.isYou = isYou
        self.avatar = avatar
        self.primaryContent = primaryContent
        self.secondaryContent = secondaryContent
        self.trailing = trailing
    }

    var body: some View {
        HStack(spacing: 12) {
            avatar()
                .frame(width: avatarSize, height: avatarSize)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    primaryContent()
                    if isYou {
                        BadgePill("You", style: .you)
                    }
                }
                secondaryContent()
            }

            Spacer()
            trailing()
        }
        .padding(.vertical, 4)
    }
}
