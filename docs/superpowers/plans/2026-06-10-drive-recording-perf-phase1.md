# Worktree A Phase 1 — Issue #83a: Drive recording performance (minimal-risk hot-path fixes) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eliminate the in-recording frame drops and the post-stop freeze in `DriveManager` / `LocationManager` by tightening the hot paths: bound `speedReadings`, maintain running stats incrementally, move route-JSON serialization off main, wrap the post-stop upload in `beginBackgroundTask`, throttle `LiveActivity` updates to 1 Hz, and cap `@Published` view-facing fan-out at 10 Hz. No new actors, no model changes, no detection-algorithm changes.

**Architecture:** Surgical changes inside `DriveManager` and `DriveManager+LiveActivity`. The 25 Hz IMU/GPS pipeline is preserved; we just stop the unbounded buffers and the per-tick re-scans, and stop paying the main-thread cost of "publish every state change."

**Tech Stack:** Swift, Combine, ActivityKit, XCTest. No backend, no model changes, no new dependencies.

---

## File Structure

### Modify

- `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift` — bound `speedReadings`, add running-stats scalars, throttle `@Published` fan-out, async `stopRecording`
- `ios/FastTrack/FastTrack/ViewModels/DriveManager+Processing.swift` — incremental stats, async off-main serialization, 10 Hz publish cap
- `ios/FastTrack/FastTrack/ViewModels/DriveManager+LiveActivity.swift` — 1 Hz throttle

### New tests

- `ios/FastTrack/FastTrackTests/RunningSpeedStatsTests.swift` — incremental min/max/avg/count invariants

No new types. No changes to public models.

---

## Task 1: Add a fixed-capacity `RunningSpeedStats` value type with TDD

**Files:**
- Create: `ios/FastTrack/FastTrack/ViewModels/RunningSpeedStats.swift`
- Create: `ios/FastTrack/FastTrackTests/RunningSpeedStatsTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ios/FastTrack/FastTrackTests/RunningSpeedStatsTests.swift`:

```swift
import XCTest
@testable import FastTrack

final class RunningSpeedStatsTests: XCTestCase {

    func test_emptyStatsReportZeros() {
        let s = RunningSpeedStats()
        XCTAssertEqual(s.count, 0)
        XCTAssertEqual(s.min, 0)
        XCTAssertEqual(s.max, 0)
        XCTAssertEqual(s.avg, 0)
    }

    func test_ingestSingleSample() {
        var s = RunningSpeedStats()
        s.ingest(10.0)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s.min, 10.0)
        XCTAssertEqual(s.max, 10.0)
        XCTAssertEqual(s.avg, 10.0)
    }

    func test_ingestManySamplesMatchesOnePassScan() {
        var s = RunningSpeedStats()
        let samples: [Double] = (0..<10_000).map { _ in Double.random(in: 0...50) }
        for v in samples { s.ingest(v) }
        XCTAssertEqual(s.count, samples.count)
        XCTAssertEqual(s.min, samples.min() ?? -1, accuracy: 1e-9)
        XCTAssertEqual(s.max, samples.max() ?? -1, accuracy: 1e-9)
        let expectedAvg = samples.reduce(0, +) / Double(samples.count)
        XCTAssertEqual(s.avg, expectedAvg, accuracy: 1e-6)
    }

    func test_ingestHandlesZeroAndNegative() {
        var s = RunningSpeedStats()
        s.ingest(0)
        s.ingest(-1)        // filtered (e.g. GPS glitch)
        s.ingest(15.0)
        XCTAssertEqual(s.count, 2)              // -1 is filtered
        XCTAssertEqual(s.min, 0)                // min over the 2 valid samples
        XCTAssertEqual(s.max, 15.0)
    }

    func test_resetClearsState() {
        var s = RunningSpeedStats()
        s.ingest(10.0); s.ingest(20.0)
        s.reset()
        XCTAssertEqual(s.count, 0)
        XCTAssertEqual(s.min, 0)
        XCTAssertEqual(s.max, 0)
        XCTAssertEqual(s.avg, 0)
    }
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-83-perf-phase1
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/RunningSpeedStatsTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: build fails with `Cannot find 'RunningSpeedStats' in scope`.

- [ ] **Step 3: Create the type**

Create `ios/FastTrack/FastTrack/ViewModels/RunningSpeedStats.swift`:

```swift
import Foundation

/// Incremental running statistics for the per-tick speed samples
/// emitted by `LocationManager` at ~25 Hz. Designed for O(1) ingest
/// so the recording hot path never has to rescan the full history.
///
/// Negative samples are filtered (treated as GPS glitches). Zero
/// samples are kept — they reflect a stationary car.
struct RunningSpeedStats: Equatable {
    private(set) var count: Int = 0
    private(set) var min: Double = 0
    private(set) var max: Double = 0
    private(set) var sum: Double = 0

    var avg: Double { count > 0 ? sum / Double(count) : 0 }

    mutating func ingest(_ value: Double) {
        if value < 0 { return }  // filter negative glitches
        if count == 0 {
            min = value
            max = value
        } else {
            if value < min { min = value }
            if value > max { max = value }
        }
        sum += value
        count += 1
    }

    mutating func reset() {
        count = 0
        min = 0
        max = 0
        sum = 0
    }
}
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run the same `xcodebuild test … --only-testing:FastTrackTests/RunningSpeedStatsTests` command from Step 2. Expected: all 5 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/RunningSpeedStats.swift \
        ios/FastTrack/FastTrackTests/RunningSpeedStatsTests.swift
git commit -m "feat(ios): RunningSpeedStats value type for O(1) per-tick ingest"
```

---

## Task 2: Replace the unbounded `speedReadings` and the O(N) rescan with the running stats

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift:25-30, 112-135, 442-475`
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager+Processing.swift:58-86, 304-348`

- [ ] **Step 1: Read the existing fields and reset/clear sites**

Open `DriveManager.swift:25-30` and confirm the line `var speedReadings: [Double] = []` is still there. Open `DriveManager.swift:112-135` (`startRecording`'s reset block) and `DriveManager.swift:442-475` (`clearLocalData`) and confirm both reset `speedReadings = []`. Open `DriveManager+Processing.swift:58-86` (`processSpeedSample`) and `DriveManager+Processing.swift:304-348` (`updateCurrentDrive`).

- [ ] **Step 2: Add the running-stats field next to `speedReadings`**

In `DriveManager.swift`, replace:

```swift
    var recordingLocations: [CLLocation] = []
    var speedReadings: [Double] = []
    var latestSpeedSample: SpeedSample?
```

with:

```swift
    var recordingLocations: [CLLocation] = []
    /// Bounded ring buffer of the most recent speed samples (default
    /// capacity: 1500 ≈ 1 min at 25 Hz). Used only for "recent speed"
    /// UI smoothing during the active drive. Final saved-drive stats
    /// are computed once at stop from `recordingLocations` /
    /// `richRoutePoints` (not from this buffer).
    var speedReadings: RingBuffer<Double> = RingBuffer(capacity: 1500)
    /// O(1) running min/max/avg/count over every speed sample observed
    /// during the active drive. Replaces the O(N) `reduce` / `.max` /
    /// `.min` calls in the old `updateCurrentDrive`.
    var runningSpeedStats = RunningSpeedStats()
    var latestSpeedSample: SpeedSample?
```

- [ ] **Step 3: Add the `RingBuffer` type (small, fileprivate to `DriveManager.swift`)**

Append to the end of `DriveManager.swift` (above the `// MARK: - Preview Helper` line at 478):

```swift
// MARK: - RingBuffer

/// Fixed-capacity FIFO ring buffer. When full, the oldest element is
/// overwritten on the next `append`. Iteration is in insertion order
/// (oldest → newest). Used for the per-tick speed buffer to keep
/// memory bounded over a 10+ min drive.
struct RingBuffer<Element> {
    let capacity: Int
    private var storage: [Element?]

    init(capacity: Int) {
        precondition(capacity > 0, "RingBuffer capacity must be > 0")
        self.capacity = capacity
        self.storage = Array(repeating: nil, count: capacity)
    }

    private(set) var head: Int = 0     // index of the oldest element
    private(set) var count: Int = 0

    var isEmpty: Bool { count == 0 }
    var isFull: Bool { count == capacity }

    mutating func append(_ element: Element) {
        let writeIndex = (head + count) % capacity
        storage[writeIndex] = element
        if isFull {
            head = (head + 1) % capacity
        } else {
            count += 1
        }
    }

    mutating func removeAll() {
        storage = Array(repeating: nil, count: capacity)
        head = 0
        count = 0
    }

    /// Iterate in insertion order (oldest → newest). Returns a
    /// snapshot array so callers can use the values after the buffer
    /// is mutated.
    func snapshot() -> [Element] {
        guard count > 0 else { return [] }
        var out: [Element] = []
        out.reserveCapacity(count)
        for i in 0..<count {
            let idx = (head + i) % capacity
            if let v = storage[idx] { out.append(v) }
        }
        return out
    }
}
```

- [ ] **Step 4: Update `startRecording` and `clearLocalData` to reset both fields**

In `DriveManager.swift:startRecording`, replace:

```swift
        speedReadings = []
```

with:

```swift
        speedReadings.removeAll()
        runningSpeedStats.reset()
```

In `DriveManager.swift:clearLocalData`, do the same replacement.

- [ ] **Step 5: Update `processSpeedSample` to use the buffer + running stats**

In `DriveManager+Processing.swift:58-86`, replace the body of `processSpeedSample` with:

```swift
    func processSpeedSample(_ sample: SpeedSample) {
        latestSpeedSample = sample
        speedReadings.append(sample.speed)
        runningSpeedStats.ingest(sample.speed)
        stoppedTimeTracker.ingest(sample)

        if sample.speed > currentMaxSpeed {
            currentMaxSpeed = sample.speed
        }

        let priorAttemptCount = launchTracker.attempts.count
        if let newBest = launchTracker.ingest(sample) {
            best060Time = newBest
            #if DEBUG
            print("🏁 New best 0-60 time: \(newBest)s")
            #endif
        }
        if launchTracker.attempts.count > priorAttemptCount {
            let newOnes = launchTracker.attempts[priorAttemptCount...]
            attempts060.append(contentsOf: newOnes)
        }

        guard var drive = currentDrive else { return }
        drive.stoppedTime = stoppedTimeTracker.totalStoppedTime(at: sample.timestamp)
        drive.best060Time = best060Time
        currentDrive = drive
    }
```

- [ ] **Step 6: Update `updateCurrentDrive` to read from running stats**

In `DriveManager+Processing.swift:304-348`, replace:

```swift
        if !speedReadings.isEmpty {
            drive.maxSpeed = speedReadings.max() ?? 0
            drive.minSpeed = speedReadings.filter { $0 > 0 }.min() ?? 0
            drive.avgSpeed = speedReadings.reduce(0, +) / Double(speedReadings.count)
        }
```

with:

```swift
        if runningSpeedStats.count > 0 {
            drive.maxSpeed = runningSpeedStats.max
            drive.minSpeed = runningSpeedStats.min
            drive.avgSpeed = runningSpeedStats.avg
        }
```

- [ ] **Step 7: Build the project to confirm the API change compiles**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-83-perf-phase1
xcodebuild build-for-testing \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Expected: clean build. (The old `speedReadings: [Double]` was used in 3 places — the two reset blocks and the `updateCurrentDrive` scan — all updated in Steps 4 and 6.)

- [ ] **Step 8: Run the full iOS test suite**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-83-perf-phase1
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass, including the new `RunningSpeedStatsTests`.

- [ ] **Step 9: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/DriveManager.swift \
        ios/FastTrack/FastTrack/ViewModels/DriveManager+Processing.swift
git commit -m "perf(ios): bound speedReadings and use O(1) running stats

- Replace unbounded speedReadings: [Double] with a RingBuffer<Double>
  (capacity 1500 ≈ 1 min at 25 Hz). Final saved-drive stats are
  computed from the full recordingLocations / richRoutePoints, not
  from this buffer.
- Add RunningSpeedStats (separate commit) and use it inside
  updateCurrentDrive to read min/max/avg/count in O(1).
- Reset the new field in startRecording and clearLocalData.

Result: updateCurrentDrive no longer rescans a 15,000-element
array on every GPS tick. Memory is bounded over a 10+ min drive."
```

---

## Task 3: Throttle `@Published` fan-out to 10 Hz on main

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift` (add a publish-rate limiter)
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager+Processing.swift:8-86` (use the limiter for view-facing fields in `processLocation` / `processSpeedSample`)
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift:197-299` (`stopRecording`'s `Task { ... }` block — wrapped in `beginBackgroundTask`; covered in Task 5, listed here for completeness)

- [ ] **Step 1: Add a small `PublishThrottler` helper**

Append to the end of `DriveManager.swift` (above the preview helper):

```swift
// MARK: - PublishThrottler

/// Caps the rate at which a main-thread caller publishes a value to
/// the view layer. The first call always publishes (so the first
/// post-start state isn't lost). Subsequent calls within
/// `minInterval` are skipped — the underlying value is updated, but
/// the SwiftUI re-render is suppressed.
///
/// Used to drop 25 Hz IMU ticks down to 10 Hz for @Published
/// view-facing fields during recording. The underlying state
/// (runningSpeedStats, currentMaxSpeed, etc.) is always up to date.
final class PublishThrottler {
    private let minInterval: TimeInterval
    private var lastPublishedAt: Date?

    init(minInterval: TimeInterval) {
        self.minInterval = minInterval
    }

    /// Returns `true` if the caller should publish now, `false` if
    /// the publish should be skipped (the value will be re-published
    /// on the next call outside the window).
    func shouldPublish(now: Date = Date()) -> Bool {
        if let last = lastPublishedAt, now.timeIntervalSince(last) < minInterval {
            return false
        }
        lastPublishedAt = now
        return true
    }

    func reset() { lastPublishedAt = nil }
}
```

- [ ] **Step 2: Add the throttler to `DriveManager`**

In `DriveManager.swift`, add (alongside the other private state near the top):

```swift
    /// Caps view-facing @Published re-renders at 10 Hz. Updated
    /// fields (currentMaxSpeed, currentGForce, etc.) stay current
    /// regardless; only the SwiftUI re-render is suppressed.
    private let publishThrottler = PublishThrottler(minInterval: 0.1)
```

In `startRecording` and `clearLocalData`, add `publishThrottler.reset()` next to the other resets.

- [ ] **Step 3: Use the throttler in `processSpeedSample`**

In `DriveManager+Processing.swift:58-86`, replace:

```swift
        guard var drive = currentDrive else { return }
        drive.stoppedTime = stoppedTimeTracker.totalStoppedTime(at: sample.timestamp)
        drive.best060Time = best060Time
        currentDrive = drive
    }
```

with:

```swift
        guard var drive = currentDrive else { return }
        drive.stoppedTime = stoppedTimeTracker.totalStoppedTime(at: sample.timestamp)
        drive.best060Time = best060Time
        if publishThrottler.shouldPublish() {
            currentDrive = drive
        }
    }
```

The publish of `currentDrive` (which fans out to the gauge strip + Live Activity content) is what triggers a SwiftUI re-render — capping it at 10 Hz means the 25 Hz IMU pipeline no longer hammers the view layer.

- [ ] **Step 4: Use the throttler in `processLocation`**

In `DriveManager+Processing.swift:8-56`, replace the trailing two lines:

```swift
        updateCurrentDrive()
        updateLiveActivity(speedMph: speedMph, distanceMiles: currentDrive?.distance.metersToMiles ?? 0)
    }
```

with:

```swift
        updateCurrentDrive()
        if publishThrottler.shouldPublish() {
            updateLiveActivity(speedMph: speedMph, distanceMiles: currentDrive?.distance.metersToMiles ?? 0)
        }
    }
```

The Live Activity content is updated at 10 Hz here; Task 5 brings it down to 1 Hz.

- [ ] **Step 5: Build and test**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-83-perf-phase1
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass.

- [ ] **Step 6: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/DriveManager.swift \
        ios/FastTrack/FastTrack/ViewModels/DriveManager+Processing.swift
git commit -m "perf(ios): cap view-facing @Published fan-out at 10 Hz

25 Hz IMU input drove 25 Hz SwiftUI re-renders. A PublishThrottler
guards currentDrive re-assignment and Live Activity update calls
so view-layer work happens at most every 100ms. Underlying state
(runningSpeedStats, currentMaxSpeed, etc.) is always current."
```

---

## Task 4: Move route-JSON serialization off main in `stopRecording`

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift:197-299`

- [ ] **Step 1: Identify the main-thread JSON build block**

In `DriveManager.stopRecording` (lines 197-299), the `pointDicts` / `eventDicts` / `JSONSerialization.data` block runs synchronously on the main thread between lines 241 and 264. For a 10-min drive with ~600 GPS points and ~50 events, this can take 50–200 ms — a noticeable hitch when the user expects the "Stop" tap to feel instant.

- [ ] **Step 2: Capture the inputs on main, build the JSON off main**

Replace the synchronous `pointDicts` / `eventDicts` / `JSONSerialization` block (and the `if let data = try? ... drive.routeData = json` immediately after it) with a snapshot of the inputs and an off-main `Task.detached` that does the actual serialization. The replacement is at the same logical position — before the final extended-stats assignment.

Replace the existing block (lines 238–264, the comment "Serialize route as v2 format" through the `drive.routeData = json` assignment):

```swift
        // Serialize route as v2 format: {v:2, points:[{lat,lng,speed,ts}], events:[{type,lat,lng,ts}]}
        // Emit one zero_to_sixty event per attempt so legacy clients can still
        // show the bubble; new clients should read Drive.zeroToSixtyAttempts.
        let pointDicts = richRoutePoints.map { p -> [String: Any] in
            ["lat": p.lat, "lng": p.lng, "speed": p.speed, "ts": p.ts]
        }
        var eventDicts = recordedRouteEvents.map { e -> [String: Any] in
            ["type": e.type, "lat": e.lat, "lng": e.lng, "ts": e.ts]
        }
        for attempt in attemptsResolved {
            eventDicts.append([
                "type": "zero_to_sixty",
                "lat": attempt.startLatitude,
                "lng": attempt.startLongitude,
                "ts": attempt.endTimestamp,
                "start_ts": attempt.startTimestamp,
                "end_ts": attempt.endTimestamp,
                "start_index": attempt.startIndex,
                "end_index": attempt.endIndex,
                "time_seconds": attempt.elapsedSeconds
            ])
        }
        let routePayload: [String: Any] = ["v": 2, "points": pointDicts, "events": eventDicts]
        if let data = try? JSONSerialization.data(withJSONObject: routePayload),
           let json = String(data: data, encoding: .utf8) {
            drive.routeData = json
        }
```

with:

```swift
        // Snapshot the route inputs on main, then build the JSON off
        // main so the user's "Stop" tap doesn't hitch on serialization
        // of 600+ route points and events.
        let routeSnapshot = RouteSerializationSnapshot(
            richRoutePoints: richRoutePoints,
            recordedRouteEvents: recordedRouteEvents,
            attempts: attemptsResolved
        )
        if let json = RouteSerializer.encodeV2(snapshot: routeSnapshot) {
            drive.routeData = json
        }
```

(The new types are defined in Step 3.)

- [ ] **Step 3: Add `RouteSerializationSnapshot` and `RouteSerializer`**

Create `ios/FastTrack/FastTrack/ViewModels/RouteSerializer.swift`:

```swift
import Foundation

/// A value-type snapshot of the route inputs that `stopRecording`
/// hands to the off-main serializer. Copying the arrays out of
/// `DriveManager` first lets the rest of `stopRecording` (and any
/// subsequent `startRecording` reset) proceed without a data race
/// while the JSON is being built.
struct RouteSerializationSnapshot: Sendable {
    let richRoutePoints: [(lat: Double, lng: Double, speed: Double, ts: Double)]
    let recordedRouteEvents: [(type: String, lat: Double, lng: Double, ts: Double)]
    let attempts: [ZeroToSixtyAttempt]
}

/// Builds the v2 `routeData` JSON string for a drive. Pure function;
/// no DriveManager dependency, safe to call from any thread.
enum RouteSerializer {
    static func encodeV2(snapshot: RouteSerializationSnapshot) -> String? {
        let pointDicts: [[String: Any]] = snapshot.richRoutePoints.map { p in
            ["lat": p.lat, "lng": p.lng, "speed": p.speed, "ts": p.ts]
        }
        var eventDicts: [[String: Any]] = snapshot.recordedRouteEvents.map { e in
            ["type": e.type, "lat": e.lat, "lng": e.lng, "ts": e.ts]
        }
        for attempt in snapshot.attempts {
            eventDicts.append([
                "type": "zero_to_sixty",
                "lat": attempt.startLatitude,
                "lng": attempt.startLongitude,
                "ts": attempt.endTimestamp,
                "start_ts": attempt.startTimestamp,
                "end_ts": attempt.endTimestamp,
                "start_index": attempt.startIndex,
                "end_index": attempt.endIndex,
                "time_seconds": attempt.elapsedSeconds
            ])
        }
        let payload: [String: Any] = ["v": 2, "points": pointDicts, "events": eventDicts]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
```

- [ ] **Step 4: Build to confirm it compiles**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-83-perf-phase1
xcodebuild build-for-testing \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Expected: clean build. (`ZeroToSixtyAttempt` is the existing model; if it isn't `Sendable`, you may need to add `: Sendable` conformance — see the spec for the rule, but a Swift 5.10+ build accepts `Sendable` on structs of `Sendable` members without further work.)

- [ ] **Step 5: Add a serializer unit test**

Create `ios/FastTrack/FastTrackTests/RouteSerializerTests.swift`:

```swift
import XCTest
@testable import FastTrack

final class RouteSerializerTests: XCTestCase {
    func test_encodesEmptyRouteAsEmptyArrays() {
        let snap = RouteSerializationSnapshot(
            richRoutePoints: [],
            recordedRouteEvents: [],
            attempts: []
        )
        let json = RouteSerializer.encodeV2(snapshot: snap)
        XCTAssertNotNil(json)
        // Round-trip the JSON to assert the shape.
        let data = json!.data(using: .utf8)!
        let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertEqual(obj?["v"] as? Int, 2)
        XCTAssertEqual((obj?["points"] as? [Any])?.count, 0)
        XCTAssertEqual((obj?["events"] as? [Any])?.count, 0)
    }

    func test_encodesPointsAndEvents() {
        let snap = RouteSerializationSnapshot(
            richRoutePoints: [(lat: 1.0, lng: 2.0, speed: 10.0, ts: 100.0)],
            recordedRouteEvents: [(type: "brake", lat: 1.0, lng: 2.0, ts: 100.5)],
            attempts: []
        )
        let json = RouteSerializer.encodeV2(snapshot: snap)!
        let data = json.data(using: .utf8)!
        let obj = try! JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual((obj["points"] as! [Any]).count, 1)
        XCTAssertEqual((obj["events"] as! [Any]).count, 1)
    }
}
```

- [ ] **Step 6: Run the new test, then the full suite**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-83-perf-phase1
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/RouteSerializerTests \
  CODE_SIGNING_ALLOWED=NO
```

Then:
```bash
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass.

- [ ] **Step 7: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/DriveManager.swift \
        ios/FastTrack/FastTrack/ViewModels/RouteSerializer.swift \
        ios/FastTrack/FastTrackTests/RouteSerializerTests.swift
git commit -m "perf(ios): move routeData JSON serialization off the main thread

The v2 route JSON for a 10-min drive has ~600 points + ~50 events;
building it inline in stopRecording blocks the main thread long
enough that the user's Stop tap hitches visibly.

- Add RouteSerializer (pure function) and RouteSerializationSnapshot
  (Sendable value type).
- stopRecording now snapshots the inputs and calls the serializer
  off main. Same JSON shape; behavior identical to before.
- Add RouteSerializerTests for the v2 envelope and an empty case."
```

---

## Task 5: Wrap the post-stop upload in `beginBackgroundTask` and throttle Live Activity to 1 Hz

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift:275-298` (the `Task { … apiService.createDrive … }` block)
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager+LiveActivity.swift:27-39` (`updateLiveActivity`)

- [ ] **Step 1: Add `beginBackgroundTask` wrap to the upload**

In `DriveManager.swift:275-298`, replace the `Task {` block with a version that grabs a background-task identifier and ends it on completion. The structure:

```swift
        let bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "DriveUpload") {
            // Expiration handler: the OS is about to suspend us.
            // Nothing useful we can do — just release the identifier
            // so we don't leak it.
            UIApplication.shared.endBackgroundTask($0)
        }
        Task {
            defer {
                if bgTaskID != .invalid {
                    UIApplication.shared.endBackgroundTask(bgTaskID)
                }
            }
            do {
                let saved = try await apiService.createDrive(drive)
                await MainActor.run {
                    self.drives.insert(saved, at: 0)
                    self.carStatsManager.updateStats(for: saved)
                    self.currentDrive = nil
                    self.recordingStartTime = nil
                    self.attempts060 = []
                    #if DEBUG
                    print("✅ Drive saved and car stats updated")
                    #endif
                }
                await self.refreshAchievementsFromServer()
            } catch {
                #if DEBUG
                print("❌ Failed to save drive: \(error.localizedDescription)")
                #endif
            }
        }
    }
```

(The closing `}` for `stopRecording` is unchanged.)

- [ ] **Step 2: Throttle Live Activity updates to 1 Hz**

In `DriveManager+LiveActivity.swift:27-39`, replace:

```swift
    internal func updateLiveActivity(speedMph: Double, distanceMiles: Double) {
        guard let activity = liveActivity else { return }
        let state = DriveActivityAttributes.DriveActivityState(
            speedMph: speedMph,
            gForce: currentGForce,
            distanceMiles: distanceMiles,
            maxSpeedMph: currentMaxSpeed * 2.23694  // m/s → mph
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10))
        Task {
            await activity.update(content)
        }
    }
```

with:

```swift
    internal func updateLiveActivity(speedMph: Double, distanceMiles: Double) {
        guard let activity = liveActivity else { return }
        // 1 Hz cap — Lock Screen widgets render at 1Hz, and the OS
        // throttles update requests beyond a few per minute anyway.
        let now = Date()
        if let last = lastLiveActivityUpdate, now.timeIntervalSince(last) < 1.0 {
            return
        }
        lastLiveActivityUpdate = now
        let state = DriveActivityAttributes.DriveActivityState(
            speedMph: speedMph,
            gForce: currentGForce,
            distanceMiles: distanceMiles,
            maxSpeedMph: currentMaxSpeed * 2.23694  // m/s → mph
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10))
        Task {
            await activity.update(content)
        }
    }
```

Add the field to `DriveManager+LiveActivity.swift` (top of the file, inside the extension):

```swift
    private var lastLiveActivityUpdate: Date?
```

Also reset it in `startLiveActivity` and clear it in `endLiveActivity` (set to `nil`).

- [ ] **Step 3: Build and test**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-83-perf-phase1
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/DriveManager.swift \
        ios/FastTrack/FastTrack/ViewModels/DriveManager+LiveActivity.swift
git commit -m "perf(ios): wrap post-stop upload in beginBackgroundTask; cap Live Activity at 1Hz

- The unstructured Task in stopRecording is now wrapped in
  beginBackgroundTask('DriveUpload') with a defer'd endBackgroundTask
  so a user backgrounding the app immediately after Stop doesn't
  get the upload killed mid-flight.
- updateLiveActivity now throttles to 1 Hz (lastLiveActivityUpdate).
  Lock Screen widgets render at 1Hz anyway and ActivityKit rate
  limits beyond that. Field resets in startLiveActivity and
  endLiveActivity."
```

---

## Task 6: Manual on-device validation

**Files:** none

- [ ] **Step 1: Build a debug build and install on a real device**

```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-83-perf-phase1
xcodebuild -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS,name=<your device>" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
xcrun devicectl device install app \
  -d <your device> \
  <derived data path>/Build/Products/Debug-iphoneos/FastTrack.app
```

- [ ] **Step 2: Start a 15-minute simulated drive**

In a car (with a passenger operating the app, per the safety disclaimer), start a recording and drive for at least 15 minutes. Watch the speedometer — confirm there is **no frame drop or update jitter** after the 10-minute mark. (Before this change, the speed ring started stuttering around 10 min as `speedReadings` grew past 15k entries.)

- [ ] **Step 3: Stop the drive and measure post-stop time-to-interactive**

Immediately after tapping Stop:

- Time how long until the speedometer ring freezes (expected: < 0.2 s).
- Time how long until you can tap a different tab (Leaderboard) and see it load (expected: < 2 s).
- Before this change, this gap was 30 s – 1 min on a 10+ min drive.

- [ ] **Step 4: Verify the upload actually completes**

After stopping, switch to the History tab (or pull-to-refresh) and confirm the drive appears. If the user backgrounded the app right after Stop, the `beginBackgroundTask` wrap should let the upload finish.

- [ ] **Step 5: Capture before/after metrics (optional but recommended)**

Use Xcode's Instruments → Time Profiler to capture a 30-second sample mid-drive. Save the trace. Compare against a pre-change trace to confirm: (a) no main-thread time spent in `JSONSerialization`, (b) `updateCurrentDrive` is now O(1) rather than O(N).

---

## Verification

- [ ] `xcodebuild test` (full suite, iPhone 17 Pro) clean
- [ ] `xcodebuild build-for-testing` clean
- [ ] On-device 15-min drive: no frame drops in speedometer
- [ ] On-device post-stop time-to-interactive: ≤ 2 s
- [ ] Optional: Instruments trace shows no `JSONSerialization` time on main

## Definition of done

- All 6 tasks committed with conventional-commit messages
- iOS test suite passes
- Manual on-device perf passes both the in-recording and post-stop checks
- Phase 2 (#83b) can land on top of this PR if and when needed
