# Workstream 6, Track B — D-8 heading detection (and folded E-6 actor round-trips)

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans.

**Goal:** Wire up `processHeadingBackground` (currently dead code at `DriveManager+Processing.swift:134-175`) so it actually detects left/right turns and lane changes during recording, populates `Drive.leftTurns` / `rightTurns` / `laneChanges`, and the heading math runs in `RecordingActor` (consolidating with the running-speed-stats pattern from R2/Phase 1) — eliminating 7 `await MainActor.run` round-trips per call (E-6).

**Why track B standalone:** The block lives in `DriveManager+Processing.swift`, which track A also edits (Task 3 — D-3 — drops redundant arrays from that file). Track B must rebase onto track A's branch head when A is ready, then land on top.

**Spec reference:** §5 Workstream 6 (D-8), §7 Resolved Decision D-8, §11 (R5 release notes).

**File ownership for track B:**
- `ios/FastTrack/FastTrack/ViewModels/DriveManager+Processing.swift` — modify `processHeadingBackground` body, remove the dead block's `MainActor.run` calls
- `ios/FastTrack/FastTrack/ViewModels/RecordingActor.swift` — add `ingestHeading(...)` and `pendingTurnCounts()` methods
- `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift` — remove the now-unused `headingWindow` / `headingHistory` / `lastTurnOrLaneTime` (or repurpose if needed for the call site)
- `ios/FastTrack/FastTrack/Services/LocationManager.swift` — actually invoke the heading processor from the GPS callback path (this is the dead-code bug)
- `ios/FastTrack/FastTrack/Views/DriveDetailView.swift` — surface turn/lane-change counts in the drive summary view (per spec §7 D-8: "the drive summary view surfaces left/right turns and lane changes")
- `ios/FastTrack/FastTrack/Models/Drive.swift` — `leftTurns` / `rightTurns` / `laneChanges` already exist; no field additions needed

**Coordinate with track A:** Wait for track A's `d3cb00c` (or whatever the FTGauge-equivalent for D-3 commit ends up as) to land on the branch head before starting. Then `git fetch` and rebase.

---

## File Structure

### Modify

- `RecordingActor.swift` — add `ingestHeading(course:speed:timestamp:)` (state + per-call math)
- `DriveManager+Processing.swift` — replace `processHeadingBackground` body with single-actor-call version
- `DriveManager.swift` — remove `headingWindow` / `headingHistory` / `lastTurnOrLaneTime` private state
- `LocationManager.swift` — invoke the new heading path on every GPS update with a valid course
- `DriveDetailView.swift` — display leftTurns / rightTurns / laneChanges in the summary card

### New tests

- `RecordingActorHeadingTests.swift` — heading ingestion, turn classification, sustained-curve gating
- `DriveManagerHeadingTests.swift` — total turn/lane-change counts propagate into `Drive`

---

## Task 1: Move heading state + math into `RecordingActor`

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/RecordingActor.swift`
- New test: `ios/FastTrack/FastTrackTests/RecordingActorHeadingTests.swift`

- [ ] **Step 1: Add the new methods**

```swift
private var headingWindow: (course: Double, timestamp: TimeInterval)?
private var headingHistory: [(course: Double, timestamp: TimeInterval)] = []
private var lastTurnOrLaneTime: TimeInterval?
private var totalLeftTurns: Int = 0
private var totalRightTurns: Int = 0
private var totalLaneChanges: Int = 0

struct HeadingResult: Sendable, Equatable {
    let leftTurns: Int
    let rightTurns: Int
    let laneChanges: Int
    var hasAny: Bool { leftTurns + rightTurns + laneChanges > 0 }
}

func ingestHeading(course: Double, speed: Double, timestamp: TimeInterval) -> HeadingResult {
    defer {
        headingWindow = (course, timestamp)
    }

    // First sample: just record the window.
    guard let window = headingWindow else {
        headingHistory.append((course, timestamp))
        return HeadingResult(leftTurns: 0, rightTurns: 0, laneChanges: 0)
    }

    let windowAge = timestamp - window.course.timeOrZero  // see note below
    // (windowAge needs to be derived from a (course, time) tuple
    //  — use a small private struct or two parallel vars.)
    guard windowAge >= 2.0 else { return HeadingResult(leftTurns: 0, rightTurns: 0, laneChanges: 0) }

    var delta = course - window.course
    if delta > 180 { delta -= 360 }
    if delta < -180 { delta += 360 }

    let gap: TimeInterval = lastTurnOrLaneTime.map { timestamp - $0 } ?? 100

    headingHistory.append((course, timestamp))
    let cutoff = timestamp - 10
    headingHistory.removeAll { $0.timestamp < cutoff }
    let inCurve = isSustainedCurve(upToTimestamp: timestamp)

    var left = 0, right = 0, lane = 0
    if abs(delta) > 35 && gap > 4 {
        if delta > 0 { right = 1 } else { left = 1 }
    } else if abs(delta) >= 10 && abs(delta) <= 35 && speed > 6.7 && gap > 3 && !inCurve {
        lane = 1
    }

    totalLeftTurns += left
    totalRightTurns += right
    totalLaneChanges += lane
    if left + right + lane > 0 {
        lastTurnOrLaneTime = timestamp
    }

    return HeadingResult(leftTurns: left, rightTurns: right, laneChanges: lane)
}

func headingTotals() -> (left: Int, right: Int, lane: Int) {
    (totalLeftTurns, totalRightTurns, totalLaneChanges)
}

func resetHeading() {
    headingWindow = nil
    headingHistory.removeAll()
    lastTurnOrLaneTime = nil
    totalLeftTurns = 0
    totalRightTurns = 0
    totalLaneChanges = 0
}

private func isSustainedCurve(upToTimestamp: TimeInterval) -> Bool {
    // Port the existing implementation in DriveManager+Processing.swift:180-200
    // onto the local headingHistory array. Keep the same threshold logic
    // (cumulative > 40°, ≥3 same-sign deltas, all same direction).
    ...
}
```

**Refactor note:** The original `isSustainedCurve` takes a `Date` and reads from `self.headingHistory` (a tuple array). The actor-scoped version should take a `TimeInterval` (the `ts` field) to match the rest of the actor's scalar-based state. Verify by reading lines 180-200 of the current file.

- [ ] **Step 2: Write the tests**

```swift
final class RecordingActorHeadingTests: XCTestCase {

    @MainActor
    func test_firstSampleDoesNotClassify() async {
        let actor = RecordingActor.shared
        actor.resetHeading()
        let r = await actor.ingestHeading(course: 0, speed: 10, timestamp: 1000)
        XCTAssertFalse(r.hasAny)
    }

    @MainActor
    func test_rightTurnAbove35Degrees() async {
        let actor = RecordingActor.shared
        actor.resetHeading()
        _ = await actor.ingestHeading(course: 0, speed: 10, timestamp: 1000)
        let r = await actor.ingestHeading(course: 50, speed: 10, timestamp: 1003)
        XCTAssertEqual(r.rightTurns, 1)
        XCTAssertEqual(r.leftTurns, 0)
    }

    @MainActor
    func test_laneChangeBelow35Degrees() async {
        let actor = RecordingActor.shared
        actor.resetHeading()
        _ = await actor.ingestHeading(course: 0, speed: 10, timestamp: 1000)
        let r = await actor.ingestHeading(course: 20, speed: 10, timestamp: 1003)
        XCTAssertEqual(r.laneChanges, 1)
    }

    @MainActor
    func test_sustainedCurveGatesLaneChange() async {
        let actor = RecordingActor.shared
        actor.resetHeading()
        _ = await actor.ingestHeading(course: 0, speed: 10, timestamp: 1000)
        // 5 small same-direction deltas over 8 seconds — sustained curve
        for i in 1...5 {
            _ = await actor.ingestHeading(course: Double(i) * 5, speed: 10, timestamp: 1000 + Double(i))
        }
        // Now a 20° step should NOT count as a lane change (in curve)
        let r = await actor.ingestHeading(course: 30, speed: 10, timestamp: 1008)
        XCTAssertEqual(r.laneChanges, 0)
    }

    @MainActor
    func test_gapResetSuppressesDoubleCount() async {
        let actor = RecordingActor.shared
        actor.resetHeading()
        _ = await actor.ingestHeading(course: 0, speed: 10, timestamp: 1000)
        let r1 = await actor.ingestHeading(course: 50, speed: 10, timestamp: 1003)
        XCTAssertEqual(r1.rightTurns, 1)
        // Within the 4-second gap, even a bigger delta should not re-count
        let r2 = await actor.ingestHeading(course: 110, speed: 10, timestamp: 1004)
        XCTAssertFalse(r2.hasAny)
    }
}
```

- [ ] **Step 3: Build + test + commit**

`feat(ios): add ingestHeading to RecordingActor for D-8/E-6`

---

## Task 2: Replace `processHeadingBackground` body to use the actor

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager+Processing.swift`

- [ ] **Step 1: Replace the function**

```swift
func processHeading(course: Double, speed: Double, timestamp: Date) async -> (left: Int, right: Int, lanes: Int)? {
    let result = await RecordingActor.shared.ingestHeading(
        course: course,
        speed: speed,
        timestamp: timestamp.timeIntervalSince1970
    )
    if result.hasAny {
        let totals = await RecordingActor.shared.headingTotals()
        return (totals.left, totals.right, totals.lane)
    }
    return nil
}
```

- [ ] **Step 2: Delete the old block**

Remove `processHeadingBackground` (lines 134-175), `isSustainedCurve` (lines 177-200), and the `private extension Double { var metersToMiles: Double }` is unrelated — keep that one.

- [ ] **Step 3: Commit**

`feat(ios): wire heading detection through RecordingActor (D-8, E-6)`

---

## Task 3: Invoke the new path from `LocationManager`

**Files:**
- Modify: `ios/FastTrack/FastTrack/Services/LocationManager.swift`

- [ ] **Step 1: Add the call site**

In the location-callback path, when `location.course >= 0` and speed > 0:

```swift
if let driveManager = driveManager, driveManager.isRecording {
    Task { [weak driveManager] in
        await driveManager?.processHeading(
            course: location.course,
            speed: max(location.speed, 0),
            timestamp: location.timestamp
        )
    }
}
```

The result is consumed by `DriveManager` to update `leftTurns` / `rightTurns` / `laneChanges` on the in-flight `currentDrive`.

- [ ] **Step 2: Commit**

`feat(ios): invoke heading detection on every GPS sample (D-8)`

---

## Task 4: Surface turn counts in the drive summary view

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/DriveDetailView.swift`

- [ ] **Step 1: Add a stats card**

If the drive has `leftTurns + rightTurns + laneChanges > 0`, render a small row in the existing summary card showing the breakdown. Use a `StatInfo`-style label or the existing instrument card. Verify the layout doesn't introduce visual regressions on small devices.

- [ ] **Step 2: Commit**

`feat(ios): surface turn/lane-change counts in DriveDetailView (D-8)`

---

## Task 5: Test the totals propagate

**Files:**
- New: `ios/FastTrack/FastTrackTests/DriveManagerHeadingTests.swift`

- [ ] **Step 1: Write a test that drives the actor and reads totals**

```swift
@MainActor
func test_headingTotalsAccumulate() async {
    let mgr = DriveManager.shared
    mgr.startRecordingForTest()
    // Simulate 3 distinct right turns with proper gaps
    for i in 0..<3 {
        _ = await mgr.processHeading(course: 0, speed: 10, timestamp: Date().addingTimeInterval(TimeInterval(i * 10)))
        _ = await mgr.processHeading(course: 50, speed: 10, timestamp: Date().addingTimeInterval(TimeInterval(i * 10 + 1)))
    }
    let totals = await RecordingActor.shared.headingTotals()
    XCTAssertEqual(totals.right, 3)
    mgr.stopRecordingForTest()
}
```

(If `startRecordingForTest` / `stopRecordingForTest` don't exist, the test should call the real `startRecording` and `stopRecording` paths with a stubbed `LocationManager`. The existing `DriveManagerTests` should be the reference for the test pattern.)

- [ ] **Step 2: Commit**

`test(ios): cover heading detection end-to-end (D-8)`

---

## Final verification

- [ ] `xcodebuild build-for-testing` — passes
- [ ] `xcodebuild test` — all green
- [ ] Manual: record a drive, deliberately turn the wheel 90° on a quiet road, verify the count increments in the summary view
- [ ] Cross-check: the existing `DriveDetailView.parseRouteData` flow is unchanged (D-8 only adds; doesn't reshape)

## Open the PR

Title: `feat(ios): wire up heading detection (D-8, E-6)`

Body: list the 5 tasks, note the rebase onto track A's branch head, link spec §7 (D-8 resolved decision) and §11 (R5 release notes).

## Coordination notes

- Wait for track A's PR to land on the release branch (or open a stacked PR).
- Track A and B both touch `DriveManager+Processing.swift` and `DriveManager.swift`. Sequencing is enforced.
- After track B's PR is approved but before merge, the orchestrator (next agent) re-rebases onto track A's merged head. Manual rebase, then `xcodebuild test`.

## Decision log

- 2026-06-12: `isSustainedCurve` migrated to actor-scope — keep the original `Date`-based signature or move to `TimeInterval`? **Decision:** move to `TimeInterval` for actor consistency. The internal `headingHistory` storage changes from `[(course: Double, time: Date)]` to `[(course: Double, timestamp: TimeInterval)]`. Verify no other read site.
