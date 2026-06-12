# Workstream 7, Track C — Stability & concurrency (non-recording items)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Eliminate force-unwrap landmines, `fatalError` on multi-scene sign-in, the empty-input `split` crash, the `URL(string: "")` non-nil trap, and the `NotificationsManager` token-leak. E-2 (DriveManager `@MainActor` + nonisolated heavy math) and E-15 (URLSessionDelegate hook for cert pinning foundation) are deferred to track D because they touch every recording-path file.

**Spec reference:** §5 Workstream 7 and §11 (R5 release notes).

**File ownership for track C** (do NOT touch files outside this list without coordinating):
- `ios/FastTrack/FastTrack/Services/AppleSignInManager.swift` (E-1)
- `ios/FastTrack/FastTrack/Services/GoogleSignInManager.swift` (E-1)
- `ios/FastTrack/FastTrack/Services/AuthManager.swift` (E-3, token-leak only — full `@MainActor` annotation deferred to track D)
- `ios/FastTrack/FastTrack/Services/NotificationsManager.swift` (E-12)
- `ios/FastTrack/FastTrack/Views/SocialView.swift:217-218` (E-4)
- `ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift:113` (E-5)
- `ios/FastTrack/FastTrack/Views/Components/CarPhotoEditorSection.swift:110` (E-9)
- `ios/FastTrack/FastTrack/Views/DriveDetailView.swift:329,335,557-562` (E-7, E-8)
- `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift:167` (E-14)
- `ios/FastTrack/FastTrack/Models/Drive.swift:309-313` (E-10 — `@retroactive` warning cleanup)
- Tests under `ios/FastTrack/FastTrackTests/`

**Out of scope for this plan:**
- E-2 (`@MainActor` on `DriveManager`) — track D
- E-15 (URLSessionDelegate for pinning) — track D (foundation only; pinning rules themselves are Workstream 12 / J-1)
- E-6 (folded into D-8) — track B
- E-13 (already fixed in R2) — verify before skipping
- E-11 (already addressed in R2) — verify before skipping

---

## File Structure

### Modify

- `AppleSignInManager.swift` — replace `fatalError` with error-throwing or async-recover
- `GoogleSignInManager.swift` — same
- `AuthManager.swift` — token for in-flight operations (E-3, partial — see note)
- `NotificationsManager.swift` — token-based refresh cancellation
- `SocialView.swift` — guard `parts.first` explicitly
- `PublicCarDetailView.swift` — `car.photoUrl.flatMap { URL(string: $0) }`
- `CarPhotoEditorSection.swift` — `existingPhotoURL?.isEmpty ?? true`
- `DriveDetailView.swift` — replace `first!` / `last!` / `min()!` / `max()!` with safe access
- `DriveManager.swift:167` — guard `recordingStartTime` before force-print
- `Drive.swift:309-313` — drop `@retroactive`, use a wrapper Equatable for `CLLocationCoordinate2D` if needed

### New tests

- `ios/FastTrack/FastTrackTests/ForceUnwrapAuditTests.swift` — every site that previously force-unwrapped; verify the safe path still works on empty/single-element input
- `ios/FastTrack/FastTrackTests/NotificationsManagerTokenTests.swift` — sign-out mid-refresh cancels cleanly

---

## Task 1: E-1 — Replace `fatalError("No window available")`

**Files:**
- Modify: `ios/FastTrack/FastTrack/Services/AppleSignInManager.swift`
- Modify: `ios/FastTrack/FastTrack/Services/GoogleSignInManager.swift`

- [ ] **Step 1: Apple**

Read the surrounding context (lines 180-200). Replace the fatal path with a delegate callback that calls `signInCoordinator?.appleSignIn(didFailWith: APIError.noWindowScene)`. Add `case noWindowScene` to `APIError` if it doesn't exist. Use the existing error-surfacing path used by other sign-in failures (F-1 pattern from R4: surface via Toast or a completion-handler error).

- [ ] **Step 2: Google**

Same pattern at `GoogleSignInManager.swift:167`.

- [ ] **Step 3: Tests**

Add a unit test that constructs the managers with no root window and verifies the error is surfaced (not crashed). Use the existing `SignInCoordinator` if present.

- [ ] **Step 4: Commit**

`fix(ios): replace fatalError in sign-in managers with error path (E-1)`

---

## Task 2: E-4 — Guard `parts.first` in `SocialView.swift:217`

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/SocialView.swift`

- [ ] **Step 1: Replace the check**

```swift
let make = String(parts.first ?? "")
```

- [ ] **Step 2: Test + commit**

`fix(ios): guard parts.first in SocialView (E-4)`

---

## Task 3: E-5 — `URL(string:)` only on non-empty photo URL

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift:113`

- [ ] **Step 1: Replace**

```swift
if let s = car.photoUrl, !s.isEmpty, let url = URL(string: s) {
    AsyncImage(url: url) { ... }
} else {
    placeholder
}
```

(Per the F-2/R4 toast pattern, the same site may already be partially fixed — verify the existing code first.)

- [ ] **Step 2: Commit**

`fix(ios): guard URL parsing on empty photoUrl in PublicCarDetailView (E-5)`

---

## Task 4: E-9 — `existingPhotoURL?.isEmpty ?? true`

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/Components/CarPhotoEditorSection.swift:110`

- [ ] **Step 1: Replace**

```swift
pickedImage != nil || (existingPhotoURL?.isEmpty == false)
```

(Or `!(existingPhotoURL?.isEmpty ?? true)` to preserve original short-circuit behavior.)

- [ ] **Step 2: Commit**

`fix(ios): drop force-unwrap on existingPhotoURL in photo editor (E-9)`

---

## Task 5: E-7 — `routeCoordinates.first!` / `.last!` in `DriveDetailView.swift:329,335`

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/DriveDetailView.swift:329,335`

- [ ] **Step 1: Replace with safe access**

The `Annotation` block is inside an `if !routeCoordinates.isEmpty` guard at line 264 already. Add a `guard let first = routeCoordinates.first, let last = routeCoordinates.last` inside that block, or use `if let first = routeCoordinates.first { ... }`.

- [ ] **Step 2: Commit**

`fix(ios): drop routeCoordinates first!/last! force-unwraps (E-7)`

---

## Task 6: E-8 — `min()!` / `max()!` in `regionForRoute` (DriveDetailView:550-562)

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/DriveDetailView.swift:550-562`

- [ ] **Step 1: Replace**

The function already guards `!routeCoordinates.isEmpty`. The `min()` and `max()` calls on non-empty arrays return non-optional. Drop the `!`. No behavior change, just hygiene.

- [ ] **Step 2: Commit**

`fix(ios): drop redundant min()! / max()! in regionForRoute (E-8)`

---

## Task 7: E-14 — `recordingStartTime!` debug print

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift:167`

- [ ] **Step 1: Replace**

```swift
if let start = recordingStartTime {
    print("⏰ Recording start time: \(start)")
}
```

- [ ] **Step 2: Commit**

`chore(ios): guard recordingStartTime debug print (E-14)`

---

## Task 8: E-10 — Drop `@retroactive` warning on `CLLocationCoordinate2D`

**Files:**
- Modify: `ios/FastTrack/FastTrack/Models/Drive.swift:309-313`

- [ ] **Step 1: Replace with a wrapper type**

The simplest fix is to remove the conformance and let `Drive` synthesize `Equatable` without it. The route points field uses `[CLLocationCoordinate2D]?` — check whether that breaks `Equatable`. If it does, introduce a `Coordinate: Equatable` struct in `Models/` and migrate the field. (This may be out of scope for a "stability" PR — if the migration is wide, defer the field change and just silence the warning by adding `// swift(>=6.0) ignore retroactive` or by making the conformance a private extension on a wrapper struct. The simplest acceptable change: write a custom `Equatable` for `Drive` that compares the route points array manually using `zip` and `==` on individual coords.)

- [ ] **Step 2: Test + commit**

`fix(ios): drop @retroactive warning on CLLocationCoordinate2D (E-10)`

---

## Task 9: E-3 (partial) — `AuthManager` token-based in-flight cancellation

**Files:**
- Modify: `ios/FastTrack/FastTrack/Services/AuthManager.swift`

This is the **minimum-viable** part of E-3 — full `@MainActor` annotation is track D. The risk addressed here: in-flight `signIn` completions that fire after `signOut` corrupting `isAuthenticated` state.

- [ ] **Step 1: Add a UUID token to sign-in / sign-out transitions**

```swift
private var sessionToken: UUID = UUID()

func signIn() async {
    let myToken = UUID()
    await MainActor.run { self.sessionToken = myToken }
    do {
        let token = try await performSignIn()
        guard await MainActor.run({ self.sessionToken == myToken }) else { return }
        await MainActor.run {
            self.isAuthenticated = true
            self.token = token
        }
    } catch {
        guard await MainActor.run({ self.sessionToken == myToken }) else { return }
        // surface error to caller
    }
}

func signOut() {
    sessionToken = UUID()
    isAuthenticated = false
    // existing clearLocalData, etc.
}
```

- [ ] **Step 2: Test + commit**

`fix(ios): guard AuthManager in-flight sign-in against post-signout races (E-3 partial)`

---

## Task 10: E-12 — `NotificationsManager` token-based refresh cancellation

**Files:**
- Modify: `ios/FastTrack/FastTrack/Services/NotificationsManager.swift`

- [ ] **Step 1: Add a token**

```swift
private var sessionToken: UUID = UUID()

func refresh() async {
    let myToken = UUID()
    await MainActor.run { self.sessionToken = myToken }
    do {
        let notifs = try await performFetch()
        guard await MainActor.run({ self.sessionToken == myToken }) else { return }
        // assign
    } catch {
        guard await MainActor.run({ self.sessionToken == myToken }) else { return }
        // set lastError (per F-2 / R4)
    }
}

func cancelInFlight() {
    sessionToken = UUID()
}
```

Call `cancelInFlight()` from `AuthManager.signOut` (which is in the same plan as Task 9) so a sign-out stops the polling Task from writing to the now-stale instance.

- [ ] **Step 2: Test + commit**

`fix(ios): add sessionToken to NotificationsManager to cancel in-flight refresh (E-12)`

---

## Task 11: Force-unwrap audit test (E-7/E-8/E-9/E-14 in one regression suite)

**Files:**
- New: `ios/FastTrack/FastTrackTests/ForceUnwrapAuditTests.swift`

- [ ] **Step 1: Write a single test file that exercises the safe paths with empty/single-element inputs**

```swift
import XCTest
@testable import FastTrack

final class ForceUnwrapAuditTests: XCTestCase {

    func test_DriveDetailView_emptyRouteCoordinates() {
        // Construct a DriveDetailView with no route; the Annotation
        // block must not crash.
    }

    func test_PhotoEditorSection_existingPhotoURLEmpty() {
        // Test the "should we show the save button?" predicate.
    }

    // ...
}
```

If the views are not easily unit-testable in isolation, lean on `xcodebuild test`'s screenshot UI tests or skip this task and rely on the manual verification checklist.

- [ ] **Step 2: Commit**

`test(ios): regression suite for force-unwrap cleanup (E-7/8/9/14)`

---

## Final verification

- [ ] `xcodebuild build-for-testing` — passes
- [ ] `xcodebuild test` — all green
- [ ] Crash-test: multi-scene sign-in (open the app on iPad with two scenes, sign in on one, sign out on the other — the `fatalError` site must no longer crash)
- [ ] `bundle exec fastlane test` — UI walkthrough

## Open the PR

Title: `fix(ios): stability & concurrency pass (Workstream 7, track C)`

Body: list the items addressed (E-1, E-3-partial, E-4, E-5, E-7, E-8, E-9, E-10, E-12, E-14), link spec §11. Note that E-2 and E-15 land in track D.

## Decision log

- 2026-06-12: For E-10, prefer a custom `Drive.==` that zips the route points array, or a wrapper `Coordinate` struct? **Decision:** custom `==` is the smaller diff. Use it unless it breaks the existing `RecordingActor` snapshot path.
- 2026-06-12: For E-3 partial, do we want `sessionToken` checked from a detached task via `await MainActor.run`? Or do we just hold an actor reference? **Decision:** use `await MainActor.run` for parity with the rest of `AuthManager` — full `@MainActor` migration is track D.
