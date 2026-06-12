import Foundation
import Combine
import UIKit

final class NotificationsManager: ObservableObject {
    static let shared = NotificationsManager()

    @Published private(set) var notifications: [InAppNotification] = []
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var isLoading: Bool = false
    @Published var lastError: String?

    private var pollingTask: Task<Void, Never>?
    private var nextCursor: String?
    private var sessionToken: UUID = UUID()

    private init() {}

    /// Polls the server every 30 seconds while the app is in the foreground.
    /// Stops automatically on sign-out. Idempotent — calling start on an
    /// already-running manager cancels the previous loop and starts fresh.
    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(nanoseconds: 30_000_000_000)  // 30s
            }
        }
    }

    func stopPolling() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// Fetches the unread count (cheap). Used to keep the bell badge fresh
    /// without re-pulling the full list.
    func refreshUnreadCount() async {
        let myToken = UUID()
        await MainActor.run { self.sessionToken = myToken }
        do {
            let count = try await APIService.shared.fetchUnreadNotificationCount()
            guard await MainActor.run({ self.sessionToken == myToken }) else { return }
            await MainActor.run { self.unreadCount = count }
        } catch {
            guard await MainActor.run({ self.sessionToken == myToken }) else { return }
            await MainActor.run { self.lastError = "Couldn't refresh notification count" }
        }
    }

    /// Fetches the full notifications list (first page).
    func refresh() async {
        let myToken = UUID()
        await MainActor.run { self.sessionToken = myToken }
        await MainActor.run { self.isLoading = true }
        defer {
            Task { @MainActor in self.isLoading = false }
        }
        do {
            let resp = try await APIService.shared.fetchNotifications(cursor: nil, limit: 50)
            guard await MainActor.run({ self.sessionToken == myToken }) else { return }
            await MainActor.run {
                self.notifications = resp.notifications
                self.unreadCount = resp.unreadCount
                self.nextCursor = resp.nextCursor
            }
        } catch {
            guard await MainActor.run({ self.sessionToken == myToken }) else { return }
            await MainActor.run { self.lastError = "Couldn't load notifications" }
        }
    }

    /// Loads the next page using the cursor. No-op when exhausted.
    func loadMore() async {
        guard let cursor = nextCursor else { return }
        let myToken = UUID()
        await MainActor.run { self.sessionToken = myToken }
        do {
            let resp = try await APIService.shared.fetchNotifications(cursor: cursor, limit: 50)
            guard await MainActor.run({ self.sessionToken == myToken }) else { return }
            await MainActor.run {
                self.notifications.append(contentsOf: resp.notifications)
                self.unreadCount = resp.unreadCount
                self.nextCursor = resp.nextCursor
            }
        } catch {
            guard await MainActor.run({ self.sessionToken == myToken }) else { return }
            await MainActor.run { self.lastError = "Couldn't load older notifications" }
        }
    }

    func markRead(_ notification: InAppNotification) async {
        do {
            try await APIService.shared.markNotificationRead(id: notification.id)
            await MainActor.run {
                if let idx = self.notifications.firstIndex(where: { $0.id == notification.id }) {
                    var updated = self.notifications[idx]
                    updated = InAppNotification(
                        id: updated.id,
                        kind: updated.kind,
                        actor: updated.actor,
                        driveId: updated.driveId,
                        achievementId: updated.achievementId,
                        message: updated.message,
                        readAt: Date(),
                        createdAt: updated.createdAt
                    )
                    self.notifications[idx] = updated
                }
            }
            await refreshUnreadCount()
        } catch {
            await MainActor.run { self.lastError = "Couldn't mark notification as read" }
        }
    }

    func markAllRead() async {
        do {
            try await APIService.shared.markAllNotificationsRead()
            await MainActor.run { self.unreadCount = 0 }
        } catch {
            await MainActor.run { self.lastError = "Couldn't mark all as read" }
        }
    }

    /// Rotates the session token so any in-flight refresh will bail
    /// before writing stale state. Call from AuthManager.signOut.
    func cancelInFlight() {
        sessionToken = UUID()
    }

    /// "9+" cap for the bell badge. Pure helper so the view can stay
    /// declarative and so the cap behavior is unit-testable.
    static func badgeLabel(forUnreadCount count: Int) -> String {
        count > 9 ? "9+" : "\(count)"
    }
}
