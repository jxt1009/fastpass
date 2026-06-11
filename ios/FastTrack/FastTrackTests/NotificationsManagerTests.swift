import XCTest
@testable import FastTrack

/// Tests for the iOS in-app notification feed (Phase 3 / Track H of the
/// issue #64 plan). Covers wire decoding for `InAppNotification` and the
/// bell-badge cap helper.
final class NotificationsManagerTests: XCTestCase {

    // MARK: - Wire decoding

    /// A representative server payload must decode every documented field
    /// onto the matching Swift property. Mirrors the wire format emitted
    /// by `backend/internal/app/notifications.go`.
    func testInAppNotification_DecodesFullWireFormat() throws {
        let json = """
        {
          "id": 9001,
          "kind": "personal_best",
          "actor": {
            "id": 42,
            "username": "apexdriver",
            "avatar_url": "https://fast.toper.dev/uploads/avatars/42.jpg"
          },
          "drive_id": 7777,
          "achievement_id": "speed_150",
          "message": "@apexdriver hit a new top speed of 158.2 mph",
          "read_at": null,
          "created_at": "2026-06-07T10:15:30Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let n = try decoder.decode(InAppNotification.self, from: json)

        XCTAssertEqual(n.id, 9001)
        XCTAssertEqual(n.kind, "personal_best")
        XCTAssertEqual(n.actor?.id, 42)
        XCTAssertEqual(n.actor?.username, "apexdriver")
        XCTAssertEqual(n.actor?.avatarUrl, "https://fast.toper.dev/uploads/avatars/42.jpg")
        XCTAssertEqual(n.driveId, 7777)
        XCTAssertEqual(n.achievementId, "speed_150")
        XCTAssertEqual(n.message, "@apexdriver hit a new top speed of 158.2 mph")
        XCTAssertNil(n.readAt)
        XCTAssertNotNil(n.createdAt)
    }

    /// Optional fields (`actor`, `drive_id`, `achievement_id`, `read_at`)
    /// must decode as nil when absent so old / partial server payloads
    /// don't break the client.
    func testInAppNotification_DecodesMinimalPayload() throws {
        let json = """
        {
          "id": 1,
          "kind": "system",
          "message": "Welcome to FastTrack",
          "created_at": "2026-06-01T00:00:00Z"
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let n = try decoder.decode(InAppNotification.self, from: json)

        XCTAssertEqual(n.id, 1)
        XCTAssertEqual(n.kind, "system")
        XCTAssertNil(n.actor)
        XCTAssertNil(n.driveId)
        XCTAssertNil(n.achievementId)
        XCTAssertNil(n.readAt)
        XCTAssertEqual(n.message, "Welcome to FastTrack")
    }

    /// The list envelope (`{notifications, next_cursor, unread_count}`)
    /// must decode and expose the cursor + unread count.
    func testInAppNotificationsListResponse_Decodes() throws {
        let json = """
        {
          "notifications": [
            {
              "id": 1, "kind": "personal_best", "actor": null,
              "drive_id": null, "achievement_id": null,
              "message": "hi", "read_at": null,
              "created_at": "2026-06-07T10:15:30Z"
            }
          ],
          "next_cursor": "eyJpZCI6MTB9",
          "unread_count": 3
        }
        """.data(using: .utf8)!

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let resp = try decoder.decode(InAppNotificationsListResponse.self, from: json)
        XCTAssertEqual(resp.notifications.count, 1)
        XCTAssertEqual(resp.notifications[0].id, 1)
        XCTAssertEqual(resp.nextCursor, "eyJpZCI6MTB9")
        XCTAssertEqual(resp.unreadCount, 3)
    }

    // MARK: - Identifiable

    /// The id used by SwiftUI's ForEach must be the server's notification
    /// id (an Int), not a synthetic string.
    func testInAppNotification_IdentifiableIdMatchesServerId() throws {
        let json = """
        {
          "id": 42, "kind": "personal_best", "message": "x",
          "created_at": "2026-06-07T10:15:30Z"
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let n = try decoder.decode(InAppNotification.self, from: json)
        XCTAssertEqual(n.id, 42)
    }

    // MARK: - Bell badge cap

    /// "9+" cap: any count above 9 must render as "9+", single-digit and
    /// exact two-digit counts must render as the number itself. The bell
    /// uses this helper to keep the badge compact.
    func testBadgeLabel_CapsAtNine() {
        XCTAssertEqual(NotificationsManager.badgeLabel(forUnreadCount: 0), "0")
        XCTAssertEqual(NotificationsManager.badgeLabel(forUnreadCount: 1), "1")
        XCTAssertEqual(NotificationsManager.badgeLabel(forUnreadCount: 3), "3")
        XCTAssertEqual(NotificationsManager.badgeLabel(forUnreadCount: 9), "9")
        XCTAssertEqual(NotificationsManager.badgeLabel(forUnreadCount: 10), "9+")
        XCTAssertEqual(NotificationsManager.badgeLabel(forUnreadCount: 12), "9+")
        XCTAssertEqual(NotificationsManager.badgeLabel(forUnreadCount: 99), "9+")
        XCTAssertEqual(NotificationsManager.badgeLabel(forUnreadCount: 1_000_000), "9+")
    }

    // MARK: - lastError surface (F-2)

    /// `lastError` must be a published, settable, clearable `String?`.
    /// `NotificationsView` observes it to surface a Toast. We can't
    /// drive the catch blocks without mocking `APIService`, but the
    /// contract the view relies on is that the property exists, starts
    /// nil, and accepts a new value.
    @MainActor
    func testLastError_StartsNilAndAcceptsAssignment() {
        let manager = NotificationsManager.shared
        // Reset in case a prior test surfaced an error.
        manager.lastError = nil
        XCTAssertNil(manager.lastError)

        manager.lastError = "Couldn't load notifications"
        XCTAssertEqual(manager.lastError, "Couldn't load notifications")

        manager.lastError = nil
        XCTAssertNil(manager.lastError)
    }

    // MARK: - Polling lifecycle (smoke)

    /// Smoke test: startPolling followed by stopPolling should not crash
    /// and should leave the manager in a stopped state. We can't easily
    /// assert on the in-flight network call without injecting a mock
    /// APIService (which would require a protocol refactor), so this
    /// test only guards the lifecycle boundary itself.
    func testPollingStartsAndStops() {
        let manager = NotificationsManager.shared
        manager.stopPolling()  // ensure clean slate
        manager.startPolling()
        // Give the loop a moment to begin.
        let exp = expectation(description: "loop started")
        Task {
            try? await Task.sleep(nanoseconds: 50_000_000)
            exp.fulfill()
        }
        wait(for: [exp], timeout: 1.0)
        manager.stopPolling()
    }
}
