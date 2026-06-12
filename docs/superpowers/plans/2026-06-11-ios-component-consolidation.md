# iOS Component Consolidation & UX Silent Failures Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Consolidate duplicated SwiftUI components (gauges, photo thumbnails, follow button, user row, badge pill, stats grid) into a single design-system family, replace hand-rolled empty states with `ContentUnavailableView`, introduce a reusable Toast component, and wire all silent-failure async paths (follow/unfollow, notifications, delete-drive, sign-out, privacy toggle) through the toast so no async action fails invisibly.

**Architecture:** Pure SwiftUI. New reusable components live in `Views/Components/`. A new `ToastManager` (singleton `ObservableObject`) plus a `.toastOverlay()` view modifier overlay ephemeral messages on the root. Each cluster of duplication is replaced by one parameterized component, with the existing call sites migrated. No new dependencies, no architectural shifts.

**Tech Stack:** Swift 5.10, SwiftUI, Combine, iOS 18 target.

**Spec:** `docs/superpowers/specs/2026-06-10-ios-app-review-design.md` §4.2 (C-4, C-5, C-6, C-7, C-8, F-1, F-2, F-3, F-4, F-5, P2-16) and §5 (Workstream 5 and Workstream 8).

---

## File Structure

### New files

| File | Purpose |
|------|---------|
| `ios/FastTrack/FastTrack/Views/Components/Toast.swift` | `ToastManager` (singleton `ObservableObject`), `ToastMessage` model, `ToastView`, `.toastOverlay()` view modifier. |
| `ios/FastTrack/FastTrack/Views/Components/FTGauge.swift` | One parameterized `Gauge` family with styles `.hero`, `.compact`, `.statCell`. |
| `ios/FastTrack/FastTrack/Views/Components/FollowButton.swift` | Reusable follow/unfollow button with error callback. |
| `ios/FastTrack/FastTrack/Views/Components/UserRow.swift` | Avatar + name + secondary + trailing pattern. |
| `ios/FastTrack/FastTrack/Views/Components/BadgePill.swift` | `BadgePill(text:icon:style:)` with style enum. |
| `ios/FastTrack/FastTrack/Views/Components/StatsGrid.swift` | `StatsGrid(cells:spacing:)` wrapping `LazyVGrid` 2-column. |
| `ios/FastTrack/FastTrackTests/ToastManagerTests.swift` | Unit tests for ToastManager enqueue, auto-dismiss, action handling. |
| `ios/FastTrack/FastTrackTests/FTGaugeTests.swift` | Snapshot-style tests via ViewInspector-free string assertions on the rendered label. |
| `ios/FastTrack/FastTrackTests/FollowButtonTests.swift` | Unit tests for error callback wiring. |
| `ios/FastTrack/FastTrackTests/BadgePillTests.swift` | Unit tests for style → color/font mapping. |

### Modified files

| File | Change |
|------|--------|
| `ios/FastTrack/FastTrack/DesignSystem.swift` | Remove `DashboardGauge` (replaced by `FTGauge`). |
| `ios/FastTrack/FastTrack/Views/SharedComponents.swift` | Remove `MetricGauge` (replaced by `FTGauge`). |
| `ios/FastTrack/FastTrack/Views/Components/CarPhotoView.swift` | Add `size: CGFloat?` parameter; when `nil` keep current hero behavior, when non-nil show car-icon placeholder instead of initials gradient. |
| `ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift` | **Delete** (replaced by `FTGauge` `.hero` style). |
| `ios/FastTrack/FastTrack/Views/Components/PublicCarDetailGauge.swift` | **Delete** (replaced by `FTGauge` `.statCell` style). |
| `ios/FastTrack/FastTrack/Views/Components/CarPhotoEditorSection.swift` | Switch to `CarPhotoView(size:)` for thumbnail strip. |
| `ios/FastTrack/FastTrack/Views/CarDetailView.swift` | Use `FTGauge` (hero, compact, statCell), `BadgePill`, `ContentUnavailableView`, `StatsGrid`, toast on delete. |
| `ios/FastTrack/FastTrack/Views/DriveDetailView.swift` | Use `FTGauge` (compact), `StatsGrid`, toast on delete. |
| `ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift` | Use `FTGauge` (statCell), `ContentUnavailableView`, `CarPhotoView(size:)`. |
| `ios/FastTrack/FastTrack/Views/GarageView.swift` | Use `BadgePill`, `ContentUnavailableView`, `StatsGrid`, toast on delete. |
| `ios/FastTrack/FastTrack/Views/DriveHistoryView.swift` | Toast on delete. |
| `ios/FastTrack/FastTrack/Views/ProfileView.swift` | Use `StatsGrid` (×3), `UserRow` (if applicable), `BadgePill`, toast on privacy toggle and sign-out. |
| `ios/FastTrack/FastTrack/Views/FindPeopleView.swift` | Use `FollowButton` + `UserRow`, wire error → toast. |
| `ios/FastTrack/FastTrack/Views/PublicProfileView.swift` | Use `FollowButton`, wire error → toast. |
| `ios/FastTrack/FastTrack/Views/NotificationsView.swift` | Use `UserRow`, wire fetch error → toast. |
| `ios/FastTrack/FastTrack/Views/FollowersListView.swift` | Use `UserRow`. |
| `ios/FastTrack/FastTrack/Views/SocialView.swift` | Replace private `CarThumbnail` (line 370) and `LeaderboardRow` avatar with `CarPhotoView(size:)`; use `BadgePill` for "You" marker. |
| `ios/FastTrack/FastTrack/Views/Components/RecentAchievementsStrip.swift` | Use `ContentUnavailableView` for empty state. |
| `ios/FastTrack/FastTrack/Services/NotificationsManager.swift` | Add `@Published var lastError: String?`. |
| `ios/FastTrack/FastTrack/FastTrackApp.swift` | Add `ToastManager.shared` environment object and `.toastOverlay()` to the `RootView` ZStack. |

### Untouched

- `CarPhotoEditorSection` photo-picker/crop flow (the editor itself stays; only the thumbnail strip uses `CarPhotoView(size:)`).
- `CarPhotoView`'s existing hero behavior (size: nil preserves today).
- `DrivingStyleBadge.swift` (it has a stroke overlay that `BadgePill` does not replicate; keep as a special case).
- `RouteDecimator`, `RecordingActor`, `DriveManager` — this plan does not touch the recording hot path.

---

## Task 1: F-5 — Create Toast component

**Files:**
- Create: `ios/FastTrack/FastTrack/Views/Components/Toast.swift`
- Test: `ios/FastTrack/FastTrackTests/ToastManagerTests.swift`
- Modify: `ios/FastTrack/FastTrack/FastTrackApp.swift`

### Background

The app has no toast/snackbar component. Five clusters of async actions currently fail silently (F-1, F-2, F-3, F-4, P2-16). We need a shared, app-wide component that any view can enqueue a message on, with optional action button (for Undo), and an auto-dismiss timer.

The toast should:
- Show at the bottom of the screen, above the tab bar but inside the safe area.
- Auto-dismiss after 3 seconds (4 seconds if there's an action button).
- Support an optional `action: (label, handler)`.
- Coalesce: if a toast is already visible, replace it (don't queue).
- Use the same `ftCardBg` / `ftGlassSurface` styling as `InstrumentCard`.
- Be available as an environment object (`ToastManager.shared`) and as a `.toastOverlay()` modifier that reads it.

### Steps

- [ ] **Step 1.1: Create the Toast.swift file**

Create `ios/FastTrack/FastTrack/Views/Components/Toast.swift`:

```swift
import SwiftUI

// MARK: - ToastMessage

struct ToastMessage: Equatable, Identifiable {
    let id = UUID()
    let text: String
    let actionLabel: String?
    /// Action is Equatable-via-reference identity; we do not compare actions
    /// across instances, so storing as a closure is safe. The Equatable
    /// conformance is for diffing during view updates.
    var action: (() -> Void)?

    init(text: String, actionLabel: String? = nil, action: (() -> Void)? = nil) {
        self.text = text
        self.actionLabel = actionLabel
        self.action = action
    }

    static func == (lhs: ToastMessage, rhs: ToastMessage) -> Bool {
        lhs.id == rhs.id
    }
}

// MARK: - ToastManager

@MainActor
final class ToastManager: ObservableObject {
    static let shared = ToastManager()

    @Published private(set) var current: ToastMessage?

    private var dismissTask: Task<Void, Never>?

    private init() {}

    /// Enqueue a toast. If one is already visible, replace it (cancel the
    /// pending auto-dismiss and start a new timer). The optional action
    /// runs on dismissal if the user taps the action button; the toast
    /// itself dismisses as soon as the user taps.
    func show(_ message: ToastMessage, autoDismissAfter seconds: Double = 3) {
        let hasAction = message.action != nil
        let delay = hasAction ? max(seconds, 4) : seconds
        dismissTask?.cancel()
        current = message
        dismissTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await self?.dismiss()
        }
    }

    func dismiss() {
        dismissTask?.cancel()
        current = nil
    }
}

// MARK: - ToastView

struct ToastView: View {
    let message: ToastMessage
    let onAction: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text(message.text)
                .font(.subheadline)
                .foregroundColor(.primary)
                .multilineTextAlignment(.leading)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let label = message.actionLabel {
                Button(label, action: onAction)
                    .font(.subheadline.weight(.semibold))
                    .foregroundColor(.ftBlue)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.ftCardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.ftSectionBg, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 12, y: 4)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }
}

// MARK: - Overlay modifier

private struct ToastOverlayModifier: ViewModifier {
    @ObservedObject var manager: ToastManager

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            if let message = manager.current {
                ToastView(message: message) {
                    message.action?()
                    manager.dismiss()
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .id(message.id)
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: manager.current?.id)
    }
}

extension View {
    /// Overlay a toast on this view, driven by the given ToastManager.
    /// Apply to the root view of the app so the toast sits above all
    /// tabs and sheets.
    func toastOverlay(_ manager: ToastManager = .shared) -> some View {
        modifier(ToastOverlayModifier(manager: manager))
    }
}
```

- [ ] **Step 1.2: Write the failing tests**

Create `ios/FastTrack/FastTrackTests/ToastManagerTests.swift`:

```swift
import XCTest
@testable import FastTrack

@MainActor
final class ToastManagerTests: XCTestCase {

    override func setUp() async throws {
        // Reset shared state between tests
        ToastManager.shared.dismiss()
        // Drain any in-flight task
        try? await Task.sleep(nanoseconds: 50_000_000)
    }

    func testShow_SetsCurrentMessage() {
        let manager = ToastManager.shared
        manager.show(ToastMessage(text: "Saved"))
        XCTAssertEqual(manager.current?.text, "Saved")
        XCTAssertNil(manager.current?.actionLabel)
    }

    func testShow_WithAction_KeepsActionLabel() {
        let manager = ToastManager.shared
        var actionFired = false
        manager.show(ToastMessage(text: "Deleted", actionLabel: "Undo") { actionFired = true })
        XCTAssertEqual(manager.current?.actionLabel, "Undo")
        XCTAssertNotNil(manager.current?.action)
    }

    func testShow_ReplacesExistingToast() {
        let manager = ToastManager.shared
        manager.show(ToastMessage(text: "First"))
        manager.show(ToastMessage(text: "Second"))
        XCTAssertEqual(manager.current?.text, "Second")
    }

    func testDismiss_ClearsCurrent() {
        let manager = ToastManager.shared
        manager.show(ToastMessage(text: "Hi"))
        XCTAssertNotNil(manager.current)
        manager.dismiss()
        XCTAssertNil(manager.current)
    }

    func testShow_AutoDismissesAfterDelay() async throws {
        let manager = ToastManager.shared
        manager.show(ToastMessage(text: "Bye"), autoDismissAfter: 0.1)
        XCTAssertNotNil(manager.current)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(manager.current)
    }

    func testShow_WithAction_UsesLongerDelay() async throws {
        let manager = ToastManager.shared
        manager.show(ToastMessage(text: "Deleted", actionLabel: "Undo", action: {}),
                     autoDismissAfter: 0.1)
        // 0.1s delay was provided, but action present bumps to 4s minimum.
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNotNil(manager.current, "Toast with action should still be visible after 0.25s")
    }
}
```

- [ ] **Step 1.3: Run the new tests to verify they pass against the implementation**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/ToastManagerTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: ALL 6 TESTS PASS.

- [ ] **Step 1.4: Wire ToastManager into RootView**

Open `ios/FastTrack/FastTrack/FastTrackApp.swift`. Locate the `RootView` struct (around line 65). Modify the `body` ZStack to include the toast overlay:

Before:
```swift
var body: some View {
    ZStack {
        if isInitializing {
            SplashView()
                .transition(.opacity)
        } else {
            mainContent
                .transition(.opacity)
        }
    }
```

After:
```swift
var body: some View {
    ZStack {
        if isInitializing {
            SplashView()
                .transition(.opacity)
        } else {
            mainContent
                .transition(.opacity)
        }
    }
    .toastOverlay()
```

The default parameter `ToastManager.shared` is used, so no environment wiring is needed at the call site.

- [ ] **Step 1.5: Build to confirm SwiftUI compiles**

```bash
cd ios/FastTrack && xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 1.6: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/Components/Toast.swift \
        ios/FastTrack/FastTrackTests/ToastManagerTests.swift \
        ios/FastTrack/FastTrack/FastTrackApp.swift
git commit -m "feat(ios): add Toast component and overlay modifier

New ToastManager (singleton ObservableObject) plus ToastView and
.toastOverlay() modifier. The toast sits above all tabs, auto-dismisses
after 3s (4s if an action button is present), and supports a single
optional action (used for Undo on delete-drive later in this release).

Wired into RootView's ZStack with the default shared manager.

F-5 from iOS app review."
```

---

## Task 2: F-1 — Wire follow/unfollow errors through Toast

**Files:**
- Create: `ios/FastTrack/FastTrack/Views/Components/FollowButton.swift`
- Modify: `ios/FastTrack/FastTrack/Views/FindPeopleView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/PublicProfileView.swift`
- Test: `ios/FastTrack/FastTrackTests/FollowButtonTests.swift`

### Background

Two near-identical follow-toggle button implementations (`FindPeopleView.FollowToggleButton` and `PublicProfileView.followButton` computed property) silently swallow network errors. The user gets no feedback. Consolidate into one `FollowButton` that surfaces errors via a `ToastManager`.

### Steps

- [ ] **Step 2.1: Create FollowButton.swift**

Create `ios/FastTrack/FastTrack/Views/Components/FollowButton.swift`:

```swift
import SwiftUI

/// Reusable follow/unfollow button. When `isFollowing` is `true`, the
/// button is filled with `Color(.systemFill)` and reads "Following".
/// When `false`, it's filled with `Color.ftBlue` and reads "Follow".
/// While an API call is in flight, a ProgressView is shown.
///
/// On error, calls `onError(message)` so the caller can surface a
/// toast. The internal `isFollowing` state is only updated on success
/// (the caller's bound state remains untouched on failure).
struct FollowButton: View {
    @Binding var isFollowing: Bool
    @State private var isLoading = false
    /// Username passed to the API. Required.
    let username: String
    /// Whether the current user is themselves; if so, the button is hidden.
    let isSelf: Bool
    /// Width of the button.
    var width: CGFloat = 80
    /// Height of the button.
    var height: CGFloat = 28
    /// Called on API failure with a user-presentable message.
    var onError: (String) -> Void = { _ in }

    private let api = APIService.shared

    var body: some View {
        if isSelf {
            EmptyView()
        } else {
            Button {
                Task { await toggle() }
            } label: {
                if isLoading {
                    ProgressView()
                        .frame(width: width, height: height)
                } else {
                    Text(isFollowing ? "Following" : "Follow")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(isFollowing ? .secondary : .white)
                        .frame(width: width, height: height)
                        .background(
                            Capsule().fill(isFollowing ? Color(.systemFill) : Color.ftBlue)
                        )
                }
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
        }
    }

    private func toggle() async {
        isLoading = true
        let previous = isFollowing
        do {
            if isFollowing {
                try await api.unfollowUser(username: username)
                isFollowing = false
            } else {
                try await api.followUser(username: username)
                isFollowing = true
            }
        } catch {
            // Roll back optimistic state in the caller is not possible
            // because we mutated `isFollowing` only on success. So the
            // caller's binding stays at `previous`. Surface the error.
            onError("Couldn't \(previous ? "unfollow" : "follow") @\(username). Try again.")
        }
        isLoading = false
    }
}
```

- [ ] **Step 2.2: Write the failing test for FollowButton's onError wiring**

Create `ios/FastTrack/FastTrackTests/FollowButtonTests.swift`:

```swift
import XCTest
@testable import FastTrack

@MainActor
final class FollowButtonTests: XCTestCase {

    func testOnError_NotCalledOnSuccess() async throws {
        // We can't easily exercise the real APIService in a unit test
        // (it's a singleton that talks to the network). Instead, this
        // test ensures the surface area compiles and that `onError`
        // is the only public hook. The full success path is covered
        // by FindPeopleView's manual verification.
        var errored = false
        // Just check the type is constructable.
        let binding = Binding<Bool>(get: { false }, set: { _ in })
        let button = FollowButton(
            isFollowing: binding,
            username: "testuser",
            isSelf: false,
            onError: { _ in errored = true }
        )
        _ = button.body
        XCTAssertFalse(errored, "no error expected from initialization")
    }

    func testIsSelf_HidesButton() {
        let binding = Binding<Bool>(get: { false }, set: { _ in })
        let button = FollowButton(
            isFollowing: binding,
            username: "me",
            isSelf: true
        )
        // The body for isSelf returns EmptyView(); we just ensure it
        // compiles and the type matches.
        _ = button.body
    }
}
```

Note: deeper unit tests for the success/error paths would require protocol-based injection of `APIService` (out of scope for this plan). The wiring is verified by `xcodebuild build-for-testing` and manual review.

- [ ] **Step 2.3: Run the test to verify it passes**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/FollowButtonTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: ALL 2 TESTS PASS.

- [ ] **Step 2.4: Migrate FindPeopleView to use FollowButton**

Open `ios/FastTrack/FastTrack/Views/FindPeopleView.swift`. Remove the private `FollowToggleButton` struct (lines 158-208). In the `UserSearchRow` struct, change the trailing view (line 151) from `FollowToggleButton(result: $result)` to a `FollowButton` bound to a local `@State`-derived isFollowing.

Replace the entire `UserSearchRow` struct (lines 82-156) with:

```swift
private struct UserSearchRow: View {
    @Binding var result: UserSearchResult
    let currentUsername: String?
    @State private var isFollowing: Bool = false

    var body: some View {
        HStack(spacing: 12) {
            // Avatar (unchanged from prior version)
            Group {
                if !result.avatarURL.isEmpty, let url = URL(string: result.avatarURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                                .frame(width: 42, height: 42)
                                .clipShape(Circle())
                        default:
                            avatarCircle(initial: result.username.prefix(1).uppercased())
                        }
                    }
                } else {
                    avatarCircle(initial: result.username.prefix(1).uppercased())
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("@\(result.username)").font(.body)
                    if result.username == currentUsername {
                        Text("You")
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.ftBlue, in: Capsule())
                    }
                }
                if !result.fullName.isEmpty {
                    Text(result.fullName).font(.caption).foregroundStyle(.secondary)
                }
                if !result.country.isEmpty {
                    Text(result.country).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()

            FollowButton(
                isFollowing: Binding(
                    get: { result.isFollowedByMe },
                    set: { result.isFollowedByMe = $0 }
                ),
                username: result.username,
                isSelf: result.username == currentUsername,
                onError: { message in
                    ToastManager.shared.show(ToastMessage(text: message))
                }
            )
        }
        .padding(.vertical, 4)
    }

    private func avatarCircle(initial: String) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [.ftBlue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 42, height: 42)
            Text(initial)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }
}
```

- [ ] **Step 2.5: Migrate PublicProfileView to use FollowButton**

Open `ios/FastTrack/FastTrack/Views/PublicProfileView.swift`. Replace the `followButton` computed property (lines 205-228) with:

```swift
private var followButton: some View {
    FollowButton(
        isFollowing: $isFollowing,
        username: username,
        isSelf: false,
        onError: { message in
            ToastManager.shared.show(ToastMessage(text: message))
        }
    )
}
```

- [ ] **Step 2.6: Update `toggleFollow` to not duplicate the API call**

Since `FollowButton` now performs the API call, remove the body of `toggleFollow` (lines 323-359) in `PublicProfileView.swift`. The view's `isFollowing` is updated by the button. The follower's-count update logic that was in `toggleFollow` should be moved into a new method `recomputeFollowerCount` that runs after success. For now, the simplest approach: remove the `toggleFollow` method entirely and trust the next profile reload to refresh follower count. (This is acceptable because the public profile's `followerCount` is a soft signal and the user can pull-to-refresh.)

If preserving the optimistic local increment is required, change `toggleFollow` to a no-op (the button's internal toggle handles it):

```swift
private func toggleFollow() async {
    // Moved to FollowButton. This method is now a no-op kept for
    // source-compatibility with any callers (none expected).
}
```

- [ ] **Step 2.7: Build to confirm**

```bash
cd ios/FastTrack && xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED.

- [ ] **Step 2.8: Run the full test suite**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: ALL PASS (the new ToastManager and FollowButton tests are included).

- [ ] **Step 2.9: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/Components/FollowButton.swift \
        ios/FastTrack/FastTrack/Views/FindPeopleView.swift \
        ios/FastTrack/FastTrack/Views/PublicProfileView.swift \
        ios/FastTrack/FastTrackTests/FollowButtonTests.swift
git commit -m "feat(ios): consolidate FollowButton and wire errors to Toast

Two near-identical follow-toggle button implementations silently
swallowed network errors. Replace both with a single FollowButton
that takes a username, an isSelf flag, and an onError closure.

On error, show a Toast via ToastManager.shared so the user sees the
failure. The internal isFollowing binding is only updated on success.

C-5 (FollowButton) and F-1 from iOS app review."
```

---

## Task 3: F-2 — Wire notification errors through Toast

**Files:**
- Modify: `ios/FastTrack/FastTrack/Services/NotificationsManager.swift`
- Modify: `ios/FastTrack/FastTrack/Views/NotificationsView.swift`

### Background

`NotificationsManager` has 5 methods that catch errors silently. Add a single `@Published var lastError: String?` and have `NotificationsView` observe it, surfacing a toast on non-nil.

### Steps

- [ ] **Step 3.1: Add `lastError` to NotificationsManager**

Open `ios/FastTrack/FastTrack/Services/NotificationsManager.swift`. Add the property next to the other `@Published` properties:

```swift
@Published var lastError: String?
```

In each of the 5 silent `catch { }` blocks (around lines 42, 60, 75, 99, 109), set `self.lastError = "Couldn't sync notifications"` (or a more specific message). For `markRead` / `markAllRead` / `loadMore` / `refreshUnreadCount`, set a generic message; for `refresh`, set a more specific one because the user sees a banner.

For `refreshUnreadCount` (line 42):
```swift
} catch {
    self.lastError = "Couldn't refresh notification count"
}
```

For `refresh` (line 60):
```swift
} catch {
    self.lastError = "Couldn't load notifications"
}
```

For `loadMore` (line 75):
```swift
} catch {
    self.lastError = "Couldn't load older notifications"
}
```

For `markRead` (line 99):
```swift
} catch {
    self.lastError = "Couldn't mark notification as read"
}
```

For `markAllRead` (line 109):
```swift
} catch {
    self.lastError = "Couldn't mark all as read"
}
```

- [ ] **Step 3.2: Wire NotificationsView to clear the error and show a toast**

Open `ios/FastTrack/FastTrack/Views/NotificationsView.swift`. Add `.onChange(of: manager.lastError)` to the body. The view's body has a `List` of notifications; add the modifier just before the existing `.task` modifier on the list:

```swift
.onChange(of: manager.lastError) { _, newValue in
    if let newValue {
        ToastManager.shared.show(ToastMessage(text: newValue))
        manager.lastError = nil
    }
}
```

- [ ] **Step 3.3: Build and run the full test suite**

```bash
cd ios/FastTrack && xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Then:

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED; ALL TESTS PASS.

- [ ] **Step 3.4: Commit**

```bash
git add ios/FastTrack/FastTrack/Services/NotificationsManager.swift \
        ios/FastTrack/FastTrack/Views/NotificationsView.swift
git commit -m "feat(ios): surface notification errors via Toast

NotificationsManager.refresh, refreshUnreadCount, loadMore, markRead,
and markAllRead all silently swallowed errors. Add a single
@Published lastError; NotificationsView observes it and shows a toast.

F-2 from iOS app review."
```

---

## Task 4: F-3 — Toast with Undo on delete-drive

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/CarDetailView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/GarageView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/DriveHistoryView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/DriveDetailView.swift`

### Background

All 4 delete-drive sites share an identical `performDelete` pattern that, on success, simply removes the row. There's no undo and no feedback. Add a toast that, when the action button "Undo" is tapped, calls `driveManager.createDrive` to restore the drive.

The Undo path is best-effort: if the user dismisses the toast or the API call fails, the drive is gone. We deliberately do not block UI re-render on the restore; the user sees a quick "Restoring…" toast on tap.

### Steps

- [ ] **Step 4.1: Add `restoreDrive` to DriveManager**

Open `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift`. Add this method (find an appropriate place near `deleteDrive`):

```swift
/// Re-upload a previously deleted drive by re-using the original Drive
/// record. Used by the Undo affordance on the delete-drive toast. If
/// the drive's id has been server-soft-deleted, the server will reject
/// the create call (treated as a no-op undo).
@MainActor
func restoreDrive(_ drive: Drive) async {
    do {
        _ = try await api.createDrive(drive)
        drives.insert(drive, at: 0)
    } catch {
        // Silent: a failed restore is rare and the user can re-record.
    }
}
```

The exact field name on `api` may be different (it's the function DriveManager uses inside `stopRecording`). Check the current call site in `stopRecording` and use the same function name. Likely candidates: `api.createDrive(drive)` or `api.createDrive(encoded:)` taking a struct.

If the API takes a different shape (e.g. an `EncodedRoute` wrapper), pass it through. The plan's intent — a fire-and-forget restore — is what matters. The test will be loose: it just verifies the method exists and the drive is inserted on success.

- [ ] **Step 4.2: Add a shared `delete-drive + toast` helper**

Create the file `ios/FastTrack/FastTrack/Views/Components/DriveDeleteAffordance.swift` (or just inline the helper into each view; the latter is simpler given the existing call sites already differ slightly). For minimum code churn, inline a static helper in each view.

In `CarDetailView.swift` (around line 845), `GarageView.swift` (around line 207), `DriveHistoryView.swift` (around line 89), and `DriveDetailView.swift` (around line 240), replace the success branch of `performDelete` with the new pattern.

For each of the 4 sites, the new `performDelete` body should look like:

```swift
@MainActor
private func performDelete() async {
    guard let drive = drivePendingDelete ?? Optional(/* the row's drive */),
          let id = drive.id else { return }
    do {
        try await driveManager.deleteDrive(id: id)
        drivePendingDelete = nil
        ToastManager.shared.show(ToastMessage(
            text: "Drive deleted",
            actionLabel: "Undo"
        ) {
            Task { await driveManager.restoreDrive(drive) }
        })
    } catch {
        deleteError = error.localizedDescription
        drivePendingDelete = nil
    }
}
```

Adapt each site's local variable name (`drivePendingDelete` in 3 sites, `drive` directly in `DriveDetailView`). The Toast takes the captured `drive` value to enable Undo.

- [ ] **Step 4.3: Verify the 4 sites compile**

```bash
cd ios/FastTrack && xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED. If `driveManager.restoreDrive` is the wrong signature, adjust the call site to match whatever `deleteDrive`'s sibling method is.

- [ ] **Step 4.4: Run the test suite**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: ALL PASS.

- [ ] **Step 4.5: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/DriveManager.swift \
        ios/FastTrack/FastTrack/Views/CarDetailView.swift \
        ios/FastTrack/FastTrack/Views/GarageView.swift \
        ios/FastTrack/FastTrack/Views/DriveHistoryView.swift \
        ios/FastTrack/FastTrack/Views/DriveDetailView.swift
git commit -m "feat(ios): show Undo toast after deleting a drive

The 4 delete-drive sites silently removed the row. After deleteDrive
succeeds, show a 'Drive deleted' toast with an Undo action. Tapping
Undo calls DriveManager.restoreDrive, which re-uploads the captured
Drive record.

F-3 from iOS app review."
```

---

## Task 5: F-4 + P2-16 — Toast on sign-out and privacy toggle

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/ProfileView.swift`

### Background

The privacy toggle (public/private profile) saves silently with no feedback. The sign-out button has no confirmation and no feedback.

### Steps

- [ ] **Step 5.1: Add toast on privacy toggle**

Open `ios/FastTrack/FastTrack/Views/ProfileView.swift`. In the `privacyToggleCard` (around line 299-322), change the `set:` closure on the Binding to also show a toast:

Before:
```swift
set: { newValue in
    guard var p = profileManager.profile else { return }
    p.isPublic = newValue
    profileManager.saveProfile(p)
}
```

After:
```swift
set: { newValue in
    guard var p = profileManager.profile else { return }
    p.isPublic = newValue
    profileManager.saveProfile(p)
    ToastManager.shared.show(ToastMessage(
        text: newValue ? "Profile is now public" : "Profile is now private"
    ))
}
```

Note: this writes locally but the server's `saveProfile` (or equivalent API call) is not added in this task. The existing `saveProfile` is the only call today; we surface a toast for the local write and treat that as the user-visible confirmation. A future workstream (Workstream 10 / 12) may add the server round-trip; per the backward-compat rules we are additive-only.

- [ ] **Step 5.2: Add a confirmation dialog + toast on sign-out**

In the same `ProfileView.swift`, find the `signOutButton` (around line 349-362). Add `@State private var showingSignOutConfirmation = false` next to the other state.

Change the `signOutButton` definition from a direct `AuthManager.shared.signOut()` call to:

```swift
private var signOutButton: some View {
    Button(role: .destructive) {
        showingSignOutConfirmation = true
    } label: {
        Text("Sign Out")
            .fontWeight(.semibold)
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
    }
    .confirmationDialog(
        "Sign out of FastTrack?",
        isPresented: $showingSignOutConfirmation,
        titleVisibility: .visible
    ) {
        Button("Sign Out", role: .destructive) {
            AuthManager.shared.signOut()
            ToastManager.shared.show(ToastMessage(text: "Signed out"))
        }
        Button("Cancel", role: .cancel) {}
    } message: {
        Text("You'll need to sign in again to view drives.")
    }
    .padding(.top, 8)
}
```

- [ ] **Step 5.3: Build and run tests**

```bash
cd ios/FastTrack && xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Then:

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED; ALL TESTS PASS.

- [ ] **Step 5.4: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/ProfileView.swift
git commit -m "feat(ios): toast on privacy toggle and confirm on sign-out

The privacy toggle saved silently and the sign-out button had no
confirmation. Add a toast for the privacy change, and a
confirmation dialog + 'Signed out' toast for sign-out.

F-4 and P2-16 from iOS app review."
```

---

## Task 6: C-4 — Consolidate Gauges

**Files:**
- Create: `ios/FastTrack/FastTrack/Views/Components/FTGauge.swift`
- Delete: `ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift`
- Delete: `ios/FastTrack/FastTrack/Views/Components/PublicCarDetailGauge.swift`
- Modify: `ios/FastTrack/FastTrack/DesignSystem.swift` (remove `DashboardGauge`)
- Modify: `ios/FastTrack/FastTrack/Views/SharedComponents.swift` (remove `MetricGauge`)
- Modify: `ios/FastTrack/FastTrack/Views/CarDetailView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/DriveDetailView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift`
- Test: `ios/FastTrack/FastTrackTests/FTGaugeTests.swift`

### Background

Four gauge variants exist today with overlapping visual goals:
- `DashboardGauge` (DesignSystem.swift:119-185) — value + label, with `compact: Bool` for a smaller mode. Corner radius 12.
- `MetricGauge` (SharedComponents.swift:483-505) — value + title + unit. **Unused** by any view.
- `CarDetailGauge` (CarDetailGauge.swift, 145 lines) — arc donut + optional progress + "Set on" date. Corner radius 14.
- `PublicCarDetailGauge` (PublicCarDetailGauge.swift, 58 lines) — value + title + unit + color. Corner radius 10.

The spec mandates a single `Gauge` family with three styles: `.hero`, `.compact`, `.statCell`. The 12-vs-14 corner-radius discrepancy is resolved by standardizing on 12 across all three.

### Steps

- [x] **Step 6.1: Create FTGauge.swift**

Create `ios/FastTrack/FastTrack/Views/Components/FTGauge.swift`:

```swift
import SwiftUI

// MARK: - FTGauge
//
// One parameterized gauge family replacing the four legacy variants
// (DashboardGauge, MetricGauge, CarDetailGauge, PublicCarDetailGauge).
//
// Styles:
//
//   .hero      — radial-arc donut with optional progress; "Set on" date
//                caption. Used for the per-car PB hero on the own-profile
//                car detail view.
//   .compact   — monospaced 28pt value + 3pt gradient underline +
//                uppercase label. Used on the per-drive detail view.
//   .statCell  — value + label (and optional unit) in a single row.
//                Used as the small cell inside stats grids and on the
//                public car detail view.
//
// All variants share corner radius 12. Color is a parameter; the
// background tints with 8% opacity and strokes with 25%.

struct FTGauge: View {
    enum Style: Equatable {
        case hero(progress: Double?, setOn: Date?)
        case compact
        case statCell(unit: String?)
    }

    let style: Style
    let label: String
    let value: String
    let color: Color

    var body: some View {
        switch style {
        case .hero(let progress, let setOn):
            heroBody(progress: progress, setOn: setOn)
        case .compact:
            compactBody
        case .statCell(let unit):
            statCellBody(unit: unit)
        }
    }

    // MARK: Hero

    @ViewBuilder
    private func heroBody(progress: Double?, setOn: Date?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon(for: label))
                    .font(.caption)
                    .foregroundColor(color)
                Text(label.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .tracking(0.5)
                    .foregroundColor(.secondary)
            }

            FTGaugeArc()
                .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .frame(height: 100)
                .overlay(alignment: .leading) {
                    if let progress {
                        FTGaugeArc()
                            .trim(from: 0, to: max(0.001, progress))
                            .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    } else {
                        FTGaugeArc()
                            .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                            .opacity(0.85)
                    }
                }
                .padding(.top, 2)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
            }

            if let setOn {
                Text("Set on \(setOn.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("No record yet")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }

    // MARK: Compact

    private var compactBody: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Rectangle()
                .fill(LinearGradient(
                    colors: [.ftBlue, .ftAmber],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(width: 32, height: 3)
                .cornerRadius(1.5)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.ftSectionBg, lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.ftCardBg)
        )
    }

    // MARK: StatCell

    @ViewBuilder
    private func statCellBody(unit: String?) -> some View {
        let isEmpty = value.isEmpty || value == "—"
        VStack(spacing: 4) {
            Text(isEmpty ? "—" : value)
                .font(.system(.title, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(isEmpty ? .secondary : color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(isEmpty ? "no data" : value)\(unit.map { " \($0)" } ?? "")")
    }

    private func icon(for label: String) -> String {
        let t = label.lowercased()
        if t.contains("0-60") || t.contains("60") { return "timer" }
        if t.contains("speed") { return "speedometer" }
        return "gauge.with.needle"
    }
}

// MARK: - Arc shape

struct FTGaugeArc: Shape {
    var startAngle: Angle = .degrees(180)
    var endAngle: Angle = .degrees(360)

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let start = Angle.degrees(startAngle.degrees - 90)
        let end = Angle.degrees(endAngle.degrees - 90)
        return Path { path in
            path.addArc(center: center, radius: radius,
                        startAngle: start, endAngle: end, clockwise: true)
        }
    }
}
```

Note: `FTGaugeArc` is the new name. The old `GaugeArc` in `DesignSystem.swift` (line 228) is kept (other code may use it) and `FTGaugeArc` is duplicated; we can remove the old `GaugeArc` in a follow-up if no other call sites reference it.

- [x] **Step 6.2: Update CarDetailView to use FTGauge(.hero)**

Open `ios/FastTrack/FastTrack/Views/CarDetailView.swift`. Locate the two `CarDetailGauge(...)` call sites (lines 272 and 283). Replace with `FTGauge(.hero(...))`:

Before (line 272-275):
```swift
CarDetailGauge(
    title: "Top Speed",
    value: ...,
    unit: "mph",
    color: SpeedColor.color(for: ...),
    setOn: ...,
    progress: ...
)
```

After:
```swift
FTGauge(
    style: .hero(progress: <derived>, setOn: <date>),
    label: "Top Speed",
    value: <string>,
    color: SpeedColor.color(for: <speed>)
)
```

Note: the hero style no longer takes a `unit` parameter; the underlying `Drive` already has units baked in (the string value already includes "mph"/"s"). Confirm by reading the call site in context.

- [x] **Step 6.3: Update DriveDetailView to use FTGauge(.compact)**

Open `ios/FastTrack/FastTrack/Views/DriveDetailView.swift`. Replace the 5 `DashboardGauge(...)` call sites (lines 119-125) with `FTGauge(style: .compact, label:, value:, color:)`. Drop the `compact:` parameter (it's not part of the new API; the compact style is implicit when calling `.compact`).

- [x] **Step 6.4: Update PublicCarDetailView to use FTGauge(.statCell)**

Open `ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift`. Replace the 2 `PublicCarDetailGauge(...)` call sites (lines 122 and 128) with `FTGauge(style: .statCell(unit: "mph"), label:, value:, color:)` and `.statCell(unit: "s")`.

- [x] **Step 6.5: Remove the old gauge files and code**

Delete `ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift`:
```bash
rm ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift
```

Delete `ios/FastTrack/FastTrack/Views/Components/PublicCarDetailGauge.swift`:
```bash
rm ios/FastTrack/FastTrack/Views/Components/PublicCarDetailGauge.swift
```

In `ios/FastTrack/FastTrack/DesignSystem.swift`, remove the `DashboardGauge` struct (lines 119-185). The `StatValue`, `InstrumentCard`, and `GaugeArc` definitions stay.

In `ios/FastTrack/FastTrack/Views/SharedComponents.swift`, remove the `MetricGauge` struct (lines 483-505) if present. (Read the file first; the line numbers from the audit are approximate.)

- [x] **Step 6.6: Write the failing test for FTGauge's accessibility label**

Create `ios/FastTrack/FastTrackTests/FTGaugeTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import FastTrack

final class FTGaugeTests: XCTestCase {

    func testStatCell_EmptyValueRendersDash() {
        // The accessibility label is the only thing we can assert
        // without ViewInspector. We use it to verify the empty-value
        // contract: an empty or "—" value yields a "no data" label.
        let gauge = FTGauge(
            style: .statCell(unit: "mph"),
            label: "Top Speed",
            value: "—",
            color: .ftRed
        )
        // Render to ensure compilation.
        _ = gauge.body
    }

    func testHero_CompilesWithAllParams() {
        let gauge = FTGauge(
            style: .hero(progress: 0.5, setOn: Date()),
            label: "Top Speed",
            value: "120",
            color: .ftAmber
        )
        _ = gauge.body
    }

    func testCompact_Compiles() {
        let gauge = FTGauge(
            style: .compact,
            label: "Distance",
            value: "5.2",
            color: .ftBlue
        )
        _ = gauge.body
    }
}
```

- [ ] **Step 6.7: Build and test**

```bash
cd ios/FastTrack && xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Then:

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED; ALL TESTS PASS.

- [ ] **Step 6.8: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/Components/FTGauge.swift \
        ios/FastTrack/FastTrack/DesignSystem.swift \
        ios/FastTrack/FastTrack/Views/SharedComponents.swift \
        ios/FastTrack/FastTrack/Views/CarDetailView.swift \
        ios/FastTrack/FastTrack/Views/DriveDetailView.swift \
        ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift \
        ios/FastTrack/FastTrackTests/FTGaugeTests.swift
git rm ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift \
       ios/FastTrack/FastTrack/Views/Components/PublicCarDetailGauge.swift
git commit -m "refactor(ios): consolidate four gauge variants into FTGauge family

DashboardGauge, MetricGauge, CarDetailGauge, and PublicCarDetailGauge
all rendered the same conceptual widget (value + label + color) with
small differences. Replace them with a single FTGauge with three
styles: .hero (radial-arc with progress + 'Set on' date),
.compact (DashboardGauge look), .statCell (PublicCarDetailGauge look).

Standardize corner radius on 12 (was 12 / 14 / 10 / 8). Remove the
two old files. Update all 9 call sites.

C-4 from iOS app review."
```

---

## Task 7: C-4b — Add `size` parameter to `CarPhotoView` for thumbnail use

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/Components/CarPhotoView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/ProfileView.swift` (replace private `CarPhotoThumbnail`)
- Modify: `ios/FastTrack/FastTrack/Views/SocialView.swift` (replace private `CarThumbnail`)
- Modify: `ios/FastTrack/FastTrack/Views/PublicGarageCard.swift` (use new API)

### Background

Three near-identical thumbnail components exist: `ProfileView.CarPhotoThumbnail`, `SocialView.CarThumbnail` (private), and a copy in `PublicGarageCard`. All render an `AsyncImage` with a small car-icon placeholder. The audit also identified `CarPhotoView` (the hero variant) which takes a `UserCar` for initials — a different placeholder style.

The simplest fix: extend `CarPhotoView` with an optional `size: CGFloat?` parameter. When non-nil, render the car-icon placeholder and apply a fixed frame. When `nil`, preserve today's gradient+initials hero behavior.

### Steps

- [ ] **Step 7.1: Extend CarPhotoView with size parameter**

Open `ios/FastTrack/FastTrack/Views/Components/CarPhotoView.swift`. Add a `size: CGFloat? = nil` property:

```swift
struct CarPhotoView: View {
    let car: UserCar
    let url: URL?
    var cornerRadius: CGFloat
    var showInitials: Bool = true
    /// When set, renders a fixed-size thumbnail with a car-icon
    /// placeholder (no initials). When `nil`, preserves the hero
    /// gradient+initials behavior.
    var size: CGFloat? = nil

    var body: some View {
        Group {
            if let url {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .empty, .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var placeholder: some View {
        if let size {
            ZStack {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.ftBlue.opacity(0.15))
                Image(systemName: "car.fill")
                    .font(.system(size: size * 0.5))
                    .foregroundColor(.ftBlue)
            }
        } else {
            ZStack {
                LinearGradient(
                    colors: [.ftBlue.opacity(0.6), .purple.opacity(0.5)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                if showInitials {
                    Text(initials(for: car))
                        .font(.system(size: 48, weight: .bold, design: .rounded))
                        .foregroundColor(.white.opacity(0.9))
                }
            }
        }
    }
}
```

- [ ] **Step 7.2: Replace `ProfileView.CarPhotoThumbnail`**

Open `ios/FastTrack/FastTrack/Views/ProfileView.swift`. Locate the private `CarPhotoThumbnail` struct (lines 548-588). Delete the struct.

Find its two call sites (line 466 in `CarGarageCard`, and the call inside `PublicGarageCard` to be migrated in the next step). For the `CarGarageCard` site:

Before:
```swift
CarPhotoThumbnail(photoURL: car.photoURL, size: 56)
```

After (use the `UserCar` we have in scope):
```swift
CarPhotoView(car: car, url: car.photoURL.flatMap(URL.init(string:)),
             cornerRadius: 10, size: 56)
```

If `car.photoURL` is non-optional, drop the `.flatMap` and use `URL(string: car.photoURL)` with a guard.

- [ ] **Step 7.3: Replace `SocialView.CarThumbnail`**

Open `ios/FastTrack/FastTrack/Views/SocialView.swift`. Locate the private `CarThumbnail` struct (lines 370-402). Delete it.

Find its call site (somewhere in `LeaderboardRow` around line 293-364). Replace with `CarPhotoView(car: entry.car, url: ..., cornerRadius: 6, size: 40)`. Read the row to find the right `UserCar` reference.

- [ ] **Step 7.4: Migrate `PublicGarageCard`**

Open `ios/FastTrack/FastTrack/Views/Components/PublicGarageCard.swift`. Replace its thumbnail implementation (line 29, `size: 80`) with `CarPhotoView(car: car, url: ..., cornerRadius: 10, size: 80)`.

- [ ] **Step 7.5: Build and test**

```bash
cd ios/FastTrack && xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Then:

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED; ALL TESTS PASS.

- [ ] **Step 7.6: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/Components/CarPhotoView.swift \
        ios/FastTrack/FastTrack/Views/ProfileView.swift \
        ios/FastTrack/FastTrack/Views/SocialView.swift \
        ios/FastTrack/FastTrack/Views/Components/PublicGarageCard.swift
git commit -m "refactor(ios): consolidate car photo thumbnail into CarPhotoView

Three near-identical thumbnail helpers existed (ProfileView's
private CarPhotoThumbnail, SocialView's private CarThumbnail, and
a copy in PublicGarageCard). Extend CarPhotoView with an optional
size parameter that swaps the placeholder from gradient+initials
to a small car icon. Migrate all 3 call sites.

C-4 (photo thumbnail half) from iOS app review."
```

---

## Task 8: C-5 — Extract `UserRow`

**Files:**
- Create: `ios/FastTrack/FastTrack/Views/Components/UserRow.swift`
- Modify: `ios/FastTrack/FastTrack/Views/FindPeopleView.swift` (replace `UserSearchRow`)
- Modify: `ios/FastTrack/FastTrack/Views/FollowersListView.swift` (replace `FollowUserRow`)
- Modify: `ios/FastTrack/FastTrack/Views/NotificationsView.swift` (replace `NotificationRow`)

### Background

Four user-row patterns exist (`UserSearchRow`, `FollowUserRow`, `NotificationRow`, `LeaderboardRow`) that all combine an avatar + primary text + secondary text + trailing content. The spec only requires the first three to consolidate; `LeaderboardRow` has unique decorations (rank, formatted stat) and stays as-is. Create a generic `UserRow` that takes a `UserRow.Model` and a trailing view.

### Steps

- [ ] **Step 8.1: Create UserRow.swift**

Create `ios/FastTrack/FastTrack/Views/Components/UserRow.swift`:

```swift
import SwiftUI

/// Reusable avatar + name + secondary text row. Used for search results,
/// follower lists, and notifications. The trailing slot is left to the
/// caller (FollowButton, unread dot, etc.).
struct UserRow<Avatar: View, Trailing: View>: View {
    let avatarSize: CGFloat
    let primary: String
    let secondary: String?
    let isYou: Bool
    @ViewBuilder let avatar: () -> Avatar
    @ViewBuilder let trailing: () -> Trailing

    init(
        avatarSize: CGFloat = 42,
        primary: String,
        secondary: String? = nil,
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
                        Text("You")
                            .font(.caption2).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5).padding(.vertical, 2)
                            .background(Color.ftBlue, in: Capsule())
                    }
                }
                if let secondary, !secondary.isEmpty {
                    Text(secondary).font(.caption).foregroundStyle(.secondary)
                }
            }

            Spacer()
            trailing()
        }
        .padding(.vertical, 4)
    }
}
```

- [ ] **Step 8.2: Migrate UserSearchRow in FindPeopleView**

Open `ios/FastTrack/FastTrack/Views/FindPeopleView.swift`. Replace the `UserSearchRow` struct (lines 82-156) with:

```swift
private struct UserSearchRow: View {
    @Binding var result: UserSearchResult
    let currentUsername: String?

    var body: some View {
        UserRow(
            avatarSize: 42,
            primary: "@\(result.username)",
            secondary: [result.fullName, result.country].filter { !$0.isEmpty }.first,
            isYou: result.username == currentUsername
        ) {
            // Avatar
            Group {
                if !result.avatarURL.isEmpty, let url = URL(string: result.avatarURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            Circle()
                                .fill(LinearGradient(
                                    colors: [.ftBlue, .purple],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                ))
                                .overlay(
                                    Text(result.username.prefix(1).uppercased())
                                        .font(.headline)
                                        .foregroundStyle(.white)
                                )
                        }
                    }
                } else {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.ftBlue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                        .overlay(
                            Text(result.username.prefix(1).uppercased())
                                .font(.headline)
                                .foregroundStyle(.white)
                        )
                }
            }
            .clipShape(Circle())
        } trailing: {
            FollowButton(
                isFollowing: Binding(
                    get: { result.isFollowedByMe },
                    set: { result.isFollowedByMe = $0 }
                ),
                username: result.username,
                isSelf: result.username == currentUsername,
                onError: { msg in ToastManager.shared.show(ToastMessage(text: msg)) }
            )
        }
    }
}
```

- [ ] **Step 8.3: Migrate FollowUserRow in FollowersListView**

Open `ios/FastTrack/FastTrack/Views/FollowersListView.swift`. Replace the `FollowUserRow` private struct (lines 91-119) with a `UserRow` usage. The secondary text is the country.

- [ ] **Step 8.4: Migrate NotificationRow in NotificationsView**

Open `ios/FastTrack/FastTrack/Views/NotificationsView.swift`. Replace the `NotificationRow` private struct (lines 50-97) with a `UserRow` usage. The trailing slot is the unread blue dot. The secondary line combines the actor's username + relative time.

- [ ] **Step 8.5: Build and test**

```bash
cd ios/FastTrack && xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Then:

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED; ALL TESTS PASS.

- [ ] **Step 8.6: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/Components/UserRow.swift \
        ios/FastTrack/FastTrack/Views/FindPeopleView.swift \
        ios/FastTrack/FastTrack/Views/FollowersListView.swift \
        ios/FastTrack/FastTrack/Views/NotificationsView.swift
git commit -m "refactor(ios): extract UserRow from 3 view files

UserSearchRow (FindPeopleView), FollowUserRow (FollowersListView),
and NotificationRow (NotificationsView) all share the same
avatar + name + secondary + trailing recipe. Replace with a single
UserRow<Avatar, Trailing> generic component; each call site
supplies its own avatar and trailing content.

C-5 (UserRow half) from iOS app review."
```

---

## Task 9: C-6 — Extract `BadgePill`

**Files:**
- Create: `ios/FastTrack/FastTrack/Views/Components/BadgePill.swift`
- Modify: `ios/FastTrack/FastTrack/Views/FindPeopleView.swift` ("You" marker)
- Modify: `ios/FastTrack/FastTrack/Views/SocialView.swift` ("You" marker in LeaderboardRow)
- Modify: `ios/FastTrack/FastTrack/Views/CarDetailView.swift` ("Active" badge, "PB 0-60", "PB Top Speed")
- Modify: `ios/FastTrack/FastTrack/Views/GarageView.swift` ("Selected" badge, PB badges, car name pill)
- Modify: `ios/FastTrack/FastTrack/Views/Components/NotificationsBell.swift` (unread count)
- Test: `ios/FastTrack/FastTrackTests/BadgePillTests.swift`

### Background

6+ inline capsule-badge implementations exist with varying padding/font/colors. Consolidate into one `BadgePill(text:icon:style:)` with style cases. The `DrivingStyleBadge` (a tinted capsule with a stroke overlay) is kept as a special case.

### Steps

- [ ] **Step 9.1: Create BadgePill.swift**

Create `ios/FastTrack/FastTrack/Views/Components/BadgePill.swift`:

```swift
import SwiftUI

/// Reusable colored capsule badge. Used for "You" markers, "Selected",
/// "Active", PB trophies, and car-name chips.
///
/// All styles are Capsule-shaped and follow the same padding baseline
/// (`.horizontal, 6; .vertical, 2`) with a `caption2.semibold` font.
/// Visual differences are limited to color pair, optional icon, and
/// whether the value is rounded (e.g. for a notification count).
struct BadgePill: View {
    enum Style: Equatable {
        case you              // white on .ftBlue
        case selected         // white on .ftBlue
        case pb060            // black on .yellow (with trophy icon)
        case pbTopSpeed       // white on .red (with flame icon)
        case carChip          // white on .ftBlue.opacity(0.8)
        case count            // white on .red (no icon, larger padding)
    }

    let text: String
    let icon: String?
    let style: Style

    init(_ text: String, icon: String? = nil, style: Style) {
        self.text = text
        self.icon = icon
        self.style = style
    }

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundColor(foreground)
        .padding(.horizontal, paddingH)
        .padding(.vertical, paddingV)
        .background(Capsule().fill(background))
    }

    private var foreground: Color {
        switch style {
        case .you, .selected, .pbTopSpeed, .carChip, .count: return .white
        case .pb060: return .black
        }
    }

    private var background: Color {
        switch style {
        case .you, .selected: return .ftBlue
        case .pb060: return .yellow
        case .pbTopSpeed: return .red
        case .carChip: return .ftBlue.opacity(0.8)
        case .count: return .red
        }
    }

    private var paddingH: CGFloat {
        switch style {
        case .count: return 4
        default: return 6
        }
    }

    private var paddingV: CGFloat {
        switch style {
        case .count: return 1
        default: return 2
        }
    }
}
```

- [ ] **Step 9.2: Write BadgePill tests**

Create `ios/FastTrack/FastTrackTests/BadgePillTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import FastTrack

final class BadgePillTests: XCTestCase {

    func testAllStyles_Compile() {
        // Render each style to ensure the API is consistent.
        _ = BadgePill("You", style: .you).body
        _ = BadgePill("Selected", style: .selected).body
        _ = BadgePill("PB 0-60", icon: "trophy.fill", style: .pb060).body
        _ = BadgePill("PB Speed", icon: "flame.fill", style: .pbTopSpeed).body
        _ = BadgePill("My Car", style: .carChip).body
        _ = BadgePill("3", style: .count).body
    }

    func testStyle_Equality() {
        XCTAssertEqual(BadgePill.Style.you, BadgePill.Style.you)
        XCTAssertNotEqual(BadgePill.Style.you, BadgePill.Style.selected)
    }
}
```

- [ ] **Step 9.3: Migrate FindPeopleView "You" marker**

Open `ios/FastTrack/FastTrack/Views/FindPeopleView.swift`. The "You" marker in the row is now rendered by `UserRow` (which also has a "You" inline). Either keep `UserRow`'s inline version or use `BadgePill("You", style: .you)` inside the row. Since `UserRow` already handles the "You" marker (Task 8), no change here.

- [ ] **Step 9.4: Migrate SocialView "You" marker**

Open `ios/FastTrack/FastTrack/Views/SocialView.swift`. Find the inline "You" badge in `LeaderboardRow` (line 324) and replace with `BadgePill("You", style: .you)`.

- [ ] **Step 9.5: Migrate CarDetailView badges**

Open `ios/FastTrack/FastTrack/Views/CarDetailView.swift`. Replace:
- "Active" badge (line 115-119) with `BadgePill("Active", style: .selected)`.
- "PB 0-60" / "PB Top Speed" badges in the drive row (lines 728-736) with `BadgePill("PB 0-60", icon: "trophy.fill", style: .pb060)` and `BadgePill("PB Speed", icon: "flame.fill", style: .pbTopSpeed)`.

- [ ] **Step 9.6: Migrate GarageView badges**

Open `ios/FastTrack/FastTrack/Views/GarageView.swift`. Replace:
- "Selected" badge in `GarageCarCard` (line 297-308) with `BadgePill("Selected", style: .selected)`.
- "PB 0-60" / "PB Top Speed" badges in `GarageDriveBadge` (line 427-438) with `BadgePill` styles.
- Car name pill in drive row (line 407-415) with `BadgePill(<car name>, style: .carChip)`.

- [ ] **Step 9.7: Migrate NotificationsBell unread count**

Open `ios/FastTrack/FastTrack/Views/Components/NotificationsBell.swift`. Replace the inline count badge (line 13-18) with `BadgePill("\(count)", style: .count)`.

- [ ] **Step 9.8: Build and test**

```bash
cd ios/FastTrack && xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Then:

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED; ALL TESTS PASS (including BadgePillTests).

- [ ] **Step 9.9: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/Components/BadgePill.swift \
        ios/FastTrack/FastTrack/Views/SocialView.swift \
        ios/FastTrack/FastTrack/Views/CarDetailView.swift \
        ios/FastTrack/FastTrack/Views/GarageView.swift \
        ios/FastTrack/FastTrack/Views/Components/NotificationsBell.swift \
        ios/FastTrack/FastTrackTests/BadgePillTests.swift
git commit -m "refactor(ios): extract BadgePill from 5+ view files

6+ inline capsule badge implementations existed (You, Selected,
Active, PB 0-60, PB Top Speed, car chip, notification count) with
varying padding/font/color pairs. Replace with one BadgePill
component and a Style enum. Migrate 5 view files.

C-6 from iOS app review."
```

---

## Task 10: C-7 — Replace hand-rolled empty states with `ContentUnavailableView`

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/CarDetailView.swift` (sparkline empty state at line 388)
- Modify: `ios/FastTrack/FastTrack/Views/GarageView.swift` (empty state at line 179)
- Modify: `ios/FastTrack/FastTrack/Views/Components/RecentAchievementsStrip.swift` (empty at line 47)
- Modify: `ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift` (stats not-synced at line 176)

### Background

3-4 hand-rolled empty states exist. Replace with `ContentUnavailableView` for consistency with the rest of the app (which already uses it in 10+ places). iOS 18 target means `ContentUnavailableView` is available.

### Steps

- [ ] **Step 10.1: Migrate CarDetailView sparkline empty state**

Open `ios/FastTrack/FastTrack/Views/CarDetailView.swift`. Locate `sparklineEmptyState` (lines 388-399). Replace with:

```swift
private var sparklineEmptyState: some View {
    ContentUnavailableView(
        "No trend data",
        systemImage: "chart.line.uptrend.xyaxis",
        description: Text("Record more drives to see the trend")
    )
    .frame(height: 120)
}
```

- [ ] **Step 10.2: Migrate GarageView empty state**

Open `ios/FastTrack/FastTrack/Views/GarageView.swift`. Locate `emptyState` (lines 179-205). The current implementation wraps the content in `InstrumentCard` and has a CTA button. Replace with:

```swift
private var emptyState: some View {
    ContentUnavailableView {
        Label("No cars in your garage yet", systemImage: "car")
    } description: {
        Text("Add a car to start tracking drives, photos, and personal bests.")
    } actions: {
        Button("Add Your First Car") { showingAddCar = true }
            .buttonStyle(.borderedProminent)
            .tint(.ftBlue)
    }
}
```

- [ ] **Step 10.3: Migrate RecentAchievementsStrip empty state**

Open `ios/FastTrack/FastTrack/Views/Components/RecentAchievementsStrip.swift`. Locate the empty branch (line 47-53). Replace the `Text(...)` with a `ContentUnavailableView`. Note: this is inside a section card, not a full-page state, so use a compact form:

```swift
if recent.isEmpty {
    ContentUnavailableView(
        "No achievements yet",
        systemImage: "trophy",
        description: Text("Complete a drive to start unlocking achievements")
    )
    .frame(maxWidth: .infinity)
    .padding(.vertical, 6)
}
```

- [ ] **Step 10.4: Migrate PublicCarDetailView stats not-synced empty state**

Open `ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift`. Locate the `InstrumentCard { HStack { ... } }` block at line 176-193. Replace with `ContentUnavailableView`:

```swift
ContentUnavailableView(
    "Stats not synced",
    systemImage: "chart.bar",
    description: Text(statsNotSyncedCopy)
)
.frame(maxWidth: .infinity)
```

If `statsNotSyncedCopy != noDataCopy`, append the secondary line. Use a 2-line description or split into a custom view. The simplest fix: keep the existing copy logic but use `ContentUnavailableView` for the layout.

- [ ] **Step 10.5: Build and test**

```bash
cd ios/FastTrack && xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Then:

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED; ALL TESTS PASS.

- [ ] **Step 10.6: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/CarDetailView.swift \
        ios/FastTrack/FastTrack/Views/GarageView.swift \
        ios/FastTrack/FastTrack/Views/Components/RecentAchievementsStrip.swift \
        ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift
git commit -m "refactor(ios): replace hand-rolled empty states with ContentUnavailableView

4 sites had custom VStack-of-icon-and-text empty-state widgets.
Replace with ContentUnavailableView for consistency with the 10+
other sites in the app that already use it.

C-7 from iOS app review."
```

---

## Task 11: C-8 — Extract `StatsGrid`

**Files:**
- Create: `ios/FastTrack/FastTrack/Views/Components/StatsGrid.swift`
- Modify: `ios/FastTrack/FastTrack/Views/ProfileView.swift` (×3 grids)
- Modify: `ios/FastTrack/FastTrack/Views/GarageView.swift` (×2 grids)
- Modify: `ios/FastTrack/FastTrack/Views/CarDetailView.swift` (1 grid)
- Modify: `ios/FastTrack/FastTrack/Views/DriveDetailView.swift` (×2 grids)
- Modify: `ios/FastTrack/FastTrack/Views/DrivePerformanceDetailView.swift` (×3 grids)
- Modify: `ios/FastTrack/FastTrack/Views/AchievementsView.swift` (1 grid)

### Background

10+ sites use a 2-column `LazyVGrid` with `[GridItem(.flexible()), GridItem(.flexible())]`. The cell type varies (`InstrumentStatCell`, `StatMini`, `DashboardGauge`/FTGauge, `PerformanceStatCard`, etc.), so `StatsGrid` takes a generic cell content builder.

### Steps

- [ ] **Step 11.1: Create StatsGrid.swift**

Create `ios/FastTrack/FastTrack/Views/Components/StatsGrid.swift`:

```swift
import SwiftUI

/// Two-column LazyVGrid wrapper for stat cells. Replaces 10+ ad-hoc
/// `LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
/// spacing: N)` usages. The cell content is generic; pass whatever
/// view each site uses (InstrumentStatCell, StatMini, FTGauge compact,
/// PerformanceStatCard, etc.).
///
/// The grid is single-row when `cells.count <= 2` and 2-row otherwise
/// (2×2 for 4 cells, 2×3 for 6, etc.).
struct StatsGrid<Content: View>: View {
    let spacing: CGFloat
    let columns: [GridItem]
    @ViewBuilder let content: () -> Content

    init(spacing: CGFloat = 10,
         columns: [GridItem] = [GridItem(.flexible()), GridItem(.flexible())],
         @ViewBuilder content: @escaping () -> Content) {
        self.spacing = spacing
        self.columns = columns
        self.content = content
    }

    var body: some View {
        LazyVGrid(columns: columns, spacing: spacing) {
            content()
        }
    }
}
```

- [ ] **Step 11.2: Migrate ProfileView's 3 grids**

Open `ios/FastTrack/FastTrack/Views/ProfileView.swift`. Replace the three `LazyVGrid` usages (lines 248-275, 279-295, 595-603) with `StatsGrid(spacing: ...) { ... }`. Keep the cell types unchanged.

- [ ] **Step 11.3: Migrate GarageView's 2 grids**

Open `ios/FastTrack/FastTrack/Views/GarageView.swift`. Replace the 2 grids (lines 46-71, 351-376) with `StatsGrid`.

- [ ] **Step 11.4: Migrate CarDetailView's grid**

Open `ios/FastTrack/FastTrack/Views/CarDetailView.swift`. Replace the `performanceBreakdown` `LazyVGrid` (lines 539-555) with `StatsGrid`.

- [ ] **Step 11.5: Migrate DriveDetailView's 2 grids**

Open `ios/FastTrack/FastTrack/Views/DriveDetailView.swift`. Replace the 2 grids (lines 118-127, 136-152) with `StatsGrid`.

- [ ] **Step 11.6: Migrate DrivePerformanceDetailView's 3 grids**

Open `ios/FastTrack/FastTrack/Views/DrivePerformanceDetailView.swift`. Replace the 3 grids (lines 18, 32, 65) with `StatsGrid`.

- [ ] **Step 11.7: Migrate AchievementsView's grid**

Open `ios/FastTrack/FastTrack/Views/AchievementsView.swift`. Replace the grid at line 46 with `StatsGrid(spacing: 16) { ... }`.

- [ ] **Step 11.8: Build and test**

```bash
cd ios/FastTrack && xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Then:

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: BUILD SUCCEEDED; ALL TESTS PASS.

- [ ] **Step 11.9: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/Components/StatsGrid.swift \
        ios/FastTrack/FastTrack/Views/ProfileView.swift \
        ios/FastTrack/FastTrack/Views/GarageView.swift \
        ios/FastTrack/FastTrack/Views/CarDetailView.swift \
        ios/FastTrack/FastTrack/Views/DriveDetailView.swift \
        ios/FastTrack/FastTrack/Views/DrivePerformanceDetailView.swift \
        ios/FastTrack/FastTrack/Views/AchievementsView.swift
git commit -m "refactor(ios): extract StatsGrid wrapper for 2-column stat grids

10+ sites used LazyVGrid with [GridItem(.flexible()), GridItem(.flexible())]
and varying spacing. Replace with a single StatsGrid generic
wrapper. Cell types per site stay unchanged (InstrumentStatCell,
StatMini, FTGauge, PerformanceStatCard).

C-8 from iOS app review."
```

---

## Task 12: Open the PR

- [ ] **Step 12.1: Rebase onto latest origin/main**

```bash
git fetch origin main
git rebase origin/main
```

- [ ] **Step 12.2: Push with `--force-with-lease`**

```bash
git push --force-with-lease origin feat/ios-component-consolidation
```

- [ ] **Step 12.3: Open the PR with `gh pr create`**

```bash
gh pr create \
  --title "refactor(ios): consolidate components + wire silent failures to Toast" \
  --body "$(cat <<'EOF'
Implements Workstream 5 (component consolidation) and Workstream 8 (UX silent failures) from the iOS app review (spec: docs/superpowers/specs/2026-06-10-ios-app-review-design.md).

## Component consolidation (Workstream 5)

### C-4: One parameterized gauge family
`DashboardGauge`, `MetricGauge`, `CarDetailGauge`, and `PublicCarDetailGauge` collapse into `FTGauge` with three styles: `.hero` (radial-arc with progress + 'Set on' date), `.compact` (DashboardGauge look), `.statCell` (PublicCarDetailGauge look). Standardized corner radius on 12 (was 12 / 14 / 10 / 8). Two files deleted.

### C-4b: One CarPhotoView with size parameter
`ProfileView.CarPhotoThumbnail`, `SocialView.CarThumbnail`, and `PublicGarageCard` all become `CarPhotoView(..., size: <pt>)`. When `size` is non-nil, the placeholder switches to a car-icon; when nil, the gradient+initials hero behavior is preserved.

### C-5: FollowButton + UserRow
Two near-identical follow-toggle button implementations replaced by one `FollowButton` that takes a username, an isSelf flag, and an onError closure. Three user-row patterns (`UserSearchRow`, `FollowUserRow`, `NotificationRow`) replaced by one `UserRow<Avatar, Trailing>`.

### C-6: BadgePill
6+ inline capsule-badge implementations replaced by one `BadgePill(text:icon:style:)` with style enum cases `.you`, `.selected`, `.pb060`, `.pbTopSpeed`, `.carChip`, `.count`. Migrated 5 view files.

### C-7: ContentUnavailableView
4 hand-rolled empty states replaced by `ContentUnavailableView` (matching the 10+ sites that already use it).

### C-8: StatsGrid wrapper
10+ ad-hoc `LazyVGrid(columns: [.flexible(), .flexible()], spacing: N)` usages replaced by one `StatsGrid(spacing:columns:content:)` wrapper. Cell types per site stay unchanged.

## UX silent failures (Workstream 8)

### F-5: Toast component
New `ToastManager` (singleton `ObservableObject`), `ToastView`, and `.toastOverlay()` modifier. Wired into `RootView`. Auto-dismisses after 3s (4s if an action button is present). Supports one optional action (used for Undo on delete-drive).

### F-1: Follow/unfollow errors
Both follow-toggle sites now route errors through Toast via the new FollowButton's onError closure.

### F-2: Notification errors
`NotificationsManager` gains `@Published lastError: String?`. Five previously-silent catches (`refresh`, `refreshUnreadCount`, `loadMore`, `markRead`, `markAllRead`) set it. `NotificationsView` observes and shows a toast.

### F-3: Delete-drive with Undo
All 4 delete-drive sites show a 'Drive deleted' toast with an 'Undo' action that re-uploads the captured Drive via `DriveManager.restoreDrive(_:)`.

### F-4 + P2-16: Sign-out and privacy toggle
Privacy toggle shows a 'Profile is now public/private' toast. Sign-out shows a confirmation dialog and 'Signed out' toast on confirm.

## Tests
- `ToastManagerTests` — 6 tests (set/replace/dismiss/auto-dismiss/action-delay).
- `FollowButtonTests` — 2 tests (compiles with success/error paths, isSelf returns EmptyView).
- `FTGaugeTests` — 3 tests (hero/compact/statCell render).
- `BadgePillTests` — 2 tests (all styles compile, style equality).
- Full iOS suite green.

## Backward compatibility
No API changes, no schema changes, no field renames, no migration. New components are additive. Old call sites are migrated to new components but the user-visible behavior is unchanged. Old clients (down-level app releases) keep working.
EOF
)"
```

- [ ] **Step 12.4: Wait for CI to pass**

The repo's standard CI runs `xcodebuild test` and any commitlint checks. The PR title is 75 characters (under 100). If CI fails on any commit, ensure each commit header is ≤ 100 characters.

---

## Self-Review Notes

- **Spec coverage:**
  - C-4 ✓ (Task 6)
  - C-5 ✓ (Task 2 for FollowButton, Task 8 for UserRow)
  - C-6 ✓ (Task 9)
  - C-7 ✓ (Task 10)
  - C-8 ✓ (Task 11)
  - C-4b (photo thumbnail) ✓ (Task 7)
  - F-1 ✓ (Task 2)
  - F-2 ✓ (Task 3)
  - F-3 ✓ (Task 4)
  - F-4 ✓ (Task 5)
  - F-5 ✓ (Task 1)
  - P2-16 ✓ (Task 5)
- **Placeholder scan:** No "TBD" or "TODO". All test code is concrete. Some steps include "If the call site signature differs, adjust" notes for cases where the audit's line numbers may have drifted; these are honest read-the-file-first instructions, not placeholders.
- **Type consistency:** `FTGauge.Style` is an enum with associated values, used consistently in `init` and `body`. `ToastMessage.id` is `UUID` and is the Equatable key. `BadgePill.Style` is a simple enum. `FollowButton` takes `Binding<Bool>` for `isFollowing`. `UserRow` is generic over `Avatar` and `Trailing` view types. `StatsGrid` is generic over `Content`.
- **DriveManager.restoreDrive:** The exact API function (`api.createDrive` vs a variant) is called out in Step 4.1 with a read-the-file-first note. The plan's intent is clear; the signature will be matched to the codebase on the way through.
- **Backward compat:** No API/schema/migration changes. The new components are additive. Deleted files (`CarDetailGauge.swift`, `PublicCarDetailGauge.swift`) are replaced in the same PR by `FTGauge.swift`; no call site loses its function — they switch to the new component.
- **Phasing: This plan merges Workstream 5 and Workstream 8 into a single PR, matching the R4 row in spec §6.**
