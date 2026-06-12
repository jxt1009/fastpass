import SwiftUI

struct NotificationsBell: View {
    @ObservedObject var manager: NotificationsManager

    var body: some View {
        Image(systemName: "bell.fill")
            .font(.body)
            .foregroundColor(.primary)
            .frame(minWidth: 44, minHeight: 44)
            .overlay(alignment: .topTrailing) {
                if manager.unreadCount > 0 {
                    BadgePill(NotificationsManager.badgeLabel(forUnreadCount: manager.unreadCount), style: .count)
                        .offset(x: 8, y: -4)
                }
            }
            .accessibilityLabel("Notifications")
            .accessibilityValue("\(manager.unreadCount) unread")
    }
}
