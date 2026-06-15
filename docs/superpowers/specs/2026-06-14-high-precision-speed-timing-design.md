# High-Precision 0-60 Timing & Top Speed Accuracy

**Date:** 2026-06-14
**Status:** Design approved, awaiting implementation plan
**Target:** ±0.05s 0-60 accuracy, improved top-speed leaderboard integrity

## 1. Architecture Overview

Three-layer design:

### Layer 1 — Recording (real-time, 100 Hz)
- IMU polling bumped from 25 Hz → 100 Hz
- SpeedFusion Kalman filter runs at 100 Hz (was 25 Hz)
- Every 100 Hz SpeedSample buffered into compact ring buffer
- Launch detection upgraded to jolt-based (longitudinal accel threshold, not just lock break)
- Top speed tracking: windowed median + max over 0.5s of fused samples

### Layer 2 — Post-hoc Analysis (at drive end)
- Full 100 Hz speed stream replay via dedicated `LaunchAnalyzer`
- Two-pass launch detection: (1) find acceleration events, (2) backward-search for true launch point
- Computes 0-30, 0-60, 0-100, quarter-mile time, quarter-mile trap speed
- Replaces real-time LaunchTracker for final stored values
- Each attempt carries metadata: coordinates, confidence score, GPS accuracy

### Layer 3 — Leaderboard Integrity
- Attempts carry confidence metadata
- Backend can flag low-confidence entries (fused speed exceeding GPS max by >5 m/s)
- Future: server-side validation of attempt plausibility

## 2. Speed Sample Buffer & Storage

### Real-time Buffer
- `DriveRecordingController` maintains `speedStream: [(TimeInterval, Double, Bool, Double)]`
  - Fields: `(timestamp, fusedSpeedMetersPerSecond, isZeroLocked, stationaryConfidence)`
  - isZeroLocked + stationaryConfidence are required by LaunchAnalyzer Pass 2 to find the true launch point
- Consumed from every 100 Hz `SpeedSample` via Combine subscription
- Max memory: ~36K samples/hour at 100 Hz (~600 KB in-memory including the extra fields)

### Route Data v3 Encoding
- Delta-compressed JSON array inside `route_data` under `"speed_stream"` key
- First entry: `[absolute_ts, speed, isZeroLocked, stationaryConfidence]`
- Subsequent entries: `[Δms, speed, isZeroLocked, stationaryConfidence]`
  - `Δms` = integer milliseconds elapsed since prior sample
  - `isZeroLocked` emitted as `1`/`0` (small)
  - `stationaryConfidence` emitted as float
- Estimated size: ~300-500 KB for a 30-min track session at 100 Hz

### Route Data Versioning
- Introduce `RouteSerializer.encodeV3()` with `version: 3` marker
- Existing `encodeV2()` preserved for backward compatibility
- iOS reads v3 if present, falls back to v2 data

## 3. LaunchAnalyzer Algorithm

### Pass 1 — Acceleration Event Detection
- Scan 100 Hz speed stream with rolling 1s window
- Compute average slope (m/s²) per window
- When slope > 1.5 m/s² (~0.15g) for 5+ consecutive samples (50ms), mark as an acceleration event
- Merge contiguous events into a single launch window

### Pass 2 — True Start Point
- From first sample in the acceleration event, walk backward
- Find last sample where speed is stationary:
  - Speed < 0.3 m/s AND (isZeroLocked OR stationaryConfidence ≥ 0.8)
- If no stationary point within 2s backward window, use the sample just before sustained positive slope began
- The sample *after* this stationary point = launch T=0

### Interpolation
- Same linear interpolation approach used in `LaunchTracker.interpolatedCrossingTime()`
- Applied for 30 mph, 60 mph, 100 mph crossings
- Quarter-mile: trapezoidal integration of speed × time across 100 Hz samples; cross-checked against GPS-derived distance using the haversine sum of consecutive route points
- Quarter-mile trap speed: fused speed at the sample where cumulative integrated distance reaches 402.336 m

### Confidence Score (0-1)
- Factors:
  - GPS accuracy at launch time (from `CLLocation.horizontalAccuracy` of the nearest location sample; better = higher)
  - IMU noise floor: standard deviation of longitudinal acceleration over a 0.5s window before launch (lower = higher)
  - Longitudinal-vs-lateral ratio: ratio of longitudinal to total acceleration magnitude during the run (higher = cleaner launch on a straight path)
  - Inter-sample speed consistency: coefficient of variation of speed deltas during the run
- Stored as metadata on each `ZeroToSixtyAttempt`

## 4. Top Speed Accuracy

### Current Issue
`runningSpeedStats.max` is a running max — a single IMU spike (pothole → accelerometer jolt) can create a phantom peak.

### Design
- Replace raw running max with **0.5s rolling median + max** filter over 100 Hz speed stream
- At each GPS update (~1 Hz), record GPS-reported speed as ground-truth comparator
- Store two fields in the Drive (all m/s):
  - `fused_max_speed` (new): rolling-median-filtered max from the IMU stream
  - `gps_max_speed` (new): max from GPS location updates
- Computed `maxSpeed` (existing field) uses the **favoring-GPS-when-confident** rule:
  ```
  if gps_max_speed exists and nearest GPS update had horizontalAccuracy < 50 m:
      maxSpeed = max(gps_max_speed, fused_max_speed * 0.95)
  else:
      maxSpeed = fused_max_speed
  ```
  (The 0.95 factor on fused avoids trusting IMU fusion above GPS when GPS has been reporting higher sustained speeds — covers cases where the rolling median filtered out a legitimate peak.)
- Leaderboard displays `maxSpeed`. Flag entries where `fused_max_speed - gps_max_speed > 5 m/s` as low-confidence (visual indicator, not hidden)

### SpeedPeak Struct
```swift
struct SpeedPeak {
    let timestamp: Date
    let speed: Double         // m/s
    let source: SpeedSource   // .fused | .gps
    let confidence: Double    // 0-1
}
```
Stored in `route_data` v3 alongside the speed stream.

## 5. IMU Rate Change

### LocationManager Changes
- `motionManager.deviceMotionUpdateInterval` from `1.0 / 25.0` → `1.0 / 100.0`
- `handleMotionUpdate` dt updated to `1.0 / 100.0`
- SpeedFusion `predict()` called at 100 Hz
- `publishSpeedState()` called at 100 Hz
- `currentSpeedSample` publishes 4x more frequently
- `DriveRecordingController` subscribes to `$currentSpeedSample` at 100 Hz
- `clManager.activityType = .automotiveNavigation` set at startup (Apple may increase GPS update frequency for automotive use; cheap, no downside)

### SpeedFusion Kalman Retuning for 100 Hz

The process noise `Q = 0.5` is per-second and applied as `P += Q * dt`, so the per-second behavior is mathematically identical at 25 Hz or 100 Hz. **But the low-speed damping coefficients are applied per-tick**, not per-second:

- Current code (25 Hz): `speed *= 0.72` 25 times/sec
- New code (100 Hz): `speed *= ?` 100 times/sec

To preserve the same per-second damping behavior, the new coefficient is `oldCoeff^(25/100) = oldCoeff^0.25`:
- `0.72 → 0.72^0.25 ≈ 0.921` (4x less aggressive per tick, 4x more ticks → same per-second effect)
- `0.86 → 0.86^0.25 ≈ 0.963`

These are added to `SpeedFusion` as named constants (`lowSpeedDampingCoefficient_100Hz` and `lowSpeedDampingCoefficientActive_100Hz`) so the relationship to the 25 Hz values is explicit and reviewable. The 25 Hz coefficients are kept on the class so the math is self-documenting in code review.

### Main-Thread Throttling

`$currentSpeedSample` will fire 100 times/sec. The main-thread cost of `processSpeedSample` (append to speedStream, ingest into stats, ingest into LaunchTracker, possibly update `currentDrive`) becomes a problem at 100 Hz:

- **Buffer at full 100 Hz**, but throttle `currentDrive` updates to 10 Hz using the existing `publishThrottler` (or a new dedicated `speedPublishThrottler` if that one is locked at a different rate)
- The speed stream, stats, and LaunchTracker all process every sample at 100 Hz
- The SwiftUI-facing `currentDrive` and any UI-bound `@Published` properties get a max of 10 updates/sec
- Encoded route data is **not** affected — it captures the full 100 Hz stream regardless of UI update rate

### Battery Impact Mitigation
- 100 Hz IMU is always-on during recording (user chose accuracy over battery)
- No dynamic rate switching needed

## 6. Data Flow

```
CMMotionManager (100 Hz)
    → handleMotionUpdate()
    → SpeedFusion.predict(longAccelG, dt=0.01s) [with 100 Hz damping coefficients]
    → publishSpeedState() → SpeedSample
    → DriveRecordingController.processSpeedSample()
        → speedStream.append((ts, speed, isZeroLocked, stationaryConfidence))
        → runningSpeedStats.ingest(speed) [rolling median+max]
        → launchTracker.ingest(sample) [real-time detection continues]
        → currentDrive.update (throttled to 10 Hz for UI)

CLLocationManager (~1 Hz, activityType=.automotiveNavigation)
    → locationManager(didUpdateLocations:)
    → SpeedFusion.update(gpsSpeed, gpsSpeedAccuracy)
    → publishSpeedState(forceSpeedUpdate: true)
    → DriveRecordingController.processLocation()
        → richRoutePoints.append(...)
        → gpsMaxSpeedTracker.ingest(location.speed)

Drive end → stopRecording()
    → stoppedTimeTracker.finalize()
    → LaunchAnalyzer.analyze(speedStream) → [ZeroToSixtyAttempt] (overrides real-time)
    → TopSpeedComputer.compute(speedStream, gpsMaxSpeed) → (fusedMax, gpsMax, finalMax)
    → RouteSerializer.encodeV3(speedStream, richRoutePoints, attempts, speedPeaks, routeEvents)
    → drive.routeData = json
    → drive.fusedMaxSpeed = fusedMax (m/s)
    → drive.gpsMaxSpeed = gpsMax (m/s)
    → drive.maxSpeed = finalMax (m/s)
    → apiService.createDrive(drive)
```

## 7. Backward Compatibility

- `route_data` v3 is additive — old iOS clients ignore `"speed_stream"` and `"speed_peaks"` fields
- `Drive` struct gets new optional fields `fusedMaxSpeed`, `gpsMaxSpeed` (nullable on backend)
- Backend `best_060_time` column unchanged — still the single best time
- `zero_to_sixty_attempts` JSON column unchanged — still stores all attempts with additional metadata fields
- Old drives (pre-v3 route_data) parsed without LaunchAnalyzer — fall back to stored `best_060_time`
- Backend `max_speed` column continues to receive the computed `maxSpeed` (m/s), so leaderboards and historical stats stay consistent
- New nullable DB columns for `fused_max_speed` and `gps_max_speed` are added in a new migration (per project convention for additive migrations)

## 8. Testing Strategy

### Unit Tests
- `SpeedFusion` at 100 Hz: verify Kalman filter correctness with simulated GPS+IMU data
- `LaunchAnalyzer` algorithm: synthetic speed streams with known 0-60 times
- `RollingWindowMax`: verify median+max filter rejects spikes
- `RouteSerializer` v3: round-trip encode/decode with delta compression

### Integration Tests
- `DriveRecordingController` end-to-end: mock LocationManager+SpeedSamples → verify stored route_data contains speed stream
- Backward compat: decode a v2 route_data blob → verify LaunchAnalyzer gracefully skips

### iOS Tests
- `DriveCalculationTests`: extend with LaunchAnalyzer accuracy assertions
- New `LaunchAnalyzerTests`: verify ±0.05s accuracy on synthetic data with known ground truth

## Decision Log

| Date | Decision | Rationale |
|------|----------|-----------|
| 2026-06-14 | 100 Hz IMU, no dynamic rate | User prioritized accuracy over battery |
| 2026-06-14 | Post-hoc analysis over real-time-only | Enables backward-search for true launch point that real-time can't do |
| 2026-06-14 | Route data v3 with delta-compressed speed stream | Keeps storage manageable (300-500 KB) while preserving full 100 Hz history with isZeroLocked + stationaryConfidence per sample |
| 2026-06-14 | Two-pass launch detection (event → true start) | Single-pass can't reliably find launch T=0 without looking backward |
| 2026-06-14 | Rolling median+max for top speed | Rejects IMU spike artifacts while catching real peaks |
| 2026-06-14 | External GPS deferred | User chose Approach 2 over Approach 3; can be added later |
| 2026-06-14 | Retune low-speed damping coefficients for 100 Hz (0.921, 0.963) | Coefficients are per-tick; 4x ticks/sec = 4x more damping without retuning. Old values kept as comments for traceability |
| 2026-06-14 | Speed stream carries isZeroLocked + stationaryConfidence | LaunchAnalyzer Pass 2 needs them to find the true launch point; speed-only inference would lose ~1-2 samples of precision |
| 2026-06-14 | Throttle currentDrive UI updates to 10 Hz, keep speed stream at 100 Hz | Main thread can't tolerate 100 UI-triggering updates/sec; data capture is unaffected by UI throttling |
| 2026-06-14 | activityType = .automotiveNavigation | Cheap, may improve GPS update frequency on iPhone |
