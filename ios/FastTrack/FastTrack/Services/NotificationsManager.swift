import Foundation
import Combine
import UIKit

final class NotificationsManager: ObservableObject {
    static let shared = NotificationsManager()

    @Published private(set) var notifications: [InAppNotification] = []
    @Published private(set) var unreadCount: Int = 0
    @Published private(set) var isLoading: Bool = false

    private var pollingTask: Task<Void, Never>?
    private var nextCursor: String?

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
        do {
            let count = try await APIService.shared.fetchUnreadNotificationCount()
            await MainActor.run { self.unreadCount = count }
        } catch {
            // Silent: bell badge is a soft signal.
        }
    }

    /// Fetches the full notifications list (first page).
    func refresh() async {
        await MainActor.run { self.isLoading = true }
        defer {
            Task { @MainActor in self.isLoading = false }
        }
        do {
            let resp = try await APIService.shared.fetchNotifications(cursor: nil, limit: 50)
            await MainActor.run {
                self.notifications = resp.notifications
                self.unreadCount = resp.unreadCount
                self.nextCursor = resp.nextCursor
            }
        } catch {
            // Silent on first failure; bell badge is the primary signal.
        }
    }

    /// Loads the next page using the cursor. No-op when exhausted.
    func loadMore() async {
        guard let cursor = nextCursor else { return }
        do {
            let resp = try await APIService.shared.fetchNotifications(cursor: cursor, limit: 50)
            await MainActor.run {
                self.notifications.append(contentsOf: resp.notifications)
                self.unreadCount = resp.unreadCount
                self.nextCursor = resp.nextCursor
            }
        } catch {
            // Silent: pagination is best-effort.
        }
    }

    func markRead(_ notification: InAppNotification) async {
        do {
            try await APIService.shared.markNotificationRead(id: notification.id)
            await refreshUnreadCount()
        } catch {
            // Silent: read state is best-effort.
        }
    }

    func markAllRead() async {
        do {
            try await APIService.shared.markAllNotificationsRead()
            await MainActor.run { self.unreadCount = 0 }
        } catch {
            // Silent: read state is best-effort.
        }
    }

    /// "9+" cap for the bell badge. Pure helper so the view can stay
    /// declarative and so the cap behavior is unit-testable.
    static func badgeLabel(forUnreadCount count: Int) -> String {
        count > 9 ? "9+" : "\(count)"
    }
}
