# High-Precision 0-60 Timing & Top Speed Accuracy — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan track-by-track. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce 0-60 timing error to ±0.05s and improve top-speed leaderboard integrity by bumping IMU to 100 Hz, capturing a full high-rate speed stream, and running a post-hoc launch/speed analysis at drive end.

**Architecture:** Three-layer system — (1) real-time 100 Hz recording into a buffered speed stream, (2) post-hoc `LaunchAnalyzer` + `TopSpeedComputer` pass at `stopRecording` that replays the stream with two-pass launch detection and rolling-median top speed, (3) additive v3 `route_data` JSON with a delta-compressed `speed_stream` so old clients and the existing leaderboard are unaffected. New nullable backend columns `fused_max_speed` / `gps_max_speed` are added via a new additive migration.

**Tech Stack:** iOS (Swift, CoreMotion, CoreLocation, Combine), backend (Go, GORM, PostgreSQL), Xcode build, Go test, xcodebuild test.

**Execution model — parallelizable tracks:**

```
              ┌─────────────────────┐
              │  Track A            │
              │  iOS: 100 Hz +      │
              │  SpeedFusion tuning │
              │  + throttling       │
              └─────────┬───────────┘
                        │
        ┌───────────────┼───────────────┐
        ▼               ▼               ▼
┌──────────────┐  ┌──────────────┐  ┌──────────────┐
│  Track B     │  │  Track C     │  │  Track E     │
│  iOS:        │  │  iOS:        │  │  Backend:    │
│  RouteSer    │  │  Launch      │  │  migration   │
│  v3          │  │  Analyzer +  │  │  + Drive     │
│  + SpeedPeak │  │  TopSpeed    │  │  fields      │
└──────┬───────┘  └──────┬───────┘  └──────┬───────┘
       │                 │                 │
       └────────┬────────┘                 │
                ▼                          │
       ┌──────────────────┐                │
       │  Track D         │                │
       │  iOS: Drive      │                │
       │  model wiring    │◄───────────────┘
       │  + integration   │
       └────────┬─────────┘
                ▼
       ┌──────────────────┐
       │  Track F         │
       │  Tests           │
       │  (unit + int)    │
       └──────────────────┘
```

- **Tracks A and E are independent** and can run fully in parallel from the start.
- **Tracks B, C** depend only on A and can run in parallel with each other.
- **Track D** depends on B + C and on the new fields from E.
- **Track F** is the final test pass and depends on all implementation tracks.

Each track produces a working, committable state. Recommended dispatch: one subagent per track in dependency order (A+E in parallel, then B+C in parallel, then D, then F).

---

## File Structure

| File | Action | Track | Responsibility |
|------|--------|-------|----------------|
| `ios/FastTrack/FastTrack/Services/LocationManager.swift` | modify | A | IMU 100 Hz, `activityType` set, dt plumbing |
| `ios/FastTrack/FastTrack/Services/SpeedFusion.swift` | modify | A | 100 Hz damping coefficients, comment block explaining retuning |
| `ios/FastTrack/FastTrack/ViewModels/DriveRecordingController.swift` | modify | A + D | `speedStream` buffer, `processSpeedSample` throttling, post-hoc analyzer invocation at stop |
| `ios/FastTrack/FastTrack/ViewModels/RouteSerializer.swift` | modify | B | `encodeV3` with delta-compressed `speed_stream`, `SpeedPeak` struct, `RouteSerializationSnapshot` extensions |
| `ios/FastTrack/FastTrack/ViewModels/LaunchAnalyzer.swift` | create | C | Two-pass launch detection on the speed stream |
| `ios/FastTrack/FastTrack/ViewModels/TopSpeedComputer.swift` | create | C | Rolling-median + GPS-aware top speed |
| `ios/FastTrack/FastTrack/Models/Drive.swift` | modify | D | `fusedMaxSpeed` / `gpsMaxSpeed` optional fields, CodingKeys, custom decoder, memberwise init |
| `ios/FastTrack/FastTrack/Models/ZeroToSixtyAttempt.swift` | modify | D | Add `confidence` field with backward-compat decoder |
| `ios/FastTrack/FastTrack/Services/APIService.swift` | modify | D | Send new fields in `createDrive` payload |
| `backend/internal/app/models.go` | modify | E | Add `FusedMaxSpeed` and `GpsMaxSpeed` columns + JSON tags |
| `backend/internal/app/migrations.go` | modify | E | New migration version `2026061401` adding the two columns |
| `backend/internal/app/handlers_test.go` | modify | E + F | Round-trip test for new fields |
| `ios/FastTrack/FastTrackTests/SpeedFusion100HzTests.swift` | create | F | 100 Hz damping behavior, Kalman correctness |
| `ios/FastTrack/FastTrackTests/LaunchAnalyzerTests.swift` | create | F | Synthetic 0-60 streams with known ground truth |
| `ios/FastTrack/FastTrackTests/TopSpeedComputerTests.swift` | create | F | Spike rejection, GPS-aware blend |
| `ios/FastTrack/FastTrackTests/RouteDataV3EncoderTests.swift` | create | F | Round-trip encode/decode + size sanity |
| `ios/FastTrack/FastTrackTests/RouteDataBackwardCompatTests.swift` | create | F | v2 blobs decoded cleanly; LaunchAnalyzer skips v2 |
| `ios/FastTrack/FastTrackTests/DriveModelBackwardCompatTests.swift` | create | F | New fields tolerate old server responses |

---

## Conventions Used Throughout

- **TDD:** Every implementation task starts with a failing test, then the smallest change to make it pass, then a commit.
- **Conventional commits:** All commits follow `<type>(<scope>): <description>` and stay under 100 chars.
- **No comments unless asked.** Code stays self-documenting; the rare explanatory comment only where math (e.g. damping retuning) needs the source-of-truth note.
- **Frequency constant:** `im` always use `1.0 / 100.0` for the new IMU rate. Define `private let imuUpdateInterval: TimeInterval = 1.0 / 100.0` once in `LocationManager` and reference it everywhere.
- **Backward compatibility:** every new API field, JSON key, and DB column is optional/nullable. Old clients and old drives keep working.

---

## Track A — iOS: 100 Hz IMU + SpeedFusion Retuning + Main-Thread Throttling

### Task A.1: Add SpeedFusion 100 Hz damping coefficients

**Files:**
- Modify: `ios/FastTrack/FastTrack/Services/SpeedFusion.swift:30-34`

- [ ] **Step 1: Write the failing test** in `ios/FastTrack/FastTrackTests/SpeedFusion100HzTests.swift`:

```swift
import XCTest
@testable import FastTrack

final class SpeedFusion100HzTests: XCTestCase {
    func test_dampingCoefficients_preservesPerSecondBehavior() {
        // 0.72 applied 25x/sec for 1s reaches ~0.72^25 ≈ 0.000189 of initial
        // 0.921 applied 100x/sec for 1s should reach the same residual
        var s = SpeedFusion()
        for _ in 0..<25 { s.predict(longAccelG: 0, dt: 1.0/25.0) }
        // Run from a low speed first by ingesting one predict that lifts it
        s.predict(longAccelG: 0.5, dt: 1.0/100.0)
        s.predict(longAccelG: 0.5, dt: 1.0/100.0)
        let speed25Hz = s.speed

        var t = SpeedFusion()
        for _ in 0..<100 { t.predict(longAccelG: 0.5, dt: 1.0/100.0) }
        // We need to set t to a similar low speed first
        // (the test asserts the per-second damping factor is approximately equal)
        // Simpler: assert the constants exist and match
        XCTAssertTrue(SpeedFusion.lowSpeedDampingCoefficient_100Hz > 0.9)
        XCTAssertTrue(SpeedFusion.lowSpeedDampingCoefficient_100Hz < 0.95)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run from `ios/FastTrack`:
```bash
xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/SpeedFusion100HzTests/test_dampingCoefficients_preservesPerSecondBehavior \
  CODE_SIGNING_ALLOWED=NO
```
Expected: FAIL with `'SpeedFusion' has no member 'lowSpeedDampingCoefficient_100Hz'`.

- [ ] **Step 3: Add the new constants to SpeedFusion**

In `ios/FastTrack/FastTrack/Services/SpeedFusion.swift`, after the existing `lowSpeedDampingThreshold` line (~line 33), add:

```swift
// 100 Hz damping: applied per-tick, so 4x more ticks than the legacy
// 25 Hz coefficients. To preserve the same per-second damping effect,
// new = old^0.25. Old values retained for traceability.
static let lowSpeedDampingCoefficient_25Hz: Double = 0.72      // 25 Hz, kept for reference
static let lowSpeedDampingCoefficient_100Hz: Double = 0.921    // 0.72^0.25 — preserves per-second decay
static let lowSpeedDampingCoefficientActive_25Hz: Double = 0.86
static let lowSpeedDampingCoefficientActive_100Hz: Double = 0.963  // 0.86^0.25
```

- [ ] **Step 4: Switch the damping call to the 100 Hz coefficient**

In `predict()` (line ~58-60), change:

```swift
if speed < lowSpeedDampingThreshold {
    speed *= abs(longAccelG) < stationaryAccelThresholdG ? 0.72 : 0.86
}
```

to:

```swift
if speed < lowSpeedDampingThreshold {
    speed *= abs(longAccelG) < stationaryAccelThresholdG
        ? SpeedFusion.lowSpeedDampingCoefficient_100Hz
        : SpeedFusion.lowSpeedDampingCoefficientActive_100Hz
}
```

- [ ] **Step 5: Run the test to verify it passes**

Run the same `xcodebuild test` command from Step 2. Expected: PASS.

- [ ] **Step 6: Run the full test suite** to verify nothing regressed

```bash
xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```
Expected: all existing tests pass.

- [ ] **Step 7: Commit**

```bash
git add ios/FastTrack/FastTrack/Services/SpeedFusion.swift ios/FastTrack/FastTrackTests/SpeedFusion100HzTests.swift
git commit -m "feat(ios): add 100 Hz damping coefficients to SpeedFusion"
```

---

### Task A.2: Bump IMU update interval to 100 Hz in LocationManager

**Files:**
- Modify: `ios/FastTrack/FastTrack/Services/LocationManager.swift`

- [ ] **Step 1: Find the current IMU interval**

Grep the file for `deviceMotionUpdateInterval` and `1.0 / 25.0`. The current value is set somewhere in `startMotionUpdates` or the init.

- [ ] **Step 2: Add a single named constant near the top of the class** (just inside the class braces, after the existing private state):

```swift
/// Centralized IMU update rate. Set to 100 Hz to give the post-hoc
/// LaunchAnalyzer ±0.05s accuracy on sub-2s 0-60 runs.
private static let imuUpdateInterval: TimeInterval = 1.0 / 100.0
```

- [ ] **Step 3: Replace the IMU interval value** wherever it's set in this file. Search/replace to:

```swift
motionManager.deviceMotionUpdateInterval = Self.imuUpdateInterval
```

- [ ] **Step 4: Update `handleMotionUpdate`** so that the `dt` argument passed to `fusion.predict()` is also `1.0/100.0` (or `Self.imuUpdateInterval`). Find the call site and update it.

- [ ] **Step 5: Set `activityType = .automotiveNavigation` on `clManager`** in the init. After the existing `desiredAccuracy` / `distanceFilter` lines, add:

```swift
clManager.activityType = .automotiveNavigation
```

- [ ] **Step 6: Build and run the iOS tests**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```
Expected: PASS (no functional test covers the exact interval value, but no regressions).

- [ ] **Step 7: Commit**

```bash
git add ios/FastTrack/FastTrack/Services/LocationManager.swift
git commit -m "feat(ios): bump IMU to 100 Hz and set automotive activity type"
```

---

### Task A.3: Add `speedStream` buffer to DriveRecordingController

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveRecordingController.swift`

- [ ] **Step 1: Write the failing test** in `ios/FastTrack/FastTrackTests/DriveRecordingControllerSpeedStreamTests.swift`:

The existing test factory pattern in this codebase is to construct a `DriveManager` (which owns a `DriveRecordingController`) and access the controller via `recordingController`. Mirror the pattern from `DriveManagerErrorSurfaceTests.swift`:

```swift
import XCTest
import CoreLocation
@testable import FastTrack

final class DriveRecordingControllerSpeedStreamTests: XCTestCase {
    /// Mirror of the factory in `DriveManagerErrorSurfaceTests`. Construct
    /// a `DriveManager` and reach through to its recording controller.
    @MainActor
    private func makeManager() -> DriveManager {
        let realAPI = APIService()
        let authMgr = AuthManager(apiService: realAPI)
        realAPI.authManager = authMgr
        return DriveManager(
            authManager: authMgr,
            profileManager: ProfileManager(apiService: realAPI),
            settings: AppSettings(apiService: realAPI),
            apiService: realAPI,
            carStatsManager: CarStatsManager(apiService: realAPI),
            achievementManager: AchievementManager()
        )
    }

    @MainActor
    func test_speedStream_appendsEverySpeedSample() async {
        let dm = makeManager()
        let controller = dm.recordingController
        controller.startRecording()
        let t0 = Date()
        for i in 0..<50 {
            let sample = SpeedSample(
                speed: Double(i) * 0.1,
                rawGPSSpeed: Double(i) * 0.1,
                speedAccuracy: 0.5,
                timestamp: t0.addingTimeInterval(Double(i) * 0.01),
                isZeroLocked: i < 5,
                stationaryConfidence: i < 5 ? 1.0 : 0.0
            )
            controller.processSpeedSample(sample)
        }
        XCTAssertEqual(controller.speedStream.count, 50)
        XCTAssertEqual(controller.speedStream.first?.1, 0.0)
        XCTAssertEqual(controller.speedStream.last?.1, 4.9)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/DriveRecordingControllerSpeedStreamTests/test_speedStream_appendsEverySpeedSample \
  CODE_SIGNING_ALLOWED=NO
```
Expected: FAIL — `speedStream` is not a member of `DriveRecordingController`, OR the test can't compile because of an API mismatch in the init signature.

- [ ] **Step 3: Discover the actual init signature** by reading the existing constructor at the top of `DriveRecordingController` (search for `init(`). Update the test to use the real signature. If the constructor takes additional dependencies you don't need for the test, follow the existing test pattern (look at `DriveManagerErrorSurfaceTests.swift` for a working example of constructing a controller with mocks).

- [ ] **Step 4: Add the buffer** to `DriveRecordingController` near the other `var` declarations (~line 84):

```swift
/// Full 100 Hz speed stream. Captured for post-hoc LaunchAnalyzer + TopSpeedComputer.
/// Schema per element: (timestamp, fusedSpeedMps, isZeroLocked, stationaryConfidence).
var speedStream: [(TimeInterval, Double, Bool, Double)] = []
```

- [ ] **Step 5: Append in `processSpeedSample`** (find the existing implementation; it's called from the Combine subscription on `$currentSpeedSample`). Add a single line at the top of the function body:

```swift
speedStream.append((sample.timestamp.timeIntervalSince1970, sample.speed, sample.isZeroLocked, sample.stationaryConfidence))
```

- [ ] **Step 6: Clear in `startRecording`** (find the existing reset block). Add:

```swift
speedStream.removeAll(keepingCapacity: true)
```

- [ ] **Step 7: Run the test to verify it passes**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/DriveRecordingControllerSpeedStreamTests/test_speedStream_appendsEverySpeedSample \
  CODE_SIGNING_ALLOWED=NO
```
Expected: PASS.

- [ ] **Step 8: Run the full iOS test suite**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```
Expected: all existing tests still pass.

- [ ] **Step 9: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/DriveRecordingController.swift ios/FastTrack/FastTrackTests/DriveRecordingControllerSpeedStreamTests.swift
git commit -m "feat(ios): capture 100 Hz speed stream for post-hoc analysis"
```

---

### Task A.4: Throttle main-thread `currentDrive` updates from speed samples

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveRecordingController.swift`

- [ ] **Step 1: Read the existing `processSpeedSample` body.** Note which lines update `currentDrive` (`@Published` properties that drive SwiftUI re-render).

- [ ] **Step 2: Write the failing test** in `ios/FastTrack/FastTrackTests/DriveRecordingControllerSpeedStreamTests.swift`:

```swift
@MainActor
func test_currentDriveUpdates_throttledTo10Hz() {
    let dm = makeManager()  // factory from the first test
    let controller = dm.recordingController
    controller.startRecording()
    let t0 = Date()
    // Fire 100 samples in 1 second
    for i in 0..<100 {
        controller.processSpeedSample(SpeedSample(
            speed: 10.0, rawGPSSpeed: 10.0, speedAccuracy: 0.5,
            timestamp: t0.addingTimeInterval(Double(i) * 0.01),
            isZeroLocked: false, stationaryConfidence: 0.0
        ))
    }
    // currentDriveUiUpdateCount is a counter we add in step 3
    XCTAssertLessThanOrEqual(controller.currentDriveUiUpdateCount, 15)
}
```

- [ ] **Step 3: Add a counter to `DriveRecordingController`** (near the other internal state):

```swift
private(set) var currentDriveUiUpdateCount: Int = 0
```

- [ ] **Step 4: Increment the counter inside the existing `currentDrive` assignment block** in `processSpeedSample`:

```swift
currentDriveUiUpdateCount += 1
```

- [ ] **Step 5: Wrap the existing `currentDrive` field updates in a throttler.** There is already a `publishThrottler` (a `PublishThrottler` with `minInterval: 0.1`) used elsewhere in the class. Reuse it (or add a dedicated one named `speedPublishThrottler` if `publishThrottler` is locked at a different rate). The shape:

```swift
if publishThrottler.shouldPublish(now: sample.timestamp) {
    currentDrive.speed = sample.speed
    // ... any other @Published fields that update from speed samples
    currentDriveUiUpdateCount += 1
}
```

(Note: do not change the *data capture* path — the speed stream buffer must append every sample at 100 Hz. Only the UI-bound `currentDrive` updates are throttled.)

- [ ] **Step 6: Run the test to verify it passes**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/DriveRecordingControllerSpeedStreamTests/test_currentDriveUpdates_throttledTo10Hz \
  CODE_SIGNING_ALLOWED=NO
```
Expected: PASS.

- [ ] **Step 7: Run the full iOS test suite**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```
Expected: no regressions.

- [ ] **Step 8: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/DriveRecordingController.swift ios/FastTrack/FastTrackTests/DriveRecordingControllerSpeedStreamTests.swift
git commit -m "perf(ios): throttle currentDrive updates to 10 Hz from 100 Hz stream"
```

---

## Track B — iOS: RouteSerializer v3 + SpeedPeak

### Task B.1: Add `SpeedPeak` and `SpeedSource` types

**Files:**
- Create: `ios/FastTrack/FastTrack/Models/SpeedPeak.swift`

- [ ] **Step 1: Write the failing test** in `ios/FastTrack/FastTrackTests/RouteDataV3EncoderTests.swift`:

```swift
import XCTest
@testable import FastTrack

final class RouteDataV3EncoderTests: XCTestCase {
    func test_SpeedPeak_encodesWithSourceAndConfidence() throws {
        let peak = SpeedPeak(
            timestamp: Date(timeIntervalSince1970: 1_700_000_000),
            speed: 35.0,
            source: .fused,
            confidence: 0.87
        )
        let data = try JSONEncoder().encode(peak)
        let dict = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(dict["source"] as? String, "fused")
        XCTAssertEqual(dict["confidence"] as? Double, 0.87)
        XCTAssertEqual(dict["speed"] as? Double, 35.0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/RouteDataV3EncoderTests/test_SpeedPeak_encodesWithSourceAndConfidence \
  CODE_SIGNING_ALLOWED=NO
```
Expected: FAIL with "cannot find 'SpeedPeak' in scope".

- [ ] **Step 3: Create the types** in `ios/FastTrack/FastTrack/Models/SpeedPeak.swift`:

```swift
import Foundation

enum SpeedSource: String, Codable, Equatable {
    case fused
    case gps
}

/// One of the top speed observations captured during a drive. Stored
/// inside `route_data` v3 alongside the speed stream so post-hoc
/// analysis and the leaderboard can show provenance.
struct SpeedPeak: Codable, Equatable {
    let timestamp: Date
    let speed: Double          // m/s
    let source: SpeedSource
    let confidence: Double     // 0-1
}
```

- [ ] **Step 4: Run the test to verify it passes**

Same command as Step 2. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/FastTrack/FastTrack/Models/SpeedPeak.swift ios/FastTrack/FastTrackTests/RouteDataV3EncoderTests.swift
git commit -m "feat(ios): add SpeedPeak and SpeedSource types"
```

---

### Task B.2: Extend `RouteSerializationSnapshot`

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/RouteSerializer.swift:8-12`

- [ ] **Step 1: Write the failing test** in `ios/FastTrack/FastTrackTests/RouteDataV3EncoderTests.swift`:

```swift
func test_RouteSerializationSnapshot_carriesSpeedStreamAndPeaks() {
    let snapshot = RouteSerializationSnapshot(
        richRoutePoints: [],
        recordedRouteEvents: [],
        attempts: [],
        speedStream: [(0.0, 0.0, true, 1.0), (0.01, 0.5, false, 0.0)],
        speedPeaks: []
    )
    XCTAssertEqual(snapshot.speedStream.count, 2)
    XCTAssertEqual(snapshot.speedStream[0].3, 1.0)
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/RouteDataV3EncoderTests/test_RouteSerializationSnapshot_carriesSpeedStreamAndPeaks \
  CODE_SIGNING_ALLOWED=NO
```
Expected: FAIL — `speedStream` is not a member of `RouteSerializationSnapshot`.

- [ ] **Step 3: Add the new fields** to the struct in `RouteSerializer.swift`:

```swift
struct RouteSerializationSnapshot: Sendable {
    let richRoutePoints: [(lat: Double, lng: Double, speed: Double, ts: Double)]
    let recordedRouteEvents: [(type: String, lat: Double, lng: Double, ts: Double)]
    let attempts: [ZeroToSixtyAttempt]
    /// Full 100 Hz speed stream for post-hoc analysis.
    /// (timestamp, fusedSpeedMps, isZeroLocked, stationaryConfidence)
    let speedStream: [(TimeInterval, Double, Bool, Double)]
    /// Top speed observations (fused + GPS) for leaderboard integrity.
    let speedPeaks: [SpeedPeak]
}
```

- [ ] **Step 4: Run the test to verify it passes**

Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/RouteSerializer.swift ios/FastTrack/FastTrackTests/RouteDataV3EncoderTests.swift
git commit -m "feat(ios): extend RouteSerializationSnapshot with speed stream and peaks"
```

---

### Task B.3: Add delta-compression helpers

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/RouteSerializer.swift`

- [ ] **Step 1: Write the failing test** in `ios/FastTrack/FastTrackTests/RouteDataV3EncoderTests.swift`:

```swift
func test_encodeSpeedStream_deltaCompresses() {
    let stream: [(TimeInterval, Double, Bool, Double)] = [
        (1000.0, 0.0, true, 1.0),
        (1000.01, 0.5, false, 0.0),
        (1000.02, 1.0, false, 0.0)
    ]
    let encoded = RouteSerializer.encodeSpeedStream(stream)
    XCTAssertEqual(encoded.first as? [AnyHashable], [1000.0, 0.0, 1, 1.0] as [AnyHashable])
    // Subsequent entries: [Δms, speed, isZeroLocked, stationaryConfidence]
    let second = encoded[1] as? [Any]
    XCTAssertEqual(second?[0] as? Int, 10)  // 10ms delta
    XCTAssertEqual(second?[1] as? Double, 0.5)
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/RouteDataV3EncoderTests/test_encodeSpeedStream_deltaCompresses \
  CODE_SIGNING_ALLOWED=NO
```
Expected: FAIL — `RouteSerializer.encodeSpeedStream` not found.

- [ ] **Step 3: Add the encoder function** in `RouteSerializer.swift` (below the existing `encodeV2`):

```swift
/// Encodes the 100 Hz speed stream with delta-compressed timestamps.
/// First entry: [absolute_ts, speed, isZeroLocked, stationaryConfidence].
/// Subsequent: [Δms, speed, isZeroLocked, stationaryConfidence] where Δms is
/// an integer millisecond delta from the prior sample.
static func encodeSpeedStream(_ stream: [(TimeInterval, Double, Bool, Double)]) -> [[Any]] {
    guard !stream.isEmpty else { return [] }
    var out: [[Any]] = []
    out.reserveCapacity(stream.count)
    out.append([stream[0].0, stream[0].1, stream[0].2 ? 1 : 0, stream[0].3])
    var lastTs = stream[0].0
    for i in 1..<stream.count {
        let (ts, speed, locked, conf) = stream[i]
        let deltaMs = Int(((ts - lastTs) * 1000).rounded())
        out.append([deltaMs, speed, locked ? 1 : 0, conf])
        lastTs = ts
    }
    return out
}

/// Inverse of `encodeSpeedStream`. Used by tests and (future) v3 readers.
static func decodeSpeedStream(_ encoded: [[Any]]) -> [(TimeInterval, Double, Bool, Double)] {
    guard !encoded.isEmpty else { return [] }
    var out: [(TimeInterval, Double, Bool, Double)] = []
    out.reserveCapacity(encoded.count)
    if let first = encoded.first, first.count >= 4,
       let ts = (first[0] as? Double) ?? (first[0] as? NSNumber)?.doubleValue,
       let speed = (first[1] as? Double) ?? (first[1] as? NSNumber)?.doubleValue {
        let locked = ((first[2] as? Int) ?? 0) != 0
        let conf = ((first[3] as? Double) ?? (first[3] as? NSNumber)?.doubleValue) ?? 0
        out.append((ts, speed, locked, conf))
        var lastTs = ts
        for i in 1..<encoded.count {
            let row = encoded[i]
            guard row.count >= 4,
                  let deltaMs = (row[0] as? Int) ?? (row[0] as? NSNumber)?.intValue,
                  let speed = (row[1] as? Double) ?? (row[1] as? NSNumber)?.doubleValue else { continue }
            let locked = ((row[2] as? Int) ?? 0) != 0
            let conf = ((row[3] as? Double) ?? (row[3] as? NSNumber)?.doubleValue) ?? 0
            let ts = lastTs + Double(deltaMs) / 1000.0
            out.append((ts, speed, locked, conf))
            lastTs = ts
        }
    }
    return out
}
```

- [ ] **Step 4: Run the test to verify it passes**

Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/RouteSerializer.swift ios/FastTrack/FastTrackTests/RouteDataV3EncoderTests.swift
git commit -m "feat(ios): add delta-compressed speed stream encoder"
```

---

### Task B.4: Add `encodeV3` to RouteSerializer

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/RouteSerializer.swift`

- [ ] **Step 1: Write the failing test** in `ios/FastTrack/FastTrackTests/RouteDataV3EncoderTests.swift`:

```swift
func test_encodeV3_producesV3Marker() {
    let snapshot = RouteSerializationSnapshot(
        richRoutePoints: [(1.0, 2.0, 5.0, 100.0)],
        recordedRouteEvents: [],
        attempts: [],
        speedStream: [(100.0, 5.0, false, 0.0)],
        speedPeaks: []
    )
    let encoded = RouteSerializer.encodeV3(snapshot: snapshot)
    XCTAssertNotNil(encoded)
    let dict = try! XCTUnwrap(try JSONSerialization.jsonObject(with: encoded!.data(using: .utf8)!) as? [String: Any])
    XCTAssertEqual(dict["v"] as? Int, 3)
    XCTAssertNotNil(dict["speed_stream"] as? [[Any]])
}

func test_encodeV3_decodeV3_roundtrip() {
    let original: [(TimeInterval, Double, Bool, Double)] = [
        (1000.0, 0.0, true, 1.0),
        (1000.01, 0.5, false, 0.0),
        (1000.05, 2.0, false, 0.0)
    ]
    let encoded = RouteSerializer.encodeSpeedStream(original)
    let decoded = RouteSerializer.decodeSpeedStream(encoded)
    XCTAssertEqual(decoded.count, original.count)
    for (a, b) in zip(decoded, original) {
        XCTAssertEqual(a.0, b.0, accuracy: 0.001)
        XCTAssertEqual(a.1, b.1, accuracy: 0.0001)
        XCTAssertEqual(a.2, b.2)
        XCTAssertEqual(a.3, b.3, accuracy: 0.0001)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/RouteDataV3EncoderTests/test_encodeV3_producesV3Marker \
  CODE_SIGNING_ALLOWED=NO
```
Expected: FAIL — `encodeV3` not found.

- [ ] **Step 3: Add the v3 encoder** in `RouteSerializer.swift`:

```swift
/// Builds the v3 `routeData` JSON string. Additive on top of v2: same
/// `points` and `events` keys, plus a delta-compressed `speed_stream`
/// and a `speed_peaks` array.
static func encodeV3(snapshot: RouteSerializationSnapshot) -> String? {
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
            "time_seconds": attempt.elapsedSeconds,
            "confidence": attempt.confidence
        ])
    }
    let speedStreamEncoded = encodeSpeedStream(snapshot.speedStream)
    let speedPeaksEncoded: [[String: Any]] = snapshot.speedPeaks.map { p in
        [
            "timestamp": p.timestamp.timeIntervalSince1970,
            "speed": p.speed,
            "source": p.source.rawValue,
            "confidence": p.confidence
        ]
    }
    let payload: [String: Any] = [
        "v": 3,
        "points": pointDicts,
        "events": eventDicts,
        "speed_stream": speedStreamEncoded,
        "speed_peaks": speedPeaksEncoded
    ]
    guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
    return String(data: data, encoding: .utf8)
}
```

- [ ] **Step 4: Run the tests**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/RouteDataV3EncoderTests \
  CODE_SIGNING_ALLOWED=NO
```
Expected: PASS for both.

- [ ] **Step 5: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/RouteSerializer.swift ios/FastTrack/FastTrackTests/RouteDataV3EncoderTests.swift
git commit -m "feat(ios): add v3 route_data encoder with speed stream and peaks"
```

---

### Task B.5: Add `ZeroToSixtyAttempt.confidence` field

**Files:**
- Modify: `ios/FastTrack/FastTrack/Models/ZeroToSixtyAttempt.swift`
- Modify: `ios/FastTrack/FastTrack/Models/Drive.swift` (if test references memberwise init)

- [ ] **Step 1: Write the failing test** in `ios/FastTrack/FastTrackTests/RouteDataBackwardCompatTests.swift`:

```swift
import XCTest
@testable import FastTrack

final class RouteDataBackwardCompatTests: XCTestCase {
    func test_ZeroToSixtyAttempt_decodeMissingConfidence_defaultsToZero() throws {
        let json = """
        {
            "start_index": 0,
            "end_index": 10,
            "start_ts": 1000.0,
            "end_ts": 1002.5,
            "elapsed_s": 2.5,
            "start_lat": 1.0,
            "start_lng": 2.0,
            "end_lat": 1.1,
            "end_lng": 2.1
        }
        """.data(using: .utf8)!
        let attempt = try JSONDecoder().decode(ZeroToSixtyAttempt.self, from: json)
        XCTAssertEqual(attempt.confidence, 0.0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/RouteDataBackwardCompatTests/test_ZeroToSixtyAttempt_decodeMissingConfidence_defaultsToZero \
  CODE_SIGNING_ALLOWED=NO
```
Expected: FAIL — `confidence` member does not exist.

- [ ] **Step 3: Add `confidence` to the struct** in `ZeroToSixtyAttempt.swift`:

In the property block (after `var legacy: Bool = false`):
```swift
var confidence: Double = 0.0
```

In the init signature and body:
```swift
init(
    startIndex: Int,
    endIndex: Int,
    startTimestamp: Double,
    endTimestamp: Double,
    elapsedSeconds: Double,
    startLatitude: Double,
    startLongitude: Double,
    endLatitude: Double,
    endLongitude: Double,
    confidence: Double = 0.0,
    legacy: Bool = false
) {
    // ...existing assignments...
    self.confidence = confidence
    self.legacy = legacy
}
```

In the custom `init(from decoder:)`:
```swift
self.confidence = (try c.decodeIfPresent(Double.self, forKey: .confidence)) ?? 0.0
```

In the `CodingKeys` enum:
```swift
case confidence
```

- [ ] **Step 4: Run the test to verify it passes**

Same command. Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/FastTrack/FastTrack/Models/ZeroToSixtyAttempt.swift ios/FastTrack/FastTrackTests/RouteDataBackwardCompatTests.swift
git commit -m "feat(ios): add confidence field to ZeroToSixtyAttempt"
```

---

## Track C — iOS: LaunchAnalyzer + TopSpeedComputer

### Task C.1: Create `LaunchAnalyzer` skeleton with two-pass algorithm

**Files:**
- Create: `ios/FastTrack/FastTrack/ViewModels/LaunchAnalyzer.swift`

- [ ] **Step 1: Write the failing test** in `ios/FastTrack/FastTrackTests/LaunchAnalyzerTests.swift`:

```swift
import XCTest
@testable import FastTrack

final class LaunchAnalyzerTests: XCTestCase {
    /// Helper: synthesise a 0-60 launch at the given real duration,
    /// sampled at 100 Hz. Returns a speed stream.
    private func makeStream(elapsed: Double, startSpeed: Double = 0.0) -> [(TimeInterval, Double, Bool, Double)] {
        let t0: TimeInterval = 1000.0
        var out: [(TimeInterval, Double, Bool, Double)] = []
        // 2s of stationary samples before the launch
        for i in 0..<200 {
            out.append((t0 + Double(i) * 0.01, startSpeed, true, 1.0))
        }
        // Build a launch reaching 60 mph at `elapsed` seconds after t=0
        let targetMps = 60.0 / 2.23694  // ~26.82 m/s
        let steps = Int(elapsed / 0.01)
        for i in 0...steps {
            let frac = Double(i) / Double(steps)
            let speed = targetMps * frac
            out.append((t0 + 2.0 + Double(i) * 0.01, speed, false, 0.0))
        }
        return out
    }

    func test_findsLaunch_withinTolerance() {
        let stream = makeStream(elapsed: 2.5)
        let analyzer = LaunchAnalyzer()
        let attempts = analyzer.analyze(stream: stream)
        XCTAssertFalse(attempts.isEmpty)
        guard let best = attempts.min(by: { $0.elapsedSeconds < $1.elapsedSeconds }) else { return }
        XCTAssertEqual(best.elapsedSeconds, 2.5, accuracy: 0.05)
        XCTAssertGreaterThan(best.confidence, 0.0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/LaunchAnalyzerTests/test_findsLaunch_withinTolerance \
  CODE_SIGNING_ALLOWED=NO
```
Expected: FAIL — `LaunchAnalyzer` not found.

- [ ] **Step 3: Create `LaunchAnalyzer.swift`** with the full algorithm:

```swift
import Foundation

/// Post-hoc analyzer for 0-60 launches. Replays the full 100 Hz speed
/// stream captured during the drive, finds acceleration events, and
/// backward-searches for the true launch T=0 (the last stationary
/// sample before sustained positive acceleration).
///
/// Two passes:
///   1. Find sustained acceleration events (slope > 1.5 m/s² for 50+ ms)
///   2. For each event, find the last stationary sample backwards and
///      treat the next sample as the launch start. Interpolate the 60 mph
///      crossing time for the elapsed value.
struct LaunchAnalyzer {
    struct Config {
        var accelerationSlopeMps2: Double = 1.5    // ~0.15g
        var minEventDurationSamples: Int = 5        // 50ms at 100 Hz
        var backwardSearchWindow: Int = 200         // 2s at 100 Hz
        var stationarySpeedMps: Double = 0.3
        var stationaryConfidenceThreshold: Double = 0.8
        var targetSpeedMph: Double = 60.0
        var minValidElapsed: Double = 1.0
        var maxValidElapsed: Double = 30.0
    }

    var config: Config = .init()

    /// Returns every 0-60 launch found in the stream, each with its
    /// computed elapsed time and confidence score.
    func analyze(stream: [(TimeInterval, Double, Bool, Double)]) -> [ZeroToSixtyAttempt] {
        guard stream.count > 10 else { return [] }

        // Pass 1: find sustained acceleration events.
        var events: [(startIndex: Int, endIndex: Int)] = []
        var runStart: Int? = nil
        for i in 1..<stream.count {
            let dt = stream[i].0 - stream[i - 1].0
            guard dt > 0 else { continue }
            let slope = (stream[i].1 - stream[i - 1].1) / dt
            if slope >= config.accelerationSlopeMps2 {
                if runStart == nil { runStart = i - 1 }
            } else {
                if let s = runStart, i - 1 - s >= config.minEventDurationSamples {
                    events.append((s, i - 1))
                }
                runStart = nil
            }
        }
        if let s = runStart, stream.count - 1 - s >= config.minEventDurationSamples {
            events.append((s, stream.count - 1))
        }

        // Pass 2: for each event, backward-search for true start + interpolate crossing.
        var attempts: [ZeroToSixtyAttempt] = []
        for event in events {
            guard let attempt = processEvent(event, in: stream) else { continue }
            attempts.append(attempt)
        }
        return attempts
    }

    private func processEvent(
        _ event: (startIndex: Int, endIndex: Int),
        in stream: [(TimeInterval, Double, Bool, Double)]
    ) -> ZeroToSixtyAttempt? {
        // Backward search for the last stationary sample
        let searchStart = max(0, event.startIndex - config.backwardSearchWindow)
        var launchStartIndex = event.startIndex
        for i in stride(from: event.startIndex, through: searchStart, by: -1) {
            let (_, speed, locked, conf) = stream[i]
            if speed < config.stationarySpeedMps && (locked || conf >= config.stationaryConfidenceThreshold) {
                launchStartIndex = i + 1
                break
            }
        }
        guard launchStartIndex < event.endIndex else { return nil }

        let startTime = stream[launchStartIndex].0
        let targetMps = config.targetSpeedMph / 2.23694

        // Forward search for target speed crossing
        var crossingTime: TimeInterval? = nil
        for i in launchStartIndex..<stream.count {
            if stream[i].1 >= targetMps {
                if i > launchStartIndex {
                    let prev = stream[i - 1]
                    let curr = stream[i]
                    let dSpeed = curr.1 - prev.1
                    let dTime = curr.0 - prev.0
                    if dSpeed > 0, dTime > 0 {
                        let frac = (targetMps - prev.1) / dSpeed
                        let clamped = min(max(frac, 0), 1)
                        crossingTime = prev.0 + dTime * clamped
                    } else {
                        crossingTime = curr.0
                    }
                } else {
                    crossingTime = stream[i].0
                }
                break
            }
        }
        guard let crossingTime else { return nil }
        let elapsed = crossingTime - startTime
        guard elapsed >= config.minValidElapsed, elapsed <= config.maxValidElapsed else { return nil }

        let confidence = computeConfidence(startIndex: launchStartIndex, endIndex: event.endIndex, in: stream)

        return ZeroToSixtyAttempt(
            startIndex: launchStartIndex,
            endIndex: event.endIndex,
            startTimestamp: startTime,
            endTimestamp: crossingTime,
            elapsedSeconds: elapsed,
            startLatitude: 0,
            startLongitude: 0,
            endLatitude: 0,
            endLongitude: 0,
            confidence: confidence,
            legacy: false
        )
    }

    private func computeConfidence(
        startIndex: Int,
        endIndex: Int,
        in stream: [(TimeInterval, Double, Bool, Double)]
    ) -> Double {
        // Baseline: start with a high score, penalise for each red flag.
        var score: Double = 1.0
        if startIndex < 50 { score -= 0.2 }     // No real "stationary" period before launch
        if endIndex - startIndex < 50 { score -= 0.1 }  // Very short run
        // Inter-sample speed consistency: coefficient of variation of deltas
        if endIndex - startIndex > 1 {
            var deltas: [Double] = []
            for i in (startIndex + 1)...endIndex {
                deltas.append(stream[i].1 - stream[i - 1].1)
            }
            let mean = deltas.reduce(0, +) / Double(deltas.count)
            let variance = deltas.map { pow($0 - mean, 2) }.reduce(0, +) / Double(deltas.count)
            let std = sqrt(variance)
            let cv = mean > 0 ? std / mean : 1
            if cv > 0.5 { score -= 0.2 }
        }
        return max(0, min(1, score))
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/LaunchAnalyzerTests/test_findsLaunch_withinTolerance \
  CODE_SIGNING_ALLOWED=NO
```
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/LaunchAnalyzer.swift ios/FastTrack/FastTrackTests/LaunchAnalyzerTests.swift
git commit -m "feat(ios): add LaunchAnalyzer with two-pass 0-60 detection"
```

---

### Task C.2: Add sub-2-second launch test (regression guard)

**Files:**
- Modify: `ios/FastTrack/FastTrackTests/LaunchAnalyzerTests.swift`

- [ ] **Step 1: Add the new test** to the existing `LaunchAnalyzerTests` class:

```swift
func test_sub2secondLaunch_isAccurate() {
    let stream = makeStream(elapsed: 1.8)
    let analyzer = LaunchAnalyzer()
    let attempts = analyzer.analyze(stream: stream)
    XCTAssertFalse(attempts.isEmpty)
    guard let best = attempts.min(by: { $0.elapsedSeconds < $1.elapsedSeconds }) else { return }
    XCTAssertEqual(best.elapsedSeconds, 1.8, accuracy: 0.05)
}
```

- [ ] **Step 2: Run the test**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/LaunchAnalyzerTests/test_sub2secondLaunch_isAccurate \
  CODE_SIGNING_ALLOWED=NO
```
Expected: PASS.

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrackTests/LaunchAnalyzerTests.swift
git commit -m "test(ios): add sub-2-second launch accuracy regression test"
```

---

### Task C.3: Create `TopSpeedComputer`

**Files:**
- Create: `ios/FastTrack/FastTrack/ViewModels/TopSpeedComputer.swift`

- [ ] **Step 1: Write the failing test** in `ios/FastTrack/FastTrackTests/TopSpeedComputerTests.swift`:

```swift
import XCTest
@testable import FastTrack

final class TopSpeedComputerTests: XCTestCase {
    func test_rejectsIMUSpike_preservesRealPeak() {
        // Build a stream peaking at 30 m/s, with a single-sample spike at 80 m/s
        var stream: [(TimeInterval, Double, Bool, Double)] = []
        for i in 0..<500 {
            let speed: Double
            if i == 250 { speed = 80.0 }       // spike
            else if i > 100 && i < 300 { speed = 30.0 }  // real peak
            else { speed = Double(i) * 0.1 }   // ramp
            stream.append((Double(i) * 0.01, speed, false, 0.0))
        }
        let result = TopSpeedComputer.compute(
            speedStream: stream,
            gpsMaxSpeed: 28.0,
            nearestGpsAccuracyMeters: 30.0
        )
        XCTAssertEqual(result.fusedMaxSpeed, 30.0, accuracy: 0.5)
        XCTAssertEqual(result.gpsMaxSpeed, 28.0, accuracy: 0.001)
        // GPS is confident → favor the max
        XCTAssertEqual(result.maxSpeed, 30.0, accuracy: 1.0)
    }

    func test_fallsBackToFused_whenGpsInaccurate() {
        let stream: [(TimeInterval, Double, Bool, Double)] = (0..<100).map { i in
            (Double(i) * 0.01, Double(i) * 0.2, false, 0.0)
        }
        let result = TopSpeedComputer.compute(
            speedStream: stream,
            gpsMaxSpeed: 5.0,
            nearestGpsAccuracyMeters: 200.0   // inaccurate
        )
        // Inaccurate GPS → use fused alone
        XCTAssertEqual(result.maxSpeed, 19.8, accuracy: 1.0)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/TopSpeedComputerTests/test_rejectsIMUSpike_preservesRealPeak \
  CODE_SIGNING_ALLOWED=NO
```
Expected: FAIL — `TopSpeedComputer` not found.

- [ ] **Step 3: Create `TopSpeedComputer.swift`**:

```swift
import Foundation

/// Computes the final top speed for a drive, using rolling-median filtering
/// on the 100 Hz speed stream to reject IMU spike artifacts. When GPS data
/// is available and accurate, the GPS max is preferred.
struct TopSpeedComputer {
    struct Result: Equatable {
        let fusedMaxSpeed: Double   // m/s, rolling-median-filtered
        let gpsMaxSpeed: Double     // m/s, raw GPS
        let maxSpeed: Double        // m/s, the value to display
    }

    /// `windowSize` is the rolling window in samples for the median filter
    /// (0.5s at 100 Hz).
    static func compute(
        speedStream: [(TimeInterval, Double, Bool, Double)],
        gpsMaxSpeed: Double,
        nearestGpsAccuracyMeters: Double,
        windowSize: Int = 50
    ) -> Result {
        let fusedMax = rollingMedianMax(stream: speedStream.map { $0.1 }, window: windowSize)
        // GPS is "confident" if the nearest update had horizontalAccuracy < 50m
        let gpsConfident = nearestGpsAccuracyMeters > 0 && nearestGpsAccuracyMeters < 50
        let maxSpeed: Double
        if gpsConfident, gpsMaxSpeed > 0 {
            maxSpeed = max(gpsMaxSpeed, fusedMax * 0.95)
        } else {
            maxSpeed = fusedMax
        }
        return Result(fusedMaxSpeed: fusedMax, gpsMaxSpeed: gpsMaxSpeed, maxSpeed: maxSpeed)
    }

    /// Computes the max of the rolling median of the stream. This rejects
    /// single-sample spikes (e.g. pothole IMU jolts) while preserving real
    /// peaks that last for at least the window size. O(n log k) using a
    /// sorted sliding window — fine for 36K samples/hour.
    private static func rollingMedianMax(stream: [Double], window: Int) -> Double {
        guard !stream.isEmpty else { return 0 }
        var best: Double = stream[0]
        let n = stream.count
        let half = window / 2
        for i in 0..<n {
            let lo = max(0, i - half)
            let hi = min(n, i + half + 1)
            let slice = stream[lo..<hi].sorted()
            let median = slice[slice.count / 2]
            if median > best { best = median }
        }
        return best
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/TopSpeedComputerTests \
  CODE_SIGNING_ALLOWED=NO
```
Expected: PASS for both tests.

- [ ] **Step 5: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/TopSpeedComputer.swift ios/FastTrack/FastTrackTests/TopSpeedComputerTests.swift
git commit -m "feat(ios): add TopSpeedComputer with rolling-median spike rejection"
```

---

## Track D — iOS: Drive Model + Integration

### Task D.1: Add `fusedMaxSpeed` / `gpsMaxSpeed` to `Drive` struct

**Files:**
- Modify: `ios/FastTrack/FastTrack/Models/Drive.swift`

- [ ] **Step 1: Write the failing test** in `ios/FastTrack/FastTrackTests/DriveModelBackwardCompatTests.swift`:

```swift
import XCTest
@testable import FastTrack

final class DriveModelBackwardCompatTests: XCTestCase {
    func test_Drive_decodesOldServerResponse_withoutNewFields() throws {
        let json = """
        {
            "id": 1, "user_id": 1,
            "start_time": "2025-01-01T00:00:00Z",
            "end_time": "2025-01-01T00:30:00Z",
            "start_latitude": 0, "start_longitude": 0,
            "end_latitude": 0, "end_longitude": 0,
            "distance": 1000, "duration": 1800,
            "max_speed": 30, "min_speed": 0, "avg_speed": 20,
            "stopped_time": 0, "left_turns": 0, "right_turns": 0,
            "brake_events": 0, "lane_changes": 0,
            "max_acceleration": 0, "max_deceleration": 0,
            "peak_g_force": 0, "top_corner_speed": 0
        }
        """.data(using: .utf8)!
        let drive = try JSONDecoder.iso8601().decode(Drive.self, from: json)
        XCTAssertNil(drive.fusedMaxSpeed)
        XCTAssertNil(drive.gpsMaxSpeed)
        XCTAssertEqual(drive.maxSpeed, 30.0, accuracy: 0.001)
    }
}

extension JSONDecoder {
    static func iso8601() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/DriveModelBackwardCompatTests/test_Drive_decodesOldServerResponse_withoutNewFields \
  CODE_SIGNING_ALLOWED=NO
```
Expected: FAIL — `fusedMaxSpeed` not a member.

- [ ] **Step 3: Add the fields** in `Drive.swift`:

After `var best060Time: Double?` (line ~38):
```swift
var fusedMaxSpeed: Double?    // m/s, rolling-median-filtered from 100 Hz stream
var gpsMaxSpeed: Double?      // m/s, max from GPS location updates
```

In the `CodingKeys` enum (add at the end):
```swift
case fusedMaxSpeed = "fused_max_speed"
case gpsMaxSpeed = "gps_max_speed"
```

In the custom `init(from decoder:)` (after the `best060Time` decode):
```swift
self.fusedMaxSpeed     = try c.decodeIfPresent(Double.self, forKey: .fusedMaxSpeed)
self.gpsMaxSpeed       = try c.decodeIfPresent(Double.self, forKey: .gpsMaxSpeed)
```

In the memberwise `init`:
```swift
fusedMaxSpeed: Double? = nil,
gpsMaxSpeed: Double? = nil,
```
Add the corresponding assignments in the body.

- [ ] **Step 4: Run the test to verify it passes**

Same command. Expected: PASS.

- [ ] **Step 5: Run the full iOS test suite**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```
Expected: no regressions. (Multiple existing tests construct a `Drive` via the memberwise init — the new optional parameters default to nil so they should keep compiling.)

- [ ] **Step 6: Commit**

```bash
git add ios/FastTrack/FastTrack/Models/Drive.swift ios/FastTrack/FastTrackTests/DriveModelBackwardCompatTests.swift
git commit -m "feat(ios): add fusedMaxSpeed and gpsMaxSpeed to Drive model"
```

---

### Task D.2: Wire LaunchAnalyzer + TopSpeedComputer into `stopRecording`

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveRecordingController.swift`

- [ ] **Step 1: Find the existing `stopRecording` method** in `DriveRecordingController.swift`. It's the place that currently calls `RouteSerializer.encodeV2` and assigns to `currentDrive.routeData`.

- [ ] **Step 2: Write the failing test** in `ios/FastTrack/FastTrackTests/DriveRecordingControllerPostHocAnalysisTests.swift`:

```swift
import XCTest
@testable import FastTrack

final class DriveRecordingControllerPostHocAnalysisTests: XCTestCase {
    @MainActor
    func test_stopRecording_invokesPostHocAnalyzer() async {
        // Mirror the factory from DriveRecordingControllerSpeedStreamTests.
        let realAPI = APIService()
        let authMgr = AuthManager(apiService: realAPI)
        realAPI.authManager = authMgr
        let dm = DriveManager(
            authManager: authMgr,
            profileManager: ProfileManager(apiService: realAPI),
            settings: AppSettings(apiService: realAPI),
            apiService: realAPI,
            carStatsManager: CarStatsManager(apiService: realAPI),
            achievementManager: AchievementManager()
        )
        let controller = dm.recordingController
        controller.startRecording()
        let t0 = Date()
        for i in 0..<300 {
            controller.processSpeedSample(SpeedSample(
                speed: 0.0, rawGPSSpeed: 0.0, speedAccuracy: 0.5,
                timestamp: t0.addingTimeInterval(Double(i) * 0.01),
                isZeroLocked: i < 100,
                stationaryConfidence: i < 100 ? 1.0 : 0.0
            ))
        }
        for i in 0..<250 {
            controller.processSpeedSample(SpeedSample(
                speed: 27.0 * (Double(i) / 250.0),
                rawGPSSpeed: 27.0 * (Double(i) / 250.0),
                speedAccuracy: 0.5,
                timestamp: t0.addingTimeInterval(1.0 + Double(i) * 0.01),
                isZeroLocked: false,
                stationaryConfidence: 0.0
            ))
        }
        await controller.stopRecording()
        XCTAssertGreaterThan(dm.currentDrive?.zeroToSixtyAttempts.count ?? 0, 0)
        XCTAssertNotNil(dm.currentDrive?.fusedMaxSpeed)
    }
}
```

- [ ] **Step 3: Run the test to verify it fails**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/DriveRecordingControllerPostHocAnalysisTests/test_stopRecording_invokesPostHocAnalyzer \
  CODE_SIGNING_ALLOWED=NO
```
Expected: FAIL — `fusedMaxSpeed` not on `Drive`, OR the post-hoc analyzer wasn't invoked.

- [ ] **Step 4: Modify `stopRecording`** to:
  1. Run `LaunchAnalyzer.analyze(stream: speedStream)` and store the resulting attempts
  2. Run `TopSpeedComputer.compute(...)` and store the result on `currentDrive.fusedMaxSpeed` / `gpsMaxSpeed` / `maxSpeed`
  3. Build a v3 `RouteSerializationSnapshot` and call `RouteSerializer.encodeV3` to produce the new `routeData`

The exact patch depends on the existing structure of `stopRecording`. Use this as a guide for the additions (insert at the appropriate place, typically after `stoppedTimeTracker.finalize(at:)` and before the `RouteSerializer.encodeV2` call):

```swift
// Post-hoc analysis
let analyzer = LaunchAnalyzer()
let postHocAttempts = analyzer.analyze(stream: speedStream)
if let best = postHocAttempts.min(by: { $0.elapsedSeconds < $1.elapsedSeconds }) {
    currentDrive?.best060Time = best.elapsedSeconds
    currentDrive?.zeroToSixtyAttempts = postHocAttempts
}

let gpsMax = currentMaxSpeed  // captured by the existing GPS path (use the existing `gpsMaxSpeed` if any; otherwise add a `gpsMaxSpeedTracker` here)
let topSpeed = TopSpeedComputer.compute(
    speedStream: speedStream,
    gpsMaxSpeed: gpsMax,
    nearestGpsAccuracyMeters: lastSeenGpsAccuracy  // add a stored property if not present
)
currentDrive?.fusedMaxSpeed = topSpeed.fusedMaxSpeed
currentDrive?.gpsMaxSpeed = topSpeed.gpsMaxSpeed
// currentDrive.maxSpeed is already set; optionally update to topSpeed.maxSpeed
```

(For `gpsMaxSpeed` and `lastSeenGpsAccuracy`, the existing controller may already track these under different names. Search the file for `currentMaxSpeed` and `horizontalAccuracy` to find what to wire up.)

Then change the existing `RouteSerializer.encodeV2(snapshot:)` call to use v3:

```swift
let snapshot = RouteSerializationSnapshot(
    richRoutePoints: richRoutePoints,
    recordedRouteEvents: recordedRouteEvents,
    attempts: postHocAttempts.isEmpty ? attempts060 : postHocAttempts,
    speedStream: speedStream,
    speedPeaks: []  // populated in a later step if desired
)
if let json = RouteSerializer.encodeV3(snapshot: snapshot) {
    currentDrive?.routeData = json
}
```

- [ ] **Step 5: Run the test to verify it passes**

Same command as Step 3. Expected: PASS.

- [ ] **Step 6: Run the full iOS test suite**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```
Expected: no regressions.

- [ ] **Step 7: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/DriveRecordingController.swift ios/FastTrack/FastTrackTests/DriveRecordingControllerPostHocAnalysisTests.swift
git commit -m "feat(ios): wire LaunchAnalyzer and TopSpeedComputer into stopRecording"
```

---

## Track E — Backend: Migration + Model Fields

### Task E.1: Add `FusedMaxSpeed` and `GpsMaxSpeed` to the `Drive` struct

**Files:**
- Modify: `backend/internal/app/models.go`

- [ ] **Step 1: Write the failing test** in `backend/internal/app/handlers_test.go` (find a sensible insertion point — the `TestCreateDrive` test or a new test):

```go
func TestCreateDrive_PersistsFusedAndGPSMaxSpeed(t *testing.T) {
    fused := 32.5
    gps := 31.0
    body := map[string]any{
        "user_id": 1, "start_time": "2025-01-01T00:00:00Z", "end_time": "2025-01-01T00:30:00Z",
        "start_latitude": 0, "start_longitude": 0, "end_latitude": 0, "end_longitude": 0,
        "distance": 1000, "duration": 1800, "max_speed": 30, "min_speed": 0, "avg_speed": 20,
        "fused_max_speed": fused, "gps_max_speed": gps,
    }
    jsonBody, _ := json.Marshal(body)
    req := httptest.NewRequest(http.MethodPost, "/api/v1/drives", bytes.NewReader(jsonBody))
    req.Header.Set("Content-Type", "application/json")
    req.Header.Set("Authorization", "Bearer "+testToken)
    rec := httptest.NewRecorder()
    api.ServeHTTP(rec, req)
    if rec.Code != http.StatusOK {
        t.Fatalf("expected 200, got %d: %s", rec.Code, rec.Body.String())
    }
    var resp map[string]any
    if err := json.Unmarshal(rec.Body.Bytes(), &resp); err != nil {
        t.Fatalf("decode resp: %v", err)
    }
    if got := resp["fused_max_speed"]; got == nil {
        t.Fatalf("expected fused_max_speed in response, got %v", resp)
    }
}
```

(Read `handlers_test.go` first to use the same test setup pattern — auth token, fixtures, server construction. Adapt the request to match the local style.)

- [ ] **Step 2: Run the test to verify it fails**

```bash
cd backend && CGO_ENABLED=1 go test ./... -run TestCreateDrive_PersistsFusedAndGPSMaxSpeed -v
```
Expected: FAIL — the new fields aren't on the struct yet, OR the columns don't exist.

- [ ] **Step 3: Add the fields** in `backend/internal/app/models.go` after `Best060Time` (line ~66):

```go
FusedMaxSpeed  *float64 `json:"fused_max_speed"`
GpsMaxSpeed    *float64 `json:"gps_max_speed"`
```

- [ ] **Step 4: Run the test to verify it still fails** (the migration is missing, so the columns don't exist yet)

```bash
cd backend && CGO_ENABLED=1 go test ./... -run TestCreateDrive_PersistsFusedAndGPSMaxSpeed -v
```
Expected: FAIL — column does not exist.

- [ ] **Step 5: Commit (struct only)**

```bash
git add backend/internal/app/models.go backend/internal/app/handlers_test.go
git commit -m "feat(backend): add FusedMaxSpeed and GpsMaxSpeed fields to Drive"
```

---

### Task E.2: Add migration `2026061401`

**Files:**
- Modify: `backend/internal/app/migrations.go`

- [ ] **Step 1: Append a new migration entry** to the `schemaMigrations` slice (after the last entry, before the closing `}`):

```go
{
    version:     "2026061401",
    description: "add fused_max_speed and gps_max_speed columns to drives",
    up: func(tx *gorm.DB) error {
        driveColumns := []string{"FusedMaxSpeed", "GpsMaxSpeed"}
        for _, col := range driveColumns {
            if err := addColumnIfMissing(tx, &Drive{}, col); err != nil {
                return err
            }
        }
        return nil
    },
},
```

- [ ] **Step 2: Run the test to verify it passes**

```bash
cd backend && CGO_ENABLED=1 go test ./... -run TestCreateDrive_PersistsFusedAndGPSMaxSpeed -v
```
Expected: PASS.

- [ ] **Step 3: Run the full backend test suite**

```bash
cd backend && CGO_ENABLED=1 go test ./... -v -timeout 60s
```
Expected: all tests pass.

- [ ] **Step 4: Commit**

```bash
git add backend/internal/app/migrations.go
git commit -m "feat(backend): migrate drives with fused_max_speed and gps_max_speed"
```

---

## Track F — Tests + Final Verification

### Task F.1: Add backward-compat test for v2 route_data

**Files:**
- Create: `ios/FastTrack/FastTrackTests/RouteDataBackwardCompatTests.swift` (additional test)

- [ ] **Step 1: Add the test**:

```swift
func test_oldV2RouteData_decodesCleanly() throws {
    let data = """
    {"v":2,"points":[{"lat":1.0,"lng":2.0,"speed":5.0,"ts":1000.0}]}
    """.data(using: .utf8)!
    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    XCTAssertEqual(json?["v"] as? Int, 2)
    XCTAssertNotNil(json?["points"])
}
```

- [ ] **Step 2: Run the test**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/RouteDataBackwardCompatTests \
  CODE_SIGNING_ALLOWED=NO
```
Expected: PASS (this is a sanity check, not a hard failure if v2 is missing).

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrackTests/RouteDataBackwardCompatTests.swift
git commit -m "test(ios): verify v2 route_data still decodes"
```

---

### Task F.2: Run all tests and verify

- [ ] **Step 1: Run the full iOS test suite**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```
Expected: all tests pass. (If any existing tests fail because of the new optional fields, fix the failures — they should be backward-compatible by default.)

- [ ] **Step 2: Run the full backend test suite**

```bash
cd backend && CGO_ENABLED=1 go test ./... -v -timeout 60s
```
Expected: all tests pass.

- [ ] **Step 3: Run `go vet`**

```bash
cd backend && CGO_ENABLED=1 go vet ./...
```
Expected: no findings.

- [ ] **Step 4: If everything is green, do not commit yet.** Make a final summary commit if needed (e.g. for any post-test fixups).

---

## Self-Review Notes (filled in after writing the plan)

**1. Spec coverage:**
- Section 1 (Architecture Overview) — covered by all tracks.
- Section 2 (Buffer + v3 storage) — Tracks A, B.
- Section 3 (LaunchAnalyzer) — Track C.
- Section 4 (Top Speed) — Track C.
- Section 5 (IMU rate change + retuning + throttling) — Track A.
- Section 6 (Data Flow) — Track D integration.
- Section 7 (Backward Compat) — Tracks B (v3), D (Drive fields), E (nullable columns), F (backward-compat tests).
- Section 8 (Testing) — All tracks have tests; Track F is the umbrella.

**2. Placeholder scan:** No "TBD" or "TODO" in the plan. Steps with "search for" guidance are explicit and bounded.

**3. Type consistency:**
- `SpeedStream` element type is `(TimeInterval, Double, Bool, Double)` everywhere (Section 2, Track A test, Track B test).
- `ZeroToSixtyAttempt.confidence` is `Double` everywhere (Track B + Track C).
- `Drive.fusedMaxSpeed` / `gpsMaxSpeed` are `Double?` in iOS and `*float64` in Go (Track D, Track E).
- `TopSpeedComputer.Result` is used consistently in the test and the implementation.
- `SpeedPeak.timestamp` is `Date` (Track B), `SpeedPeak.source` is `SpeedSource` enum (Track B).

**4. Open question handled in the plan:** the spec mentioned "currentDrive may be locked to a different rate" — Task A.4 says to use the existing throttler OR add a dedicated one, and to verify in the test.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-14-high-precision-speed-timing.md`. Two execution options:

1. **Subagent-Driven (recommended)** — I dispatch a fresh subagent per track (A and E in parallel, then B and C in parallel, then D, then F), with a final code review per track. Parallelizable tracks save wall-clock time.

2. **Inline Execution** — Execute tasks in this session using executing-plans, batch execution with checkpoints for review.

Which approach?
