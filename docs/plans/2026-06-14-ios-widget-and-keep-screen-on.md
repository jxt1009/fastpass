# iOS Widget Lifecycle + Keep-Screen-On Scope Fixes

**Goal:** Fix two user-reported bugs and tighten the Live Activity ("widget") integration: (1) the Live Activity no longer dismisses when the user stops recording from inside the app, (2) the "Keep Screen On While Recording" setting prevents the screen from sleeping even when the app is open without an active drive. Also add a brief "Drive ended" summary state to the Live Activity before it dismisses.

**Architecture:**
- Introduce a `LiveActivityController` protocol so the coordinator can be mocked in unit tests, mirroring the `DriveAPI` pattern (see project memory `ARCHITECTURE`).
- Make Live Activity lifecycle operations `async` so `DriveManager.stopRecording` actually waits for the dismissal before returning.
- Add a centralized `ScreenWakeController` that owns `UIApplication.shared.isIdleTimerDisabled`. It computes wake state from `(isRecording, keepScreenOn, scenePhase)` so any path that flips one of those inputs syncs the system flag without the caller having to remember.
- Add a `phase` (recording / ended) and `elapsedSeconds` to `DriveActivityAttributes.ContentState` so the widget can render a final summary; decode with defaults to stay forward/backward compatible across in-flight activities.

**Tech Stack:** Swift, SwiftUI, ActivityKit, WidgetKit, Combine, XCTest.

---

## Background: Root-Cause Analysis

### Bug 1 (Live Activity not dismissed)

Verified the call chain `ContentView` → `DriveManager.stopRecording()` → `LiveActivityCoordinator.endLiveActivity()` exists, but:

1. `endLiveActivity()` uses an unstructured `Task {}` and returns before `activity.end(...)` runs. If the app is suspended mid-dismissal — or `end()` throws — the activity orphans on the lock screen forever.
2. `Activity<DriveActivityAttributes>.activities` is never consulted for orphan recovery on launch, so once an activity is orphaned it cannot be reached again.
3. `updateLiveActivity(...)` is defined but never called anywhere in the app. The widget shows the initial zero state for the entire drive; only the SwiftUI `Text(timerInterval: startDate...distantFuture)` keeps ticking — and because it's bound to the immutable `startDate` attribute, the only way to stop it is to dismiss the activity.
4. The `startLiveActivity` `catch` block is empty, swallowing failures silently.

### Bug 2 (Keep-screen-on too broad)

`UIApplication.shared.isIdleTimerDisabled` is touched in exactly two places (`DriveRecordingController.swift:202` and `:246`), both gated to `startRecording`/`stopRecording`. Static analysis says the code is correct.

User verified the bug repros on a fresh launch with no recording ever started, so the truth on device differs from what the code suggests. Most likely causes:

- An earlier process kept the flag set, the app was suspended (not terminated) between launches, and `isIdleTimerDisabled` survived in some edge case.
- A system / SwiftUI interaction (e.g. continuous `Map` animations) is keeping the screen awake independent of our flag, and the user reasonably assumes our setting is responsible because the label promises it isn't.

Either way, the existing code is too passive — it only writes the flag at recording start/stop. The defensive fix is to actively re-assert the correct value on every scene-phase transition and on every `keepScreenOn` toggle, and to centralize that decision in one place so future code can't accidentally desync it.

### "Drive ended" summary

Live Activities can stay visible after `end()` via `dismissalPolicy: .after(date)`. We push a final `phase = .ended` state with locked-in stats and elapsed time, then auto-dismiss ~4 seconds later. The widget renders a static "Drive complete" card during that window.

---

## File Structure

**Created:**
- `ios/FastTrack/FastTrack/Services/ScreenWakeController.swift` — single owner of `isIdleTimerDisabled`.
- `ios/FastTrack/FastTrack/ViewModels/LiveActivityController.swift` — protocol abstraction (the file also re-homes the protocol; the concrete `LiveActivityCoordinator` stays where it is).
- `ios/FastTrack/FastTrackTests/ScreenWakeControllerTests.swift`
- `ios/FastTrack/FastTrackTests/LiveActivityCoordinationTests.swift` — exercises `DriveManager` against a `MockLiveActivityController` to lock in the new lifecycle contract.

**Modified:**
- `ios/FastTrack/FastTrack/Models/DriveActivityAttributes.swift` — add `phase`, `elapsedSeconds`, custom `init(from:)` with defaults.
- `ios/FastTrack/FastTrackWidgets/DriveActivityAttributes.swift` — mirror exactly.
- `ios/FastTrack/FastTrackWidgets/DriveActivityWidget.swift` — render `.ended` phase as a summary card; switch timer source for the ended phase.
- `ios/FastTrack/FastTrack/ViewModels/LiveActivityCoordinator.swift` — async lifecycle, error logging, orphan sweep, conform to protocol.
- `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift` — `await endLiveActivity()`, drive a `Combine` pipeline that calls `updateLiveActivity` every ~1 s, push final-state then dismiss after.
- `ios/FastTrack/FastTrack/ViewModels/DriveRecordingController.swift` — remove the two `isIdleTimerDisabled` calls; instead publish state to `ScreenWakeController`.
- `ios/FastTrack/FastTrack/FastTrackApp.swift` — own a `ScreenWakeController`, feed `scenePhase` into it, run orphan sweep on launch.
- `ios/FastTrack/FastTrack/Models/AppSettings.swift` — no signature change; just make `keepScreenOn`'s `didSet` notify the wake controller (via a closure injected at app init, to avoid `AppSettings` learning about UIKit).
- `ios/FastTrack/FastTrack.xcodeproj/project.pbxproj` — register the new files in app and test targets.

**Verification:** all tests pass via `xcodebuild test … -only-testing:FastTrackTests`. Manual smoke on Simulator + real device for the two bugs.

---

## Task 1: Lock in the keep-screen-on contract with a unit test

**Files:**
- Create: `ios/FastTrack/FastTrack/Services/ScreenWakeController.swift`
- Create: `ios/FastTrack/FastTrackTests/ScreenWakeControllerTests.swift`

- [ ] **Step 1: Write the failing test (no implementation yet)**

```swift
// ScreenWakeControllerTests.swift
import XCTest
@testable import FastTrack

final class ScreenWakeControllerTests: XCTestCase {

    final class FakeIdleTimer: IdleTimerControlling {
        private(set) var history: [Bool] = []
        var isIdleTimerDisabled: Bool = false {
            didSet { history.append(isIdleTimerDisabled) }
        }
    }

    func test_idleTimerEnabled_whenAppActive_recording_andSettingOn() {
        let timer = FakeIdleTimer()
        let c = ScreenWakeController(idleTimer: timer)
        c.update(isRecording: true, keepScreenOn: true, scenePhase: .active)
        XCTAssertTrue(timer.isIdleTimerDisabled)
    }

    func test_idleTimerEnabled_onlyWhileRecording_whenSettingOn() {
        let timer = FakeIdleTimer()
        let c = ScreenWakeController(idleTimer: timer)
        c.update(isRecording: false, keepScreenOn: true, scenePhase: .active)
        XCTAssertFalse(timer.isIdleTimerDisabled)
    }

    func test_settingOff_neverDisablesIdleTimer() {
        let timer = FakeIdleTimer()
        let c = ScreenWakeController(idleTimer: timer)
        c.update(isRecording: true, keepScreenOn: false, scenePhase: .active)
        XCTAssertFalse(timer.isIdleTimerDisabled)
    }

    func test_backgroundedScene_alwaysReleasesIdleTimer() {
        let timer = FakeIdleTimer()
        let c = ScreenWakeController(idleTimer: timer)
        c.update(isRecording: true, keepScreenOn: true, scenePhase: .active)
        XCTAssertTrue(timer.isIdleTimerDisabled)
        c.update(isRecording: true, keepScreenOn: true, scenePhase: .background)
        XCTAssertFalse(timer.isIdleTimerDisabled)
    }

    func test_repeatedSameInput_doesNotChurnFlag() {
        let timer = FakeIdleTimer()
        let c = ScreenWakeController(idleTimer: timer)
        c.update(isRecording: true, keepScreenOn: true, scenePhase: .active)
        c.update(isRecording: true, keepScreenOn: true, scenePhase: .active)
        c.update(isRecording: true, keepScreenOn: true, scenePhase: .active)
        XCTAssertEqual(timer.history, [true])
    }
}
```

- [ ] **Step 2: Build, confirm test fails to compile** (`ScreenWakeController` and `IdleTimerControlling` don't exist yet).

- [ ] **Step 3: Write minimal implementation**

```swift
// ScreenWakeController.swift
import SwiftUI
import UIKit

protocol IdleTimerControlling: AnyObject {
    var isIdleTimerDisabled: Bool { get set }
}

extension UIApplication: IdleTimerControlling {}

/// Single owner of `UIApplication.shared.isIdleTimerDisabled`. Recomputes the
/// flag from `(isRecording, keepScreenOn, scenePhase)` so any caller can flip
/// one input and the controller keeps the system flag in sync.
@MainActor
final class ScreenWakeController {
    private let idleTimer: IdleTimerControlling
    private var lastApplied: Bool?

    init(idleTimer: IdleTimerControlling = UIApplication.shared) {
        self.idleTimer = idleTimer
    }

    func update(isRecording: Bool, keepScreenOn: Bool, scenePhase: ScenePhase) {
        let shouldDisable = isRecording && keepScreenOn && scenePhase == .active
        guard shouldDisable != lastApplied else { return }
        lastApplied = shouldDisable
        idleTimer.isIdleTimerDisabled = shouldDisable
    }
}
```

- [ ] **Step 4: Add files to the FastTrack and FastTrackTests targets in `project.pbxproj`** (use Xcode if comfortable; otherwise add by hand mirroring an existing service / test file entry). Confirm the workspace still resolves: `xcodebuild build-for-testing -project ios/FastTrack/FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" CODE_SIGNING_ALLOWED=NO`.

- [ ] **Step 5: Run the new test**

```
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/ScreenWakeControllerTests \
  CODE_SIGNING_ALLOWED=NO
```
Expected: all five tests pass.

- [ ] **Step 6: Commit**

```
git add ios/FastTrack/FastTrack/Services/ScreenWakeController.swift \
        ios/FastTrack/FastTrackTests/ScreenWakeControllerTests.swift \
        ios/FastTrack/FastTrack.xcodeproj/project.pbxproj
git commit -m "feat(ios): add ScreenWakeController for centralized idle-timer control"
```

---

## Task 2: Wire ScreenWakeController into the live app, remove direct idle-timer writes

**Files:**
- Modify: `ios/FastTrack/FastTrack/FastTrackApp.swift`
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveRecordingController.swift:201-203, 246`
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift` (add a hook so AppSettings/scene-phase changes propagate)
- Modify: `ios/FastTrack/FastTrack/Models/AppSettings.swift` (publish keepScreenOn changes via existing `@Published`)

- [ ] **Step 1: Remove the two direct writes**

In `DriveRecordingController.startRecording()` delete lines 201–203:
```swift
        if settings.keepScreenOn {
            UIApplication.shared.isIdleTimerDisabled = true
        }
```
In `DriveRecordingController.stopRecording()` delete line 246:
```swift
        UIApplication.shared.isIdleTimerDisabled = false
```
Also drop the now-unused `import UIKit` if nothing else in the file needs it (it does — `UIApplication.shared.beginBackgroundTask` is still used, so keep it).

- [ ] **Step 2: Hold a `ScreenWakeController` in `FastTrackApp` and feed it `scenePhase`**

Add to `FastTrackApp`:
```swift
@StateObject private var screenWake: ScreenWakeControllerObservable
```
Where `ScreenWakeControllerObservable` is a thin `ObservableObject` wrapper around `ScreenWakeController` so SwiftUI can hold it. (Alternative: keep `ScreenWakeController` final and store as a plain `let` on the App struct; but `App` cannot hold non-State properties that survive re-init reliably. Use `StateObject` of a wrapper.)

Define alongside `ScreenWakeController`:
```swift
@MainActor
final class ScreenWakeControllerObservable: ObservableObject {
    let inner: ScreenWakeController
    init(inner: ScreenWakeController = ScreenWakeController()) { self.inner = inner }
}
```

In `RootView.body`, add:
```swift
.onChange(of: scenePhase) { _, newPhase in
    screenWake.inner.update(
        isRecording: driveManager.isRecording,
        keepScreenOn: settings.keepScreenOn,
        scenePhase: newPhase
    )
    // existing notifications-polling logic stays
}
.onChange(of: driveManager.isRecording) { _, recording in
    screenWake.inner.update(
        isRecording: recording,
        keepScreenOn: settings.keepScreenOn,
        scenePhase: scenePhase
    )
}
.onChange(of: settings.keepScreenOn) { _, keep in
    screenWake.inner.update(
        isRecording: driveManager.isRecording,
        keepScreenOn: keep,
        scenePhase: scenePhase
    )
}
.onAppear {
    screenWake.inner.update(
        isRecording: driveManager.isRecording,
        keepScreenOn: settings.keepScreenOn,
        scenePhase: scenePhase
    )
    // existing onAppear contents stay
}
```

`screenWake` is injected as an `@EnvironmentObject` into the tree alongside the others, mirroring the existing pattern.

- [ ] **Step 3: Build**
```
CGO_ENABLED=1 ... # not relevant; iOS only
xcodebuild build-for-testing \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO
```
Expected: succeeds.

- [ ] **Step 4: Re-run `ScreenWakeControllerTests` to confirm nothing regressed.**

- [ ] **Step 5: Manual smoke (or note as a follow-up): launch app on Simulator, never tap Start, leave it alone — screen should sleep at the OS auto-lock interval.**

- [ ] **Step 6: Commit**

```
git add ios/FastTrack/FastTrack/FastTrackApp.swift \
        ios/FastTrack/FastTrack/ViewModels/DriveRecordingController.swift \
        ios/FastTrack/FastTrack/Services/ScreenWakeController.swift
git commit -m "fix(ios): scope keep-screen-on to active recording via ScreenWakeController"
```

---

## Task 3: Introduce LiveActivityController protocol + lock dismissal in test

**Files:**
- Create: `ios/FastTrack/FastTrack/ViewModels/LiveActivityController.swift`
- Modify: `ios/FastTrack/FastTrack/ViewModels/LiveActivityCoordinator.swift`
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift`
- Create: `ios/FastTrack/FastTrackTests/LiveActivityCoordinationTests.swift`

- [ ] **Step 1: Define the protocol and convert lifecycle methods to async**

`LiveActivityController.swift`:
```swift
import Foundation

@MainActor
protocol LiveActivityController: AnyObject {
    func start(recordingStartTime: Date?) async
    func update(speedMph: Double, distanceMiles: Double, currentGForce: Double, currentMaxSpeed: Double) async
    func end(finalState: DriveActivityAttributes.DriveActivityState?, lingerSeconds: TimeInterval) async
    func dismissAllOrphans() async
}
```

`LiveActivityCoordinator.swift` becomes:
```swift
import Foundation
import ActivityKit
import os

@MainActor
final class LiveActivityCoordinator: LiveActivityController {
    private static let log = Logger(subsystem: "app.fasttrack", category: "live-activity")
    private var liveActivity: Activity<DriveActivityAttributes>?
    private var lastUpdate: Date?

    func start(recordingStartTime: Date?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let startDate = recordingStartTime else { return }
        lastUpdate = nil
        let attrs = DriveActivityAttributes(startDate: startDate)
        let state = DriveActivityAttributes.DriveActivityState(
            phase: .recording,
            speedMph: 0, gForce: 0, distanceMiles: 0, maxSpeedMph: 0,
            elapsedSeconds: 0
        )
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            liveActivity = try Activity<DriveActivityAttributes>.request(
                attributes: attrs, content: content, pushType: nil
            )
        } catch {
            Self.log.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(speedMph: Double, distanceMiles: Double, currentGForce: Double, currentMaxSpeed: Double) async {
        guard let activity = liveActivity else { return }
        let now = Date()
        if let last = lastUpdate, now.timeIntervalSince(last) < 1.0 { return }
        lastUpdate = now
        let state = DriveActivityAttributes.DriveActivityState(
            phase: .recording,
            speedMph: speedMph,
            gForce: currentGForce,
            distanceMiles: distanceMiles,
            maxSpeedMph: currentMaxSpeed * 2.23694,
            elapsedSeconds: now.timeIntervalSince(activity.attributes.startDate)
        )
        await activity.update(ActivityContent(state: state, staleDate: now.addingTimeInterval(10)))
    }

    func end(finalState: DriveActivityAttributes.DriveActivityState?, lingerSeconds: TimeInterval) async {
        guard let activity = liveActivity else { return }
        lastUpdate = nil
        let final = finalState ?? DriveActivityAttributes.DriveActivityState(
            phase: .ended, speedMph: 0, gForce: 0, distanceMiles: 0, maxSpeedMph: 0, elapsedSeconds: 0
        )
        let policy: ActivityUIDismissalPolicy = lingerSeconds > 0
            ? .after(Date().addingTimeInterval(lingerSeconds))
            : .immediate
        await activity.end(
            ActivityContent(state: final, staleDate: Date().addingTimeInterval(lingerSeconds + 5)),
            dismissalPolicy: policy
        )
        liveActivity = nil
    }

    func dismissAllOrphans() async {
        for activity in Activity<DriveActivityAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        liveActivity = nil
    }
}
```

`DriveManager.swift` recording control becomes:
```swift
private let liveActivity: LiveActivityController  // injected, defaults to LiveActivityCoordinator()

func startRecording() {
    recordingController.startRecording()
    Task { await liveActivity.start(recordingStartTime: recordingController.recordingStartTime) }
}

@MainActor
func stopRecording() async {
    let finalSnapshot = recordingController.currentDrive.map { drive -> DriveActivityAttributes.DriveActivityState in
        DriveActivityAttributes.DriveActivityState(
            phase: .ended,
            speedMph: 0,
            gForce: 0,
            distanceMiles: drive.distance * 0.000621371,
            maxSpeedMph: drive.maxSpeed * 2.23694,
            elapsedSeconds: drive.duration
        )
    }
    await recordingController.stopRecording()
    await liveActivity.end(finalState: finalSnapshot, lingerSeconds: 4)
    if let savedDrive = recordingController.currentDrive {
        carStatsManager.updateStats(for: savedDrive)
    }
    await refreshAchievementsFromServer()
}
```

The init takes a new defaulted parameter:
```swift
init(
    authManager: AuthManager,
    profileManager: ProfileManager,
    settings: AppSettings,
    apiService: DriveAPI,
    carStatsManager: CarStatsManager,
    achievementManager: AchievementManager,
    liveActivity: LiveActivityController? = nil
) {
    ...
    self.liveActivity = liveActivity ?? LiveActivityCoordinator()
}
```

Keep the existing `liveActivityCoordinator` property name? Rename to `liveActivity`. Update `forTesting` / `preview` factories to not regress.

- [ ] **Step 2: Write the failing tests**

```swift
// LiveActivityCoordinationTests.swift
import XCTest
@testable import FastTrack

@MainActor
final class LiveActivityCoordinationTests: XCTestCase {

    final class MockLiveActivity: LiveActivityController {
        struct Call: Equatable {
            enum Kind: Equatable { case start, update, end, sweep }
            let kind: Kind
        }
        private(set) var calls: [Call] = []
        private(set) var lastEndedWithLinger: TimeInterval?
        private(set) var lastEndedWithFinalState: DriveActivityAttributes.DriveActivityState?

        func start(recordingStartTime: Date?) async { calls.append(.init(kind: .start)) }
        func update(speedMph: Double, distanceMiles: Double, currentGForce: Double, currentMaxSpeed: Double) async {
            calls.append(.init(kind: .update))
        }
        func end(finalState: DriveActivityAttributes.DriveActivityState?, lingerSeconds: TimeInterval) async {
            calls.append(.init(kind: .end))
            lastEndedWithLinger = lingerSeconds
            lastEndedWithFinalState = finalState
        }
        func dismissAllOrphans() async { calls.append(.init(kind: .sweep)) }
    }

    func test_stopRecording_awaitsLiveActivityEnd() async {
        let mock = MockLiveActivity()
        let dm = DriveManager.forTesting(apiService: APIService(), liveActivity: mock)
        dm.isRecording = true  // bypass the recordingController guard for this unit test
        await dm.stopRecording()
        XCTAssertTrue(mock.calls.contains(.init(kind: .end)))
    }

    func test_stopRecording_endsWithLingerForSummary() async {
        let mock = MockLiveActivity()
        let dm = DriveManager.forTesting(apiService: APIService(), liveActivity: mock)
        dm.isRecording = true
        await dm.stopRecording()
        XCTAssertEqual(mock.lastEndedWithLinger, 4)
    }

    func test_stopRecording_marksFinalStateAsEnded() async {
        let mock = MockLiveActivity()
        let dm = DriveManager.forTesting(apiService: APIService(), liveActivity: mock)
        dm.isRecording = true
        dm.recordingController.currentDrive = Drive.example
        await dm.stopRecording()
        XCTAssertEqual(mock.lastEndedWithFinalState?.phase, .ended)
    }
}
```

Add a `forTesting(apiService:liveActivity:)` overload in `DriveManager+forTesting`:
```swift
static func forTesting(
    apiService: DriveAPI,
    liveActivity: LiveActivityController = MockLiveActivityController()
) -> DriveManager { ... }
```
(or simply make the existing `forTesting` accept an optional `liveActivity` parameter — the existing one passes `nil`, which falls through to the real `LiveActivityCoordinator()` which is harmless because `areActivitiesEnabled` is false in the test runner.)

- [ ] **Step 3: Verify the tests fail because the protocol/injection doesn't exist yet, then make them pass with the implementation above.**

- [ ] **Step 4: Run the full test suite to confirm no regressions**

```
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests \
  CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 5: Commit**

```
git add ios/FastTrack/FastTrack/ViewModels/LiveActivityController.swift \
        ios/FastTrack/FastTrack/ViewModels/LiveActivityCoordinator.swift \
        ios/FastTrack/FastTrack/ViewModels/DriveManager.swift \
        ios/FastTrack/FastTrackTests/LiveActivityCoordinationTests.swift \
        ios/FastTrack/FastTrack.xcodeproj/project.pbxproj
git commit -m "fix(ios): await Live Activity dismissal and log lifecycle errors"
```

---

## Task 4: Add `phase`/`elapsedSeconds` to ContentState (backward-compatible)

**Files:**
- Modify: `ios/FastTrack/FastTrack/Models/DriveActivityAttributes.swift`
- Modify: `ios/FastTrack/FastTrackWidgets/DriveActivityAttributes.swift` (must mirror exactly)

- [ ] **Step 1: Update both copies of the struct identically**

```swift
import ActivityKit
import Foundation

struct DriveActivityAttributes: ActivityAttributes {
    public typealias ContentState = DriveActivityState

    let startDate: Date

    public struct DriveActivityState: Codable, Hashable {
        public enum Phase: String, Codable, Hashable {
            case recording
            case ended
        }

        var phase: Phase
        var speedMph: Double
        var gForce: Double
        var distanceMiles: Double
        var maxSpeedMph: Double
        var elapsedSeconds: TimeInterval

        // Explicit init keeps existing call sites compiling and gives every field
        // a default so future additions stay source-compatible.
        init(
            phase: Phase = .recording,
            speedMph: Double = 0,
            gForce: Double = 0,
            distanceMiles: Double = 0,
            maxSpeedMph: Double = 0,
            elapsedSeconds: TimeInterval = 0
        ) {
            self.phase = phase
            self.speedMph = speedMph
            self.gForce = gForce
            self.distanceMiles = distanceMiles
            self.maxSpeedMph = maxSpeedMph
            self.elapsedSeconds = elapsedSeconds
        }

        // Decode with defaults so any in-flight activity payload that
        // predates `phase` / `elapsedSeconds` still decodes.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.phase = try c.decodeIfPresent(Phase.self, forKey: .phase) ?? .recording
            self.speedMph = try c.decodeIfPresent(Double.self, forKey: .speedMph) ?? 0
            self.gForce = try c.decodeIfPresent(Double.self, forKey: .gForce) ?? 0
            self.distanceMiles = try c.decodeIfPresent(Double.self, forKey: .distanceMiles) ?? 0
            self.maxSpeedMph = try c.decodeIfPresent(Double.self, forKey: .maxSpeedMph) ?? 0
            self.elapsedSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .elapsedSeconds) ?? 0
        }
    }
}
```

- [ ] **Step 2: Build both targets** (`xcodebuild build-for-testing …`) and re-run the tests from Tasks 1 and 3.

- [ ] **Step 3: Commit**

```
git add ios/FastTrack/FastTrack/Models/DriveActivityAttributes.swift \
        ios/FastTrack/FastTrackWidgets/DriveActivityAttributes.swift
git commit -m "feat(ios): add phase + elapsed to DriveActivityState with default decoding"
```

---

## Task 5: Render the ended-phase summary in the widget

**Files:**
- Modify: `ios/FastTrack/FastTrackWidgets/DriveActivityWidget.swift`

- [ ] **Step 1: In `LockScreenLiveActivityView` and the dynamic island, branch on `context.state.phase`. Replace the always-running `Text(timerInterval: ... distantFuture)` with a static elapsed-time string when the phase is `.ended`, and add a "Drive complete" label.**

In `lockScreenView`:
```swift
private var lockScreenView: some View {
    VStack(spacing: 10) {
        switch context.state.phase {
        case .recording: recordingHeader
        case .ended:     endedHeader
        }
        statsRow
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 12)
}

@ViewBuilder
private var recordingHeader: some View {
    HStack {
        HStack(spacing: 5) {
            Image(systemName: "record.circle").foregroundColor(.red).symbolEffect(.pulse)
            Text("FastTrack").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
        }
        Spacer()
        Text(timerInterval: context.attributes.startDate...Date.distantFuture, countsDown: false)
            .font(.headline).fontWeight(.bold).monospacedDigit()
        Spacer()
        Link(destination: URL(string: "fasttrack://stop-recording")!) {
            Label("Stop", systemImage: "stop.circle.fill")
                .font(.caption).fontWeight(.semibold).foregroundStyle(.white)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(Color.red.opacity(0.75), in: Capsule())
        }
    }
}

@ViewBuilder
private var endedHeader: some View {
    HStack {
        HStack(spacing: 5) {
            Image(systemName: "checkmark.circle.fill").foregroundColor(.green)
            Text("Drive complete").font(.caption).fontWeight(.semibold).foregroundStyle(.secondary)
        }
        Spacer()
        Text(formatElapsed(context.state.elapsedSeconds))
            .font(.headline).fontWeight(.bold).monospacedDigit()
        Spacer()
        // No stop button — drive is already over.
        Color.clear.frame(width: 1)
    }
}

private func formatElapsed(_ t: TimeInterval) -> String {
    let h = Int(t) / 3600
    let m = (Int(t) % 3600) / 60
    let s = Int(t) % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}

private var statsRow: some View {
    HStack(spacing: 0) {
        statCell(value: String(format: "%.0f", context.state.speedMph), unit: "mph", color: .yellow)
        statCell(value: String(format: "%.0f", context.state.maxSpeedMph), unit: "top mph", color: .yellow.opacity(0.7))
        statCell(value: String(format: "%.2f", context.state.gForce), unit: "G", color: .orange)
        statCell(value: String(format: "%.1f", context.state.distanceMiles), unit: "mi", color: .green)
    }
}
```

Repeat the same phase branch in `smallView`, the dynamic-island expanded `.center` region (replace timer with elapsed text when ended), and remove/disable the Stop button in the `.bottom` region when ended.

- [ ] **Step 2: Build the widget extension**

```
xcodebuild build-for-testing \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 3: Commit**

```
git add ios/FastTrack/FastTrackWidgets/DriveActivityWidget.swift
git commit -m "feat(ios): render Drive-complete summary in Live Activity"
```

---

## Task 6: Stream live updates to the widget while recording

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift`

- [ ] **Step 1: Subscribe to `recordingController.$currentDrive` and forward stats to the Live Activity, throttled by `LiveActivityCoordinator.update` (which already caps at 1 Hz).**

In `DriveManager.init`, after the existing `recordingController` bindings:
```swift
recordingController.$currentDrive
    .compactMap { $0 }
    .sink { [weak self] drive in
        guard let self, self.recordingController.isRecording else { return }
        Task { [weak self] in
            guard let self else { return }
            await self.liveActivity.update(
                speedMph: self.recordingController.latestSpeedSample.map { $0.speed * 2.23694 } ?? 0,
                distanceMiles: drive.distance * 0.000621371,
                currentGForce: self.recordingController.currentGForce,
                currentMaxSpeed: self.recordingController.currentMaxSpeed
            )
        }
    }
    .store(in: &cancellables)
```

- [ ] **Step 2: Add a test that verifies updates flow through**

Extend `LiveActivityCoordinationTests.swift`:
```swift
func test_recordingUpdates_pushedToLiveActivity() async {
    let mock = MockLiveActivity()
    let dm = DriveManager.forTesting(apiService: APIService(), liveActivity: mock)
    dm.recordingController.isRecording = true
    dm.recordingController.currentDrive = Drive.example  // triggers the sink
    // give the unstructured Task a chance to run
    try? await Task.sleep(nanoseconds: 50_000_000)
    XCTAssertTrue(mock.calls.contains(.init(kind: .update)))
}
```

- [ ] **Step 3: Run tests**

```
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/LiveActivityCoordinationTests \
  CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 4: Commit**

```
git add ios/FastTrack/FastTrack/ViewModels/DriveManager.swift \
        ios/FastTrack/FastTrackTests/LiveActivityCoordinationTests.swift
git commit -m "feat(ios): stream drive stats into Live Activity while recording"
```

---

## Task 7: Orphan sweep on app launch

**Files:**
- Modify: `ios/FastTrack/FastTrack/FastTrackApp.swift`

- [ ] **Step 1: In `RootView.task`, after the auth refresh, sweep any orphaned activities IF nothing is currently recording.**

```swift
.task {
    if authManager.isAuthenticated {
        do {
            try await authManager.refreshTokenIfNeeded()
        } catch {
            authManager.signOut()
        }
    }
    if !driveManager.isRecording {
        await driveManager.liveActivity.dismissAllOrphans()
    }
    try? await Task.sleep(nanoseconds: 800_000_000)
    isInitializing = false
}
```

Expose `liveActivity` from `DriveManager` (as an internal getter) so the App can call `dismissAllOrphans()`. Alternatively call directly through a new `DriveManager.discardOrphanLiveActivities()` method that delegates — the latter keeps the surface area small. Prefer the second.

```swift
// DriveManager.swift
func discardOrphanLiveActivities() async {
    await liveActivity.dismissAllOrphans()
}
```

```swift
// RootView.task
if !driveManager.isRecording {
    await driveManager.discardOrphanLiveActivities()
}
```

- [ ] **Step 2: Build, run all tests.**

- [ ] **Step 3: Commit**

```
git add ios/FastTrack/FastTrack/FastTrackApp.swift \
        ios/FastTrack/FastTrack/ViewModels/DriveManager.swift
git commit -m "fix(ios): sweep orphaned Live Activities on app launch"
```

---

## Task 8: Full regression run and PR

- [ ] **Step 1: Run the entire iOS test suite**

```
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

- [ ] **Step 2: Rebase on latest origin/main**

```
git fetch origin main
git rebase origin/main
```

- [ ] **Step 3: Push**

```
git push -u origin fix/ios-widget-and-keep-screen-on
```

- [ ] **Step 4: Open a PR**

```
gh pr create \
  --title "fix(ios): correct Live Activity lifecycle and scope keep-screen-on to recording" \
  --body "$(cat <<'EOF'
## Summary

Fixes two user-reported issues with the Live Activity ("widget") and recording session:

1. **Live Activity does not dismiss when recording is stopped from inside the app.**
   - `LiveActivityCoordinator.endLiveActivity()` previously fired-and-forgot the dismissal in an unstructured `Task`, with no error logging. If the app suspended mid-dismissal or `Activity.end()` threw, the activity orphaned on the lock screen with its `Text(timerInterval:)` timer continuing forever.
   - The widget's timer is bound to the immutable `startDate` attribute, so updating state to zero cannot stop it — dismissal is the only fix.
   - Lifecycle is now `async`, awaited from `DriveManager.stopRecording`, and emits `os_log` diagnostics on every failure. Added an orphan-sweep on app launch in case a previous session left one behind.

2. **"Keep Screen On While Recording" prevented the screen from sleeping even when not recording.**
   - The previous code wrote `UIApplication.shared.isIdleTimerDisabled` in two scattered places, which left no defense against scene-phase oddities or future code paths setting the flag.
   - New `ScreenWakeController` is the single owner of the idle-timer flag and recomputes it from `(isRecording, keepScreenOn, scenePhase)` on every input change. Scene background or recording-stopped now always release the flag.

3. **New: "Drive complete" summary in the Live Activity for ~4 seconds after stop**, before auto-dismiss. Adds a `phase` (recording / ended) plus `elapsedSeconds` to `DriveActivityState`, with `init(from:)` defaults so any in-flight activity from an older app version still decodes.

## Test Plan

- `xcodebuild test … -only-testing:FastTrackTests/ScreenWakeControllerTests` — new (5 cases).
- `xcodebuild test … -only-testing:FastTrackTests/LiveActivityCoordinationTests` — new (4 cases).
- Full suite passes.
- Manual smoke on Simulator + device:
  - Start drive → Stop drive → Live Activity shows summary for ~4 s, then dismisses.
  - Start drive → background app → drive ends from foreground later → activity dismisses.
  - With `keepScreenOn = true` and no recording: screen sleeps at OS auto-lock.
  - Toggle `keepScreenOn` off mid-drive: screen sleeps at OS auto-lock from that moment.

## Backward compatibility

- `DriveActivityState` adds new fields with default values and `init(from:)` defaults — any payload missing them decodes as `.recording` with zero elapsed.
- No API or DB change.
- No iOS app-update coordination required.
EOF
)"
```

---

## Decision log

(Populated during execution.)

- _2026-06-14_ — `ScreenWakeControllerObservable` is `@MainActor` with a `nonisolated` init, and carries a no-op `@Published` property. The wrapper is consumed by `@StateObject` from `FastTrackApp.init`, which is not MainActor-isolated. Without the `nonisolated` init the StateObject wrapper-expression fails actor-isolation checks; without `@MainActor` and a `@Published` property, the compiler cannot synthesize the default `objectWillChange` required by `ObservableObject` in this Swift/Combine module version (the `final` class has no synthesized members that would otherwise supply the conformance). — _Rationale: Unblocks build without changing the observable contract (callers in `RootView` already run on the main actor; they read `inner` and call its `@MainActor func update`).
- _2026-06-14_ — pbxproj not modified in Task 1. The project uses Xcode 16 `PBXFileSystemSynchronizedRootGroup` entries, so new files placed under the synchronized folder roots are picked up automatically. Manual `PBXBuildFile` / `PBXFileReference` edits are not required and would risk corrupting the project. — _Rationale: Verified by `build-for-testing` succeeding with the new files and no pbxproj change.
