# Improve speed data quality

## Problem

FastTrack already estimates speed at roughly 25 Hz with IMU + GPS fusion, but the recorded 0-60 metric still completes off sparse `CLLocation` callbacks. That makes very quick launches read far too slow. The app also waits too long to settle back to a trustworthy `0 mph` state after a stop, which makes standing-start runs awkward to begin.

## Scope

- Improve the existing iPhone sensor pipeline first.
- Keep route geometry and distance based on `CLLocation`.
- Do not add Tesla, OBD, or other vehicle-data integrations in this phase.

## Implementation

1. Add a timestamped speed-sample stream in `LocationManager` so downstream consumers get fused speed, raw GPS speed, speed accuracy, zero-lock state, and stationary confidence from the same source of truth.
2. Tighten `SpeedFusion` near-zero behavior so it reaches a reliable stopped state quickly using low-speed hysteresis and low-motion confidence instead of waiting solely for a later GPS zero.
3. Move launch timing in `DriveManager` onto the high-rate fused samples.
4. Detect the exact 60 mph crossing by interpolating between the last sample below target and the first sample above it.
5. Keep persisted route payloads bounded and backward compatible; continue storing route points at location cadence rather than full-drive 25 Hz traces.
6. Fix route parsing so both legacy arrays and current v2 payloads keep working.

## Validation

- Fast-launch coverage for ~3 second 0-60 runs
- Rolling-start rejection
- Faster stop-to-zero readiness
- Route parsing compatibility for old and current payloads
