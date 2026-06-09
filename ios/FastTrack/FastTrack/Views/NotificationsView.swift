import SwiftUI

struct NotificationsView: View {
    @StateObject private var manager = NotificationsManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if manager.isLoading && manager.notifications.isEmpty {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if manager.notifications.isEmpty {
                    ContentUnavailableView(
                        "No notifications yet",
                        systemImage: "bell.slash",
                        description: Text("Follow other drivers to get notified when they hit a personal best.")
                    )
                } else {
                    List {
                        ForEach(manager.notifications) { n in
                            NotificationRow(notification: n)
                                .onTapGesture {
                                    Task { await manager.markRead(n) }
                                }
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Notifications")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Mark all read") {
                        Task { await manager.markAllRead() }
                    }
                    .disabled(manager.unreadCount == 0)
                }
            }
        }
        .task {
            await manager.refresh()
        }
    }
}

private struct NotificationRow: View {
    let notification: InAppNotification

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if let url = notification.actor?.avatarUrl, !url.isEmpty,
               let parsed = URL(string: url) {
                AsyncImage(url: parsed) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        avatarPlaceholder
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                avatarPlaceholder.frame(width: 36, height: 36)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(notification.message)
                    .font(.subheadline)
                    .fontWeight(notification.readAt == nil ? .semibold : .regular)
                    .foregroundColor(.primary)
                Text(notification.createdAt, style: .relative)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            if notification.readAt == nil {
                Circle()
                    .fill(Color.blue)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle().fill(Color.blue.opacity(0.2))
            Text(notification.actor?.username.first.map(String.init) ?? "?")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.blue)
        }
    }
}
