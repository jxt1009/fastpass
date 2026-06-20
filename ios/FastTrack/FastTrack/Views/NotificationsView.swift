import SwiftUI

struct NotificationsView: View {
    @EnvironmentObject var manager: NotificationsManager

    var body: some View {
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
                        if n.driveId != nil || n.actor != nil {
                            NavigationLink {
                                NotificationDestination(notification: n)
                            } label: {
                                NotificationRow(notification: n)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.ftGlassCardFill)
                        } else {
                            Button {
                                Task { await manager.markRead(n) }
                            } label: {
                                NotificationRow(notification: n)
                            }
                            .buttonStyle(.plain)
                            .listRowBackground(Color.ftGlassCardFill)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.ftBgGradient, ignoresSafeAreaEdges: .all)
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
        .task {
            await manager.refresh()
        }
        .onChange(of: manager.lastError) { _, newValue in
            if let newValue {
                ToastManager.shared.show(ToastMessage(text: newValue))
                manager.lastError = nil
            }
        }
    }
}

private struct NotificationRow: View, Equatable {
    let notification: InAppNotification

    var body: some View {
        UserRow(
            avatarSize: 36
        ) {
            Group {
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
                } else {
                    avatarPlaceholder
                }
            }
            .clipShape(Circle())
        } primaryContent: {
            Text(notification.message)
                .font(.subheadline)
                .fontWeight(notification.readAt == nil ? .semibold : .regular)
        } secondaryContent: {
            Text(notification.createdAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.secondary)
        } trailing: {
            if notification.readAt == nil {
                Circle()
                    .fill(Color.ftBlue)
                    .frame(width: 8, height: 8)
            }
        }
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle().fill(Color.ftBlue.opacity(0.2))
            Text(notification.actor?.username.first.map(String.init) ?? "?")
                .font(.caption)
                .fontWeight(.bold)
                .foregroundColor(.ftBlue)
        }
    }
}

// MARK: - Deep-link destination

/// Routes a notification to the relevant screen based on its payload and
/// marks it read when the destination appears. `driveId` wins over `actor`.
private struct NotificationDestination: View {
    let notification: InAppNotification
    @EnvironmentObject var manager: NotificationsManager

    var body: some View {
        Group {
            if let driveId = notification.driveId {
                RemoteDriveDetailLoader(driveId: driveId)
            } else if let actor = notification.actor {
                PublicProfileView(username: actor.username)
            } else {
                ContentUnavailableView(
                    "Notification",
                    systemImage: "bell",
                    description: Text(notification.message)
                )
            }
        }
        .task { await manager.markRead(notification) }
    }
}
