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
                    Text(NotificationsManager.badgeLabel(forUnreadCount: manager.unreadCount))
                        .font(.caption2.weight(.bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.ftRed))
                        .offset(x: 8, y: -4)
                }
            }
            .accessibilityLabel("Notifications")
            .accessibilityValue("\(manager.unreadCount) unread")
    }
}
