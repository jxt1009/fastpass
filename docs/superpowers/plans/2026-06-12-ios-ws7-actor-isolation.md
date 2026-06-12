# Workstream 7, Track D — Actor isolation (`@MainActor` on `DriveManager` + URLSessionDelegate hook)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Address E-2 (`@MainActor` on `DriveManager` with `nonisolated` heavy math) and E-15 (URLSessionDelegate hook for the cert-pinning foundation in Workstream 12 / J-1). This track lands **last** because it touches every recording-path file and would create merge conflicts with tracks A/B/C.

**Why last:** The actor isolation change cascades — every call site of `DriveManager` (and its extensions) needs a concurrency check. Doing this on a stable surface (after A/B/C are merged) avoids triple-rebase pain. The URLSessionDelegate hook is additive and can land earlier in the same PR; the actual pinning rules are Workstream 12.

**Spec reference:** §5 Workstream 7, §7 Resolved Decisions, §11 (R5 release notes).

**File ownership for track D** (after A+B+C are merged to a release branch):
- `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift` — `@MainActor` annotation
- `ios/FastTrack/FastTrack/ViewModels/DriveManager+Processing.swift` — nonisolated heavy math
- `ios/FastTrack/FastTrack/ViewModels/DriveManager+LiveActivity.swift` — nonisolated ActivityKit calls
- `ios/FastTrack/FastTrack/ViewModels/RecordingActor.swift` — already an actor; verify Sendable conformance
- `ios/FastTrack/FastTrack/Services/AuthManager.swift` — `@MainActor` annotation
- `ios/FastTrack/FastTrack/Services/APIService.swift` — add `URLSessionDelegate` stub (no cert pinning yet; Workstream 12 owns that)
- `ios/FastTrack/FastTrack/ViewModels/RouteSerializer.swift` — `Sendable` verification
- `ios/FastTrack/FastTrack/Models/Drive.swift` — `Sendable` verification
- Tests under `ios/FastTrack/FastTrackTests/`

**Out of scope for this plan:**
- E-2's `LiveActivity update task` coalescing (E-11) — handled in track A's Task 14 if not already done
- E-15's actual pinning rules — Workstream 12 (J-1, J-2, J-3)

---

## File Structure

### Modify

- `DriveManager.swift` — `@MainActor` class annotation
- `DriveManager+Processing.swift` — `nonisolated` on heavy math methods, isolated access for shared state
- `DriveManager+LiveActivity.swift` — `nonisolated` on ActivityKit calls
- `AuthManager.swift` — `@MainActor` annotation
- `APIService.swift` — `URLSessionDelegate` stub, expose to be picked up by Workstream 12
- `RecordingActor.swift` — `Sendable` conformance check (already an actor; should be fine)
- `RouteSerializer.swift` — `Sendable` conformance
- `Drive.swift` — `Sendable` conformance check

### New tests

- `ios/FastTrack/FastTrackTests/DriveManagerConcurrencyTests.swift` — strict-concurrency build attempt + concurrent test exercising `processLocation` / `processSpeedSample` interleavings
- `ios/FastTrack/FastTrackTests/AuthManagerConcurrencyTests.swift` — keychain access from nonisolated context

---

## Task 1: `@MainActor` on `DriveManager`

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift`

- [ ] **Step 1: Annotate the class**

```swift
@MainActor
final class DriveManager: ObservableObject {
    // ...
}
```

`@MainActor` is implied for `ObservableObject` in some recent Swift modes; verify the build doesn't already include it. The explicit annotation is the contract.

- [ ] **Step 2: Mark heavy-math methods `nonisolated`**

In `DriveManager+Processing.swift`, methods that don't touch `@Published` state and run expensive computation should be `nonisolated`. For each one, decide:

- `processLocationHeavy(_:speed:speedMph:)` — currently runs in a `Task.detached`. The body reads `RecordingActor` (already an actor). Mark `nonisolated`. The method itself does not read or write `self`'s `@Published` state.

- `processHeadingBackground` (deleted in track B) — skip.

- `processSpeedSample` — reads/writes `@Published currentDrive`, `currentMaxSpeed`, `best060Time`, `attempts060`. Cannot be `nonisolated`. Stays on the main actor.

- `updateCurrentDrive` — reads `recordingLocations`, `recordingStartTime`, `runningSpeedStats`, `stoppedTimeTracker`, `currentMaxSpeed`, and writes `currentDrive`. Stays on main (or is broken into pieces; see step 3).

- `routePointSpeed(for:)` — pure function, takes `CLLocation`, reads `latestSpeedSample` (which is a class-level var). Move `latestSpeedSample` to be set on the main actor only; mark the read site as a `nonisolated` pure function that takes the sample as an argument.

- [ ] **Step 3: Refactor `updateCurrentDrive` for the actor split**

The current body is on the main thread. With `@MainActor`, the same is true. The hot path here is the O(n) distance loop, which is now incremental (D-4). The remaining body just reads scalars and writes one `@Published drive`. No further split needed.

- [ ] **Step 4: Build + test**

Run `xcodebuild build-for-testing` and `xcodebuild test`. Fix any concurrency warnings.

- [ ] **Step 5: Commit**

`fix(ios): annotate DriveManager @MainActor (E-2)`

---

## Task 2: `@MainActor` on `AuthManager`

**Files:**
- Modify: `ios/FastTrack/FastTrack/Services/AuthManager.swift`

- [ ] **Step 1: Annotate + mark keychain accessors `nonisolated`**

The Keychain calls are thread-safe at the OS level. Mark the keychain accessors `nonisolated` and move them to a private struct. Keep `signIn` / `signOut` / `isAuthenticated` reads and writes on the main actor.

- [ ] **Step 2: Build + test + commit**

`fix(ios): annotate AuthManager @MainActor (E-2)`

---

## Task 3: `Sendable` conformance pass

**Files:**
- Modify: `ios/FastTrack/FastTrack/Models/Drive.swift`
- Modify: `ios/FastTrack/FastTrack/ViewModels/RouteSerializer.swift`

- [ ] **Step 1: Verify `Drive: Sendable`**

If all stored properties are themselves `Sendable` (after E-10 fixes the `@retroactive` warning), `Sendable` conformance is auto-synthesized. If `URL`, `Date`, and the route point tuple are all `Sendable` (they are), add `: Sendable` to the `Drive` declaration.

- [ ] **Step 2: Verify `RouteSerializer.Snapshot: Sendable`**

Already documented as `Sendable` in earlier plans; verify the `richRoutePoints` tuple is treated as `Sendable` (it is, since all fields are `Double`).

- [ ] **Step 3: Commit**

`chore(ios): confirm Sendable conformance on Drive and RouteSerializer (E-2)`

---

## Task 4: URLSessionDelegate stub (E-15 foundation)

**Files:**
- Modify: `ios/FastTrack/FastTrack/Services/APIService.swift`

- [ ] **Step 1: Add the delegate**

```swift
final class PinningURLSessionDelegate: NSObject, URLSessionDelegate {
    // Workstream 12 (J-1) will fill in the SPKI pinning rules.
    // For now, accept all server certificates.
    func urlSession(_ session: URLSession,
                    didReceive challenge: URLAuthenticationChallenge,
                    completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        completionHandler(.performDefaultHandling, nil)
    }
}
```

- [ ] **Step 2: Wire it into the URLSession**

In `APIService`, replace `URLSession.shared` with a session that uses the delegate. E-15 says "no URLSessionDelegate → no opportunity for cert pinning"; this task is the foundation Workstream 12 needs.

- [ ] **Step 3: Test + commit**

`feat(ios): add URLSessionDelegate stub for future cert pinning (E-15 foundation)`

---

## Task 5: Concurrent stress test

**Files:**
- New: `ios/FastTrack/FastTrackTests/DriveManagerConcurrencyTests.swift`

- [ ] **Step 1: Write the test**

```swift
import XCTest
@testable import FastTrack

final class DriveManagerConcurrencyTests: XCTestCase {
    @MainActor
    func test_concurrentProcessLocationAndSpeedSample() async {
        let mgr = DriveManager.shared
        mgr.startRecordingForTest()
        // Spawn 1000 location + 1000 speedSample calls interleaved.
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<500 {
                group.addTask { @MainActor in
                    let loc = CLLocation(latitude: 37, longitude: -122)
                    mgr.processLocation(loc)
                }
                group.addTask { @MainActor in
                    let sample = SpeedSample(speed: 10, timestamp: Date())
                    mgr.processSpeedSample(sample)
                }
            }
        }
        mgr.stopRecordingForTest()
    }
}
```

- [ ] **Step 2: Commit**

`test(ios): concurrent stress test for DriveManager (E-2)`

---

## Task 6: Swift 6 strict-concurrency check

- [ ] **Step 1: Enable strict concurrency in a sandbox branch**

```bash
git checkout -b chore/swift6-strict-concurrency-check
# In the Xcode build settings, set `SWIFT_STRICT_CONCURRENCY = complete`
# for the FastTrack target.
xcodebuild build-for-testing \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO \
  OTHER_SWIFT_FLAGS="-strict-concurrency=complete"
```

- [ ] **Step 2: Fix warnings, file follow-up PRs for anything that can't be fixed in this batch**

If the strict-concurrency build surfaces 5+ warnings, file them as a follow-up issue. Don't block the merge on them.

- [ ] **Step 3: Commit + report**

`chore(ios): Swift 6 strict-concurrency build report (E-2)`

---

## Final verification

- [ ] `xcodebuild build-for-testing` — passes
- [ ] `xcodebuild test` — all green
- [ ] Manual: Swift 6 strict-concurrency build attempt passes (or warnings are documented as follow-up)
- [ ] Manual: drive-record-stop cycle on a real device still works (backgrounding, sign-out mid-drive, kill mid-upload)

## Open the PR

Title: `fix(ios): actor isolation + URLSessionDelegate foundation (E-2, E-15)`

Body: list the items addressed (E-2, E-15-foundation, plus the Sendable conformance pass), link spec §11. Note that the actual cert-pinning rules are Workstream 12.

## Decision log

- 2026-06-12: For E-15, do we add the URLSessionDelegate stub now (foundation only) or wait for Workstream 12? **Decision:** add the stub now. It's a 10-line change with zero behavior risk and unblocks Workstream 12.
- 2026-06-12: For E-2, the `processLocationHeavy` is already in `Task.detached` — does adding `nonisolated` to the method change anything? **Decision:** no behavioral change, but explicit `nonisolated` makes the contract visible to reviewers and helps future maintainers avoid implicit boundary violations.
