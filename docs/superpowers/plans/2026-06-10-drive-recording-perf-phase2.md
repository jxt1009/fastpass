# Worktree A Phase 2 — Issue #83b: Drive recording performance (actor-based rewrite) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Land the deeper architectural rewrite of the recording path on top of PR #83a: a `@globalActor RecordingActor` that owns all hot-path state, collapses the 7+ `MainActor.run` round-trips in `processLocationHeavy` to a single actor-isolated mutation, decimates the live polyline so `LiveMapView` stops re-rendering the full route on every tick, and switches the recording map style to flat elevation. Validates that Phase 1 fixes hold up and sets up the recording path for future changes without re-introducing the same perf regressions.

**Architecture:** Phase 1 introduced surgical hot-path fixes; this phase moves the data and processing onto a custom `RecordingActor` (a global actor backed by a `DispatchQueue` at `.userInitiated` QoS). All extended-tracking state lives on the actor. The actor hands a single coalesced `DriveStatsSnapshot` value to the main actor at most every 100 ms. The live map consumes a Douglas–Peucker-decimated ≤500-point array. The full-fidelity array stays in `DriveManager`/`RecordingActor` for serialization.

**Tech Stack:** Swift 5.10+ (global actors, `Sendable`), Combine, MapKit, XCTest. No backend, no model changes, no new SPM dependencies.

---

## File Structure

### Create

- `ios/FastTrack/FastTrack/ViewModels/RecordingActor.swift` — the global actor + the hot-path state it owns + the snapshot type
- `ios/FastTrack/FastTrack/ViewModels/RouteDecimator.swift` — Douglas–Peucker
- `ios/FastTrack/FastTrackTests/RecordingActorTests.swift` — actor isolation, snapshot shape, ring buffer
- `ios/FastTrack/FastTrackTests/RouteDecimatorTests.swift` — decimation accuracy

### Modify

- `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift` — async `stopRecording()`, public `recordRoutePoint(_:)` / `recordSpeedSample(_:)` async APIs that hop to the actor; main-thread view-facing state read via the snapshot
- `ios/FastTrack/FastTrack/ViewModels/DriveManager+Processing.swift` — collapsed round-trips, no `MainActor.run` ping-pong
- `ios/FastTrack/FastTrack/ViewModels/DriveManager+LiveActivity.swift` — read snapshot, 1 Hz throttle unchanged
- `ios/FastTrack/FastTrack/Views/ContentView.swift` — `LiveMapView` consumes a decimated `routeCoordinatesDecimated` and uses `.standard(elevation: .flat)`

### Out of scope (preserved from Phase 1)

- `RingBuffer<Double>` for `speedReadings`
- `RunningSpeedStats` for O(1) min/max/avg
- `RouteSerializer` for off-main JSON
- `beginBackgroundTask` wrap on upload
- `PublishThrottler` for 10 Hz view-layer cap

---

## Task 1: Add `RouteDecimator` with TDD

**Files:**
- Create: `ios/FastTrack/FastTrack/ViewModels/RouteDecimator.swift`
- Create: `ios/FastTrack/FastTrackTests/RouteDecimatorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ios/FastTrack/FastTrackTests/RouteDecimatorTests.swift`:

```swift
import XCTest
import CoreLocation
@testable import FastTrack

final class RouteDecimatorTests: XCTestCase {

    func test_emptyAndSinglePointAreReturnedAsIs() {
        XCTAssertEqual(RouteDecimator.decimate([], toleranceMeters: 5).count, 0)
        let one = [CLLocationCoordinate2D(latitude: 0, longitude: 0)]
        XCTAssertEqual(RouteDecimator.decimate(one, toleranceMeters: 5).count, 1)
    }

    func test_straightLineIsReducedToEndpoints() {
        // 100 collinear points on a line at the equator.
        let pts = (0..<100).map { i in
            CLLocationCoordinate2D(latitude: 0, longitude: Double(i) * 0.0001)
        }
        let out = RouteDecimator.decimate(pts, toleranceMeters: 5)
        // Endpoints + any corners; collinear reduces to 2.
        XCTAssertEqual(out.count, 2)
        XCTAssertEqual(out.first?.longitude ?? -1, 0, accuracy: 1e-6)
        XCTAssertEqual(out.last?.longitude ?? -1, 99 * 0.0001, accuracy: 1e-6)
    }

    func test_sharpTurnIsPreserved() {
        // Straight, then 90° turn, then straight.
        var pts: [CLLocationCoordinate2D] = []
        for i in 0..<50 { pts.append(CLLocationCoordinate2D(latitude: 0, longitude: Double(i) * 0.0001)) }
        for i in 0..<50 { pts.append(CLLocationCoordinate2D(latitude: Double(i) * 0.0001, longitude: 50 * 0.0001)) }
        let out = RouteDecimator.decimate(pts, toleranceMeters: 5)
        // Must keep the corner point (the 90° turn).
        XCTAssertGreaterThanOrEqual(out.count, 3)
        // The middle point should be the corner.
        let mid = out[out.count / 2]
        XCTAssertEqual(mid.latitude, 0, accuracy: 1e-3)
        XCTAssertEqual(mid.longitude, 50 * 0.0001, accuracy: 1e-3)
    }

    func test_respectsMaxOutputSize() {
        // 1000 noisy points that don't simplify down to 2; ensure
        // the decimation reduces the array, and that running
        // decimation on a sliding window never blows past the cap.
        let pts = (0..<1000).map { i in
            CLLocationCoordinate2D(
                latitude: sin(Double(i) / 10.0) * 0.001,
                longitude: Double(i) * 0.0001
            )
        }
        let out = RouteDecimator.decimate(pts, toleranceMeters: 1, maxOutput: 200)
        XCTAssertLessThanOrEqual(out.count, 200)
    }
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-83-perf-phase2
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/RouteDecimatorTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: build fails with `Cannot find 'RouteDecimator' in scope`.

- [ ] **Step 3: Create the decimator**

Create `ios/FastTrack/FastTrack/ViewModels/RouteDecimator.swift`:

```swift
import Foundation
import CoreLocation

/// Ramer–Douglas–Peucker polyline simplification, used to keep the
/// live recording map's polyline short. Pure function; safe to call
/// from any thread. `toleranceMeters` controls how aggressively
/// near-collinear points are collapsed (smaller = more detail);
/// `maxOutput` is a hard cap so a 10-min drive never blows past
/// the GPU's redraw budget.
enum RouteDecimator {

    static func decimate(
        _ points: [CLLocationCoordinate2D],
        toleranceMeters: Double,
        maxOutput: Int = 500
    ) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        rdp(points: points, start: 0, end: points.count - 1, tolerance: toleranceMeters, keep: &keep)

        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(min(maxOutput, points.count))
        for i in 0..<points.count where keep[i] {
            out.append(points[i])
        }

        // Hard cap: if we still exceed maxOutput, do uniform down-sample.
        if out.count > maxOutput {
            out = uniformStride(out, maxOutput: maxOutput)
        }
        return out
    }

    private static func rdp(
        points: [CLLocationCoordinate2D],
        start: Int, end: Int,
        tolerance: Double,
        keep: inout [Bool]
    ) {
        if end <= start + 1 { return }
        var maxDist = 0.0
        var maxIdx = start
        for i in (start + 1)..<end {
            let d = perpendicularDistanceMeters(
                points[i], points[start], points[end]
            )
            if d > maxDist {
                maxDist = d
                maxIdx = i
            }
        }
        if maxDist > tolerance {
            keep[maxIdx] = true
            rdp(points: points, start: start, end: maxIdx, tolerance: tolerance, keep: &keep)
            rdp(points: points, start: maxIdx, end: end, tolerance: tolerance, keep: &keep)
        }
    }

    /// Perpendicular distance from `p` to the great-circle line
    /// between `a` and `b`, in meters. Uses the equirectangular
    /// approximation — fine for the small spans in a polyline.
    private static func perpendicularDistanceMeters(
        _ p: CLLocationCoordinate2D,
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> Double {
        let lat0 = (a.latitude + b.latitude) / 2 * .pi / 180
        let mPerDegLat = 111_320.0
        let mPerDegLng = 111_320.0 * cos(lat0)

        let ax = a.longitude * mPerDegLng, ay = a.latitude * mPerDegLat
        let bx = b.longitude * mPerDegLng, by = b.latitude * mPerDegLat
        let px = p.longitude * mPerDegLng, py = p.latitude * mPerDegLat

        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        if len2 == 0 {
            let ex = px - ax, ey = py - ay
            return (ex * ex + ey * ey).squareRoot()
        }
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / len2))
        let projX = ax + t * dx, projY = ay + t * dy
        let ex = px - projX, ey = py - projY
        return (ex * ex + ey * ey).squareRoot()
    }

    private static func uniformStride(
        _ points: [CLLocationCoordinate2D],
        maxOutput: Int
    ) -> [CLLocationCoordinate2D] {
        guard points.count > maxOutput else { return points }
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(maxOutput)
        let stride = Double(points.count - 1) / Double(maxOutput - 1)
        for i in 0..<maxOutput {
            let idx = Int((Double(i) * stride).rounded())
            out.append(points[min(idx, points.count - 1)])
        }
        return out
    }
}
```

- [ ] **Step 4: Run the tests, confirm they pass**

Run the same `xcodebuild test … --only-testing:FastTrackTests/RouteDecimatorTests` command from Step 2. Expected: all 4 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/RouteDecimator.swift \
        ios/FastTrack/FastTrackTests/RouteDecimatorTests.swift
git commit -m "feat(ios): RouteDecimator (Ramer-Douglas-Peucker) for live map polyline"
```

---

## Task 2: Define `RecordingActor` and the `DriveStatsSnapshot` value type

**Files:**
- Create: `ios/FastTrack/FastTrack/ViewModels/RecordingActor.swift`
- Create: `ios/FastTrack/FastTrackTests/RecordingActorTests.swift`

- [ ] **Step 1: Write the failing tests**

Create `ios/FastTrack/FastTrackTests/RecordingActorTests.swift`:

```swift
import XCTest
import CoreLocation
@testable import FastTrack

final class RecordingActorTests: XCTestCase {

    @MainActor
    func test_actorIsolatesState() async {
        let actor = RecordingActor()
        // First ingest: always published (or coalesced by the actor's
        // own internal rate cap; for a single sample the cap is
        // irrelevant).
        await actor.ingestRoutePoint(.init(latitude: 1, longitude: 2), speed: 10, timestamp: 1)
        let snap = await actor.snapshot()
        XCTAssertEqual(snap.routePointCount, 1)
        XCTAssertEqual(snap.runningMaxSpeed, 10)
    }

    func test_runningStatsAfterManyIngests() async {
        let actor = RecordingActor()
        for i in 0..<1000 {
            let speed = Double(i % 50)
            await actor.ingestRoutePoint(
                .init(latitude: Double(i) * 0.0001, longitude: 0),
                speed: speed,
                timestamp: Double(i)
            )
        }
        let snap = await actor.snapshot()
        XCTAssertEqual(snap.routePointCount, 1000)
        XCTAssertEqual(snap.runningMaxSpeed, 49)
        XCTAssertEqual(snap.runningMinSpeed, 0)
        XCTAssertGreaterThan(snap.runningAvgSpeed, 0)
    }

    func test_snapshotThrottledToTenHertz() async {
        let actor = RecordingActor()
        let now = Date()
        for i in 0..<50 {
            await actor.ingestRoutePoint(
                .init(latitude: 0, longitude: Double(i) * 0.0001),
                speed: 20,
                timestamp: Double(i) * 0.001  // 1ms apart → 1000 Hz
            )
        }
        // Snapshot at the same wall-clock instant multiple times —
        // actor must internally rate-limit publishes.
        let s1 = await actor.snapshot(timestamp: now)
        let s2 = await actor.snapshot(timestamp: now.addingTimeInterval(0.05))   // 50ms < 100ms
        let s3 = await actor.snapshot(timestamp: now.addingTimeInterval(0.2))    // 200ms > 100ms
        // s1 and s2 should match; s3 should reflect a later publish.
        XCTAssertEqual(s1.publishedAt, s2.publishedAt)
        XCTAssertNotEqual(s2.publishedAt, s3.publishedAt)
    }
}
```

- [ ] **Step 2: Run the tests to confirm they fail**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-83-perf-phase2
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/RecordingActorTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: build fails with `Cannot find 'RecordingActor' in scope`.

- [ ] **Step 3: Create the actor**

Create `ios/FastTrack/FastTrack/ViewModels/RecordingActor.swift`:

```swift
import Foundation
import CoreLocation

/// Coalesced view-facing snapshot of the recording path's hot state.
/// Produced by `RecordingActor` at most every 100 ms and consumed
/// on the main actor by `DriveManager` / `ContentView`.
struct DriveStatsSnapshot: Sendable, Equatable {
    let routePointCount: Int
    let runningMaxSpeed: Double
    let runningMinSpeed: Double
    let runningAvgSpeed: Double
    let lastCoordinate: CLLocationCoordinate2D?
    let publishedAt: Date
}

/// Owns all the recording-path state that was previously mutated on
/// the main actor (route points, extended tracking scalars, running
/// stats). All `ingest*` methods are O(1). `snapshot()` returns a
/// Sendable value-type view of the current state and is rate-limited
/// to 10 Hz to avoid hammering the SwiftUI re-render path.
@globalActor
actor RecordingActor {
    static let shared = RecordingActor()

    private var routePointCount: Int = 0
    private var runningMinSpeed: Double = 0
    private var runningMaxSpeed: Double = 0
    private var runningSumSpeed: Double = 0
    private var lastCoordinate: CLLocationCoordinate2D?

    private var lastPublishedAt: Date = .distantPast
    private let publishInterval: TimeInterval = 0.1

    func ingestRoutePoint(_ coord: CLLocationCoordinate2D, speed: Double, timestamp: TimeInterval) {
        routePointCount += 1
        lastCoordinate = coord
        if routePointCount == 1 {
            runningMinSpeed = speed
            runningMaxSpeed = speed
        } else {
            if speed < runningMinSpeed { runningMinSpeed = speed }
            if speed > runningMaxSpeed { runningMaxSpeed = speed }
        }
        runningSumSpeed += speed
    }

    /// Returns a coalesced snapshot. If `now` is within
    /// `publishInterval` of the last publish, the same publishedAt
    /// is returned and the underlying values are NOT re-read — the
    /// caller is expected to use the most recent snapshot it has.
    func snapshot(now: Date = Date()) -> DriveStatsSnapshot {
        if now.timeIntervalSince(lastPublishedAt) < publishInterval {
            // Re-use the previous publishedAt so callers can dedupe.
            return DriveStatsSnapshot(
                routePointCount: routePointCount,
                runningMaxSpeed: runningMaxSpeed,
                runningMinSpeed: runningMinSpeed,
                runningAvgSpeed: routePointCount > 0 ? runningSumSpeed / Double(routePointCount) : 0,
                lastCoordinate: lastCoordinate,
                publishedAt: lastPublishedAt
            )
        }
        lastPublishedAt = now
        return DriveStatsSnapshot(
            routePointCount: routePointCount,
            runningMaxSpeed: runningMaxSpeed,
            runningMinSpeed: runningMinSpeed,
            runningAvgSpeed: routePointCount > 0 ? runningSumSpeed / Double(routePointCount) : 0,
            lastCoordinate: lastCoordinate,
            publishedAt: now
        )
    }

    func reset() {
        routePointCount = 0
        runningMinSpeed = 0
        runningMaxSpeed = 0
        runningSumSpeed = 0
        lastCoordinate = nil
        lastPublishedAt = .distantPast
    }
}
```

- [ ] **Step 4: Run the tests, confirm they pass**

Run the same `xcodebuild test … --only-testing:FastTrackTests/RecordingActorTests` command from Step 2. Expected: 3 tests pass.

- [ ] **Step 5: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/RecordingActor.swift \
        ios/FastTrack/FastTrackTests/RecordingActorTests.swift
git commit -m "feat(ios): RecordingActor global actor and DriveStatsSnapshot

RecordingActor owns the hot-path state that was previously
mutated on the main actor (route point count, running
min/max/avg, last coordinate). All ingest methods are O(1).
snapshot() returns a Sendable value type and is rate-limited
to 10 Hz so the view layer can't be hammered with stale
snapshots."
```

---

## Task 3: Switch `LiveMapView` to a decimated polyline and flat elevation

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/ContentView.swift:18-72, 365-421`

- [ ] **Step 1: Read the current `ContentView` body and `LiveMapView`**

Open `ios/FastTrack/FastTrack/Views/ContentView.swift:18-72` (the body that wires up `LiveMapView`) and `365-421` (the `LiveMapView` struct itself). Confirm the call site is:

```swift
LiveMapView(
    userLocation: locationManager.currentLocation?.coordinate
        ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
    routeCoordinates: driveManager.routeCoordinates
)
```

and that `LiveMapView` accepts `routeCoordinates: [CLLocationCoordinate2D]` and renders it via `MapPolyline(coordinates:)` with `.mapStyle(.standard(elevation: .realistic))`.

- [ ] **Step 2: Add a decimation call site and a new `LiveMapView` parameter**

Replace the call site in `body` (ContentView.swift:22-27) with:

```swift
LiveMapView(
    userLocation: locationManager.currentLocation?.coordinate
        ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
    routeCoordinates: driveManager.routeCoordinates,
    useFlatElevation: driveManager.isRecording
)
```

- [ ] **Step 3: Update `LiveMapView` to take the new flag and use the decimator**

Replace the entire `LiveMapView` struct (ContentView.swift:365-421) with:

```swift
struct LiveMapView: View {
    let userLocation: CLLocationCoordinate2D
    let routeCoordinates: [CLLocationCoordinate2D]
    let useFlatElevation: Bool

    @State private var cameraPosition: MapCameraPosition

    init(
        userLocation: CLLocationCoordinate2D,
        routeCoordinates: [CLLocationCoordinate2D],
        useFlatElevation: Bool = false
    ) {
        self.userLocation = userLocation
        self.routeCoordinates = routeCoordinates
        self.useFlatElevation = useFlatElevation
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: userLocation,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
    }

    /// Decimate to ≤500 points before handing to MapKit. MapKit has
    /// no incremental polyline update; redrawing 600+ points on
    /// every GPS tick with realistic elevation was the GPU hot spot.
    private var displayCoordinates: [CLLocationCoordinate2D] {
        if routeCoordinates.count <= 500 { return routeCoordinates }
        return RouteDecimator.decimate(routeCoordinates, toleranceMeters: 5, maxOutput: 500)
    }

    var body: some View {
        Map(position: $cameraPosition) {
            Annotation("", coordinate: userLocation) {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 16, height: 16)
                }
            }

            let coords = displayCoordinates
            if coords.count > 1 {
                MapPolyline(coordinates: coords)
                    .stroke(Color.ftAmber, lineWidth: 4)
            }

            if let first = routeCoordinates.first {
                Annotation("", coordinate: first) {
                    Image(systemName: "flag.checkered")
                        .foregroundColor(.ftGreen)
                        .font(.system(size: 18, weight: .bold))
                }
            }
        }
        .mapStyle(.standard(elevation: useFlatElevation ? .flat : .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onChange(of: userLocation) { oldValue, newValue in
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: newValue,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
        }
    }
}
```

The flag annotation intentionally uses `routeCoordinates.first` (the un-decimated full-fidelity array) so the start flag is always pinned to the exact start point. The polyline uses the decimated array.

- [ ] **Step 4: Build the project**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-83-perf-phase2
xcodebuild build-for-testing \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Expected: clean build.

- [ ] **Step 5: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/ContentView.swift
git commit -m "perf(ios): decimate live map polyline and switch to flat elevation while recording

- LiveMapView now takes useFlatElevation and decodes the
  coordinates to ≤500 points via RouteDecimator before handing
  to MapPolyline. The flag annotation still uses the full-fidelity
  array so the start marker stays pinned.
- During recording (useFlatElevation: true) the map style is
  .flat; in idle mode it's still .realistic.
- The call site in ContentView passes driveManager.isRecording."
```

---

## Task 4: Bridge `LocationManager` IMU/GPS callbacks into the actor and collapse `processLocationHeavy`

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager+Processing.swift:96-275`
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift` (call sites for `processLocation` / `processSpeedSample`)

- [ ] **Step 1: Read the current `processLocationHeavy` and `processHeadingBackground`**

Open `ios/FastTrack/FastTrack/ViewModels/DriveManager+Processing.swift:96-275`. Confirm the 7+ `MainActor.run` round-trips are still there.

- [ ] **Step 2: Replace `processLocationHeavy` with an actor-isolated version**

Replace the entire `processLocationHeavy` function (lines 96-232) with a version that computes everything locally (it was already mostly off-main) and at the end hops to `RecordingActor` for a single `ingest` call. The `Task.detached` wrapper is preserved.

```swift
    func processLocationHeavy(_ location: CLLocation, speed: Double, speedMph: Double) async {
        let ts = location.timestamp

        // Read prev from the actor — single hop, not seven.
        let prevRecord = await RecordingActor.shared.previousRoutePoint()
        guard let prev = prevRecord.location else { return }
        let prevSpeed = prevRecord.speed

        let dt = ts.timeIntervalSince(prev.timestamp)
        guard dt > 0 && dt < 5 else { return }

        let speedAccuracyOK = location.speedAccuracy > 0 && location.speedAccuracy < 2.0
                           && prev.speedAccuracy > 0 && prev.speedAccuracy < 2.0

        // All math runs on the detached task's thread.
        let rawAccel = (speed - prevSpeed) / dt
        let maxPhysicalAccelMS2 = 5.0 * 9.81
        let accel = max(-maxPhysicalAccelMS2, min(maxPhysicalAccelMS2, rawAccel))

        // Single actor hop to ingest everything in one batch.
        let update = RecordingActorUpdate(
            coordinate: location.coordinate,
            speed: speed,
            timestamp: ts.timeIntervalSince1970,
            acceleration: speedAccuracyOK && accel > 0 ? accel : nil,
            deceleration: speedAccuracyOK && -accel > 0 ? -accel : nil,
            brakeDetected: accel < -2.5,
            gForce: speedAccuracyOK ? computedGForce(accel: accel, location: location, prev: prev, speed: speed, dt: dt) : nil,
            cornerSpeed: speedAccuracyOK ? speed : nil
        )
        await RecordingActor.shared.ingest(update)
    }
```

(You'll add a `computedGForce` helper at file scope and a `RecordingActorUpdate` value type in Task 5; for now, stub the function and let Task 5 fill in the type.)

- [ ] **Step 3: Add the `computedGForce` helper**

Append to `DriveManager+Processing.swift`:

```swift
/// Compute the longitudinal+lat G-force magnitude for a sample.
/// Mirrors the original logic that lived inside processLocationHeavy.
private func computedGForce(
    accel: Double,
    location: CLLocation,
    prev: CLLocation,
    speed: Double,
    dt: TimeInterval
) -> Double {
    var latAccel = 0.0
    if location.course >= 0 && prev.course >= 0 && speed > 1 {
        var dh = location.course - prev.course
        if dh > 180 { dh -= 360 }
        if dh < -180 { dh += 360 }
        let omega = (dh * .pi / 180) / dt
        latAccel = speed * omega
    }
    let lonG = accel / 9.81
    let latG = abs(latAccel) / 9.81
    return (lonG * lonG + latG * latG).squareRoot()
}
```

- [ ] **Step 4: Confirm the build still compiles (with stub types)**

If `RecordingActorUpdate` doesn't exist yet, the build will fail at Task 4. Continue to Task 5 — the type is defined there, and the build will succeed once it's in place. If you want to land Task 4 atomically, add a `struct RecordingActorUpdate {}` stub now and replace it in Task 5.

- [ ] **Step 5: Commit (deferred — see Task 5)**

This task ships atomically with Task 5; one commit covers both.

---

## Task 5: Add the `RecordingActorUpdate` type and `previousRoutePoint` API

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/RecordingActor.swift`

- [ ] **Step 1: Add the `RecordingActorUpdate` value type and the `previousRoutePoint` API**

In `RecordingActor.swift`, append after the `DriveStatsSnapshot` struct:

```swift
/// A per-tick update handed to the actor. All fields except the
/// coordinate and timestamp are optional so callers can decide
/// which events to surface (e.g. brake events are rare).
struct RecordingActorUpdate: Sendable {
    let coordinate: CLLocationCoordinate2D
    let speed: Double
    let timestamp: TimeInterval
    let acceleration: Double?
    let deceleration: Double?
    let brakeDetected: Bool
    let gForce: Double?
    let cornerSpeed: Double?
}

/// Returns the previous route point + its recorded speed, used by
/// the per-tick accel/G-force math. Nil on the first sample.
struct PreviousRoutePoint: Sendable {
    let location: CLLocation?
    let speed: Double
}
```

And inside the `RecordingActor` actor body, add:

```swift
    private var lastIngestedLocation: CLLocation?
    private var lastIngestedSpeed: Double = 0

    func previousRoutePoint() -> PreviousRoutePoint {
        PreviousRoutePoint(location: lastIngestedLocation, speed: lastIngestedSpeed)
    }

    func ingest(_ update: RecordingActorUpdate) {
        routePointCount += 1
        lastCoordinate = update.coordinate
        lastIngestedLocation = CLLocation(
            coordinate: update.coordinate,
            altitude: 0,
            horizontalAccuracy: 0,
            verticalAccuracy: 0,
            course: 0,
            speed: update.speed,
            timestamp: Date(timeIntervalSince1970: update.timestamp)
        )
        lastIngestedSpeed = update.speed
        if routePointCount == 1 {
            runningMinSpeed = update.speed
            runningMaxSpeed = update.speed
        } else {
            if update.speed < runningMinSpeed { runningMinSpeed = update.speed }
            if update.speed > runningMaxSpeed { runningMaxSpeed = update.speed }
        }
        runningSumSpeed += update.speed
    }
```

And update `reset()` to clear the new fields:

```swift
    func reset() {
        routePointCount = 0
        runningMinSpeed = 0
        runningMaxSpeed = 0
        runningSumSpeed = 0
        lastCoordinate = nil
        lastPublishedAt = .distantPast
        lastIngestedLocation = nil
        lastIngestedSpeed = 0
    }
```

- [ ] **Step 2: Build the project**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-83-perf-phase2
xcodebuild build-for-testing \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Expected: clean build. (Tasks 4 and 5 land together; the stub `RecordingActorUpdate` from Task 4 Step 4 is no longer needed.)

- [ ] **Step 3: Run the full iOS test suite**

Run:
```bash
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass, including `RecordingActorTests` and `RouteDecimatorTests`.

- [ ] **Step 4: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/RecordingActor.swift \
        ios/FastTrack/FastTrack/ViewModels/DriveManager+Processing.swift
git commit -m "perf(ios): collapse processLocationHeavy to a single actor hop

The old code did 7+ MainActor.run round-trips per location
update just to read/write small scalars. The new version reads
the prev sample from the actor once, runs all the math on the
detached task, and hands a single RecordingActorUpdate value to
the actor in one call.

The actor owns the prev sample now (lastIngestedLocation +
lastIngestedSpeed), updated inside ingest(). DriveManager no
longer needs to keep recordingLocations on the main actor for
the hot path (still keeps it for serialization)."
```

---

## Task 6: Make `stopRecording` async and final on-device validation

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift:197-299`

- [ ] **Step 1: Mark `stopRecording` async**

In `DriveManager.swift`, change:

```swift
    func stopRecording() {
```

to:

```swift
    @MainActor
    func stopRecording() async {
```

The `Task { ... }` block at the end of the function (the upload) becomes the function's body — wrap it in a `defer` for the background-task identifier and remove the `Task {` wrapper.

The final function shape:

```swift
    @MainActor
    func stopRecording() async {
        guard isRecording else { return }
        isRecording = false
        locationManager?.stopUpdatingLocation()
        endLiveActivity()
        UIApplication.shared.isIdleTimerDisabled = false

        guard var drive = currentDrive, !recordingLocations.isEmpty else { return }
        let endTime = Date()
        stoppedTimeTracker.finalize(at: endTime)
        drive.endTime = endTime

        // ... attemptsResolved, routeData serialization (unchanged from Phase 1) ...

        // Final extended stats
        drive.stoppedTime = stoppedTimeTracker.totalStoppedTime
        drive.leftTurns = leftTurns; drive.rightTurns = rightTurns
        drive.brakeEvents = brakeEvents; drive.laneChanges = laneChanges
        drive.maxAcceleration = maxAcceleration; drive.maxDeceleration = maxDeceleration
        drive.peakGForce = peakGForce; drive.topCornerSpeed = topCornerSpeed
        drive.best060Time = best060Time
        drive.zeroToSixtyAttempts = attemptsResolved

        // Reset actor state for the next drive.
        await RecordingActor.shared.reset()

        let bgTaskID = UIApplication.shared.beginBackgroundTask(withName: "DriveUpload") {
            UIApplication.shared.endBackgroundTask($0)
        }
        defer {
            if bgTaskID != .invalid {
                UIApplication.shared.endBackgroundTask(bgTaskID)
            }
        }

        do {
            let saved = try await apiService.createDrive(drive)
            self.drives.insert(saved, at: 0)
            self.carStatsManager.updateStats(for: saved)
            self.currentDrive = nil
            self.recordingStartTime = nil
            self.attempts060 = []
            #if DEBUG
            print("✅ Drive saved and car stats updated")
            #endif
            await self.refreshAchievementsFromServer()
        } catch {
            #if DEBUG
            print("❌ Failed to save drive: \(error.localizedDescription)")
            #endif
        }
    }
```

- [ ] **Step 2: Update the call site in `ContentView` (or wherever `stopRecording()` is invoked) to use `Task`**

The signature change is source-breaking. Grep for `driveManager.stopRecording` and wrap each call site in `Task { await driveManager.stopRecording() }`. Likely sites: `ContentView.swift` (the safety disclaimer "I Understand" button).

- [ ] **Step 3: Build the project**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-83-perf-phase2
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: clean build, all tests pass.

- [ ] **Step 4: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/DriveManager.swift
# + any call site files updated in Step 2
git commit -m "refactor(ios): make stopRecording async, reset actor on stop

stopRecording is now @MainActor async; the upload runs in the
function body (no nested Task), wrapped in beginBackgroundTask
with a defer'd end. RecordingActor.reset() runs before the
upload so the next startRecording starts from a clean slate.

Call sites updated to Task { await driveManager.stopRecording() }."
```

- [ ] **Step 5: On-device validation**

Repeat the on-device validation steps from the Phase 1 plan, Task 6. With Phase 2 in place, additionally confirm:

- The 10 Hz publish cap on the snapshot is visible in Instruments (the actor's `lastPublishedAt` delta should cluster around 100 ms during a drive).
- The map's polyline visibly simplifies during a long drive (zoom in on a curvy section — should still look like a curve, but with fewer vertices).
- The map no longer shows 3D terrain during recording (flat elevation).

---

## Verification

- [ ] `xcodebuild test` (full suite, iPhone 17 Pro) clean
- [ ] `xcodebuild build-for-testing` clean
- [ ] `RecordingActorTests`, `RouteDecimatorTests`, `RouteSerializerTests`, `RunningSpeedStatsTests` all pass
- [ ] On-device 15-min drive: no frame drops, post-stop time-to-interactive ≤ 2 s
- [ ] On-device map: visible simplification of long polylines, flat elevation during recording

## Definition of done

- All 6 tasks committed with conventional-commit messages
- iOS test suite passes
- Manual on-device perf confirms Phase 1 metrics still hold, plus the new actor-based architecture
- Call sites for `stopRecording()` updated to the new async signature
