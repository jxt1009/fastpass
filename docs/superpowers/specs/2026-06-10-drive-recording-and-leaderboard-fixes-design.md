# Drive recording performance, leaderboard car photo, and car hero gauges

Date: 2026-06-10
Status: Design — ready for review

## Context

Three open GitHub issues target different layers of FastTrack. They share no code
and are good candidates for parallel worktrees.

| Issue | Surface             | One-line summary                                                                                                       |
| ----- | ------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| #81   | iOS view + Go SQL   | Leaderboard rows always show the placeholder car icon because `car_photo_url` is never populated in the SQL response.  |
| #82   | iOS view only       | Car hero gauges in `CarDetailView` open downward and don't animate on first appear.                                    |
| #83   | iOS runtime         | `DriveManager` / `LocationManager` perform 25 Hz main-thread work; the app slows down ~10 min into a drive and freezes for 30s–1 min after stopping. |

Goals, per issue:

- **#81.** Leaderboard rows render the user's selected car photo when one exists. No iOS model changes; one additive Go handler change.
- **#82.** Top-speed and 0-60 gauges in `CarDetailView` open upward (half-donut), render the value below the arc, and animate from 0 to the final value on first appear.
- **#83.** Eliminate the in-recording frame drops and the post-stop freeze. Preserve all current behavior (route shape, 0-60 detection, brake events, G-force, smoothness, Live Activity content). No model or backend changes. Phased: Phase 1 minimal-risk hot-path fixes; Phase 2 deeper architectural rewrite.

## Out of scope (for all three issues)

- No changes to the public `Drive`, `LeaderboardEntry`, `CarDetailData`, or any other on-the-wire JSON shape
- No backend migrations
- No changes to detection algorithms (0-60, brake events, turns, lane changes) — only where they execute
- No changes to `LocationManager`'s Kalman / fusion math
- No changes to `PublicCarDetailGauge` for #82 (separate issue if desired later)
- No iOS-side refactor of the private `CarThumbnail` in `SocialView.swift` for #81 (a follow-up if duplication becomes a problem)

---

## Worktree A — Issue #83: Drive recording performance

### Root causes (confirmed via code reading)

1. **`LocationManager.startIMU` (`ios/FastTrack/FastTrack/Services/LocationManager.swift:106–112`)** delivers 25 Hz motion updates to `.main` and writes four `@Published` properties on every tick.
2. **`processSpeedSample` (`ios/FastTrack/FastTrack/ViewModels/DriveManager+Processing.swift:58–86`)** runs 25 Hz on main, appends to an **unbounded** `speedReadings` array, and triggers `updateCurrentDrive()` (lines 304–348) on every GPS tick. `updateCurrentDrive` does an O(N) `reduce`/`.max`/`.min` over the entire `speedReadings` history — at 10 min that's a 15,000-element scan 1–10 times/sec.
3. **`processLocationHeavy` (`ios/FastTrack/FastTrack/ViewModels/DriveManager+Processing.swift:96–232`)** is `Task.detached` but performs **7+ `await MainActor.run { ... }` round-trips per location update** to read or write small scalars (`maxAcceleration`, `lastBrakeTime`, `topCornerSpeed`, `headingWindow`, etc.).
4. **`stopRecording` (`ios/FastTrack/FastTrack/ViewModels/DriveManager.swift:197–299`)** synchronously serializes the entire `richRoutePoints` + `recordedRouteEvents` arrays into `routeData` JSON on the **main thread**, then dispatches the upload as an unstructured `Task { ... }` with no `beginBackgroundTask` wrap (so a backgrounded app can have its upload killed mid-flight).
5. **`LiveMapView` (`ios/FastTrack/FastTrack/Views/ContentView.swift:365–421`)** rebuilds `MapPolyline(coordinates: routeCoordinates)` with the **full** `routeCoordinates` array on every render, with `.mapStyle(.standard(elevation: .realistic))` for a continuously growing polyline.
6. **`updateLiveActivity` (`ios/FastTrack/FastTrack/ViewModels/DriveManager+LiveActivity.swift:27–39`)** calls `activity.update(content)` on every GPS tick (1–10 Hz).

### Approach — phased rewrite

#### Phase 1 — Minimal-risk hot-path fixes (PR #83a)

Goal: largest gains, smallest surface area. No new actors, no model changes.

1. **Bound `speedReadings`.** Replace the unbounded `[Double]` with a fixed-capacity ring buffer (last 1,500 samples ≈ 1 min at 25 Hz). Anything older is dropped; the buffer is used only for "recent average" UI smoothness and for min/max during the active drive. The **final** min/max/avg for the saved `Drive` are computed once at `stopRecording` time from a single pass over `richRoutePoints` and the full (in-memory) `recordingLocations`.
2. **Incremental running stats.** Maintain `runningMinSpeed`, `runningMaxSpeed`, `runningSumSpeed`, `runningCountSpeed` as four `Double`/`Int` scalars. Update them in O(1) on every `processSpeedSample`. `updateCurrentDrive` reads them in O(1). No more O(N) scans on the hot path.
3. **Move JSON serialization off main.** In `stopRecording`, perform the `JSONSerialization.data(...)` for `routeData` on a `Task.detached(priority: .userInitiated)` and only hop to main to assign the resulting string into `drive.routeData`. The actual `apiService.createDrive(drive)` call can then proceed.
4. **`beginBackgroundTask` wrap.** In `stopRecording`, wrap the upload in `UIApplication.shared.beginBackgroundTask(...)` / `endBackgroundTask` so a user backgrounding the app immediately after stop doesn't kill the upload mid-flight.
5. **Throttle `LiveActivity` updates to 1 Hz.** In `updateLiveActivity`, track `lastLiveActivityUpdate: Date?` and skip if `< 1s` since the previous update. (Or batch updates onto a 1 Hz timer that reads the latest stats — implementation detail of the PR.)
6. **Cap `@Published` fan-out at 10 Hz on main.** Add a `lastPublishedAt: Date?` guard around the view-facing `@Published` assignments in `processSpeedSample` and `processLocation`. If `< 0.1s` since the last publish, skip the assignment (the underlying state still updates; the view just doesn't re-render).

Phase 1 should resolve both reported symptoms. The 25 Hz → 10 Hz publication cap alone drops SwiftUI re-renders by 60%, and bounded `speedReadings` keeps the min/max/avg cost flat.

#### Phase 2 — Architectural rewrite (PR #83b)

Goal: durable architecture, prevents future regressions. Bigger PR, more invasive.

1. **New `@globalActor RecordingActor`** backed by a dedicated `DispatchQueue` at `.userInitiated` QoS.
2. Move all hot-path data and processing (the IMU/GPS deltas, `recordingLocations`, `richRoutePoints`, `recordedRouteEvents`, the 25 Hz `processSpeedSample`, the bounded `speedReadings`, the extended tracking state) onto `RecordingActor`.
3. Replace the 7+ `MainActor.run` round-trips in `processLocationHeavy` with a single `DriveStatsSnapshot` value-type returned to main per tick.
4. **Throttled, coalesced publication:** the actor hands view-facing state to the main actor at most 10 Hz (same coalesce pattern as Phase 1 step 6, enforced by the actor).
5. **`stopRecording` becomes `async throws -> SavedDrive`.** All serialization on the actor; upload wrapped in `beginBackgroundTask`; returns the saved drive to the caller.
6. **Decimated polyline for `LiveMapView`.** Add `RouteDecimator` (Douglas–Peucker, ≤500 points). `LiveMapView` consumes the decimated array; the full-fidelity array stays in `DriveManager`/`RecordingActor` for serialization.
7. **Switch `LiveMapView` map style to `.standard(elevation: .flat)`** during recording. The realistic-elevation style is the GPU hot spot when paired with a redrawing polyline.
8. **Optional:** `os_signpost` interval markers in DEBUG builds around `processLocation`, `processSpeedSample`, `updateCurrentDrive`, and the stop-path serialization so future perf investigations have something to anchor on.

#### Phase ordering and validation

- **Phase 1 lands first.** Validated by a 15-min on-device drive: no dropped frames, post-stop time-to-interactive ≤ 2s.
- **Phase 2 lands only after Phase 1 is verified.** If Phase 1 alone is sufficient, Phase 2 is optional.

#### Tests

- New `ios/FastTrack/FastTrackTests/RecordingActorTests.swift` (Phase 2): ring buffer behavior, reservoir sampling accuracy vs. one-pass, incremental stats invariants (`min`/`max`/`avg`/`count` after N appends match a one-pass scan of the same N values), throttle/coalesce behavior.
- New `ios/FastTrack/FastTrackTests/RouteDecimatorTests.swift` (Phase 2): Douglas–Peucker reduces a known polyline to expected point count within a tolerance.
- Existing `ios/FastTrack/FastTrackTests/CarDetailGaugeProgressTests.swift` and `…WiringTests.swift` must continue to pass.
- Full `xcodebuild test` against `iPhone 17 Pro` simulator must pass.

#### Files affected

- `ios/FastTrack/FastTrack/Services/LocationManager.swift` — Phase 1: keep as-is. Phase 2: bridge callbacks to `RecordingActor`.
- `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift` — both phases.
- `ios/FastTrack/FastTrack/ViewModels/DriveManager+Processing.swift` — both phases.
- `ios/FastTrack/FastTrack/ViewModels/DriveManager+LiveActivity.swift` — Phase 1 throttle.
- **New** `ios/FastTrack/FastTrack/ViewModels/RecordingActor.swift` — Phase 2.
- **New** `ios/FastTrack/FastTrack/ViewModels/RouteDecimator.swift` — Phase 2.
- `ios/FastTrack/FastTrack/Views/ContentView.swift` — Phase 2: `LiveMapView` consumes decimated points, flat elevation.
- `ios/FastTrack/FastTrack/Models/CarStats.swift` — no changes expected.
- `ios/FastTrack/FastTrackTests/RecordingActorTests.swift` (new, Phase 2)
- `ios/FastTrack/FastTrackTests/RouteDecimatorTests.swift` (new, Phase 2)

#### Risk

Phase 1 is low risk (bounded buffers, throttled publication are textbook fixes). Phase 2 carries the standard "global actor" migration risk: race conditions or missed state if any code path mutates the moved state off-actor. Mitigated by the new unit tests and by the fact that all moved state is currently private to `DriveManager`/`LocationManager` and only accessed from those two files.

---

## Worktree B — Issue #81: Leaderboard car photo

### Root cause

`backend/internal/app/social_handlers.go` declares `CarPhotoURL *string \`json:"car_photo_url"\`` on the response struct (line 21) but the `SELECT` and the construction loop never populate it. `User.Garage` is a `text` column containing a JSON array; the per-car `photo_url` lives inside that array keyed by `id == entry.CarID`. iOS already decodes the field (`LeaderboardEntry.carPhotoUrl: String?` in `ios/FastTrack/FastTrack/Models/SocialModels.swift:31`), and `LeaderboardRow` already renders it via `CarThumbnail(urlString: entry.carPhotoUrl, size: 40)` in `ios/FastTrack/FastTrack/Views/SocialView.swift:302`. Once the backend populates the field, the iOS side will render the photo with no further changes.

### Approach

**Backend** — one helper, one extra `SELECT`, no schema change.

In `social_handlers.go`:

1. After the existing per-page loop builds `entries`, collect the unique `userID`s that have a non-nil `carID`.
2. Run a single `SELECT id, garage FROM users WHERE id IN (...)` against the same page, parse each `garage` into a `[]map[string]any` (or a typed `[]GarageCar` struct with a `json:"photo_url"` field — see below).
3. For each entry, look up `garageCar = parsedGarage[userID][carID]` and set `entry.CarPhotoURL = &garageCar.PhotoURL` if present.
4. Cache the parsed `map[uint]map[string]string` (userID → carID → photoURL) on the request — or, more pragmatically, scope it to a single `getLeaderboard` call so we don't risk cross-request leakage.

The helper that does step 2/3 should be factored into a `garage.go` (or `user_garage.go`) helper file alongside the existing garage-photo logic in `auth_handlers.go:511` (`setCarPhotoURLInGarage`), so future code that needs to read per-car fields can reuse the same parser. AGENTS.md's "additive only" backward-compat rule is preserved: no migration, no column rename, the only new thing is one helper function in the Go package and one `SELECT` per leaderboard request.

For a 50-row page with 50 unique users (worst case, since each user can appear up to 3 times), the extra query is `WHERE id IN (...)` with ≤ 50 IDs — well within PostgreSQL's comfort zone. The leaderboard endpoint is not on a hot path (it's a user-initiated refresh on the Social tab).

**iOS** — no model or view changes. The placeholder `car.fill` icon in `SocialView.swift:370–402` is replaced automatically once the backend returns real URLs.

### Tests

- `backend/internal/app/leaderboard_test.go` (or extend an existing handler test): seed two users with garage cars (one with a `photo_url`, one without), call the handler, assert that the response includes `car_photo_url` for the first and `null` for the second. Assert the SQL helper correctly handles missing `id`, missing `photo_url`, malformed JSON, and an empty garage array.
- iOS: no new tests required. Existing `SocialView` rendering continues to work for both populated and `null` cases (the `carPhotoUrl: String?` decoder already handles both, and the `CarThumbnail` placeholder path is already exercised).

### Files affected

- `backend/internal/app/social_handlers.go` — add the batched lookup + populate `entry.CarPhotoURL`.
- `backend/internal/app/garage.go` (new) — parse-and-index helper. Reuses the parsing pattern from `auth_handlers.go:511`.
- `backend/internal/app/garage_test.go` (new) — table-driven tests for the parser.
- No iOS changes.

### Risk

Low. The `car_photo_url` field has always been declared on the response struct; this is a bug fix, not a contract change. Old iOS clients ignore unknown fields and tolerate `null`. New iOS clients (this version) will start showing real photos.

---

## Worktree C — Issue #82: Car hero gauge formatting

### Root cause

`ios/FastTrack/FastTrack/DesignSystem.swift:226–247` defines `GaugeArc` with `startAngle: 135, endAngle: 45` — a 270° arc that opens *downward*. The car hero cards in `CarDetailView` use two `CarDetailGauge`s stacked in an `HStack` (`ios/FastTrack/FastTrack/Views/CarDetailView.swift:267–296`), with the value rendered **above** the arc and the arc pinned to the bottom of the card. The issue asks for a traditional speedometer: half-circle arc opening **upward**, value **under** the arc, animating from 0 on first appear.

The range math in `ios/FastTrack/FastTrack/Models/CarDetailGaugeProgress.swift` is already correct (0–80 m/s ≈ 0–179 mph, 2–8 s for 0-60, inverted). No math changes needed; this is purely layout + animation.

### Approach

In `DesignSystem.swift`:

- Change `GaugeArc` defaults to `startAngle: 180, endAngle: 360` (or `0`; equivalent — half-donut opening upward, value below).

In `ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift`:

- Re-layout the card: header (title) at the top, arc in the middle, **value+unit below the arc**, caption (set-on date) at the bottom. The arc should have explicit height (e.g., 80–100 pt) so the half-donut has room to breathe.
- Add an `onAppear`-driven animation: hold `displayedProgress` state starting at 0, then in a `.task` (or `.onAppear`) set it to the final `progress` inside `withAnimation(.easeInOut(duration: 0.6))`. The existing implicit `.animation(.easeInOut(duration: 0.35), value: progress)` (line 102) only fires when `progress` changes after the view is on screen — it does not fire on first appear.
- Re-evaluate the `visualProgress` floor (`CarDetailGaugeProgress.visualProgress`'s `minimumVisible = 0.12`): on a half-donut, a 12% floor is more visible than on a 270° arc, but for a true 0 ("no record yet") the value string is already "—" and `progress` is 0. The floor is only applied to non-zero values below 12%; behavior is correct, but worth a manual check.

The `PublicCarDetailGauge` (`ios/FastTrack/FastTrack/Views/Components/PublicCarDetailGauge.swift`) is left alone per scope.

### Tests

- The existing `ios/FastTrack/FastTrackTests/CarDetailGaugeProgressTests.swift` and `…WiringTests.swift` lock the math. No math changes here, so they should continue to pass.
- New `ios/FastTrack/FastTrackTests/CarDetailGaugeViewTests.swift` (if a snapshot-testing harness exists) or manual verification on `iPhone 17 Pro` simulator: the arc opens upward, value sits below, animation runs from 0 to final on appear.
- Full `xcodebuild test` against `iPhone 17 Pro` simulator must pass.

### Files affected

- `ios/FastTrack/FastTrack/DesignSystem.swift` — `GaugeArc` angle defaults.
- `ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift` — layout + onAppear animation.
- No other files.

### Risk

Low. Visual-only change. If a regression in another view that uses `GaugeArc` is discovered (e.g., the settings screen or a debug overlay), the angle defaults can be overridden at the call site instead of changing the default.

---

## Worktree layout

Following AGENTS.md §1 (always pull latest `main` first, worktree under `.worktrees/`, one per logical unit of work):

```
.worktrees/issue-83-perf-phase1        ← Worktree A, PR #83a
.worktrees/issue-83-perf-phase2        ← Worktree A, PR #83b (after #83a merges)
.worktrees/issue-81-leaderboard-photo  ← Worktree B
.worktrees/issue-82-gauges             ← Worktree C
```

- All three worktrees are based on the **latest `origin/main`** at creation time.
- Each lands as its own PR with a conventional-commit title.
- Each is rebased onto the latest `origin/main` before push (`--force-with-lease`).
- Worktree A is itself two PRs: #83a (Phase 1) lands first, then #83b (Phase 2) is rebased on top of #83a.

## Verification plan

For each PR, before claiming "done":

1. **iOS PRs (A, C):** `xcodebuild test` against `iPhone 17 Pro` simulator passes (per `.github/copilot-instructions.md`).
2. **Backend PR (B):** `CGO_ENABLED=1 go test ./... -timeout 60s` passes; new `garage_test.go` cases pass.
3. **#83 specifically:** on-device 15-min simulated drive shows no frame drops in the speedometer; post-stop time-to-interactive (time from tapping Stop to being able to tap the leaderboard tab and see it load) is ≤ 2 seconds. (Validated manually by the developer with a debug build on a real device; no automated UI test for this.)
4. **#82 specifically:** manual visual check on `iPhone 17 Pro` simulator: arc opens upward, value sits below, animation runs from 0 to final on appear.

## Spec self-review

- **Placeholders:** none. All ranges, durations, and target numbers are explicit.
- **Internal consistency:** the three issues are independent and the worktrees don't share files. The two #83 phases share files but Phase 1 is verified before Phase 2 begins.
- **Scope:** each issue fits in a single implementation plan. #83's two phases are tracked as separate PRs but designed together so the writing-plans skill can produce two plans from this single spec.
- **Ambiguity:** the "animation runs from 0 to final" in #82 is specified (`.easeInOut(duration: 0.6)` via `withAnimation`). The "≤ 10 Hz publication cap" in #83 is specified (0.1-second floor via a `lastPublishedAt` guard). The "1 Hz Live Activity throttle" in #83 is specified. The "fixed-capacity ring buffer (1,500 samples)" in #83 Phase 1 is specified; final saved-drive stats are computed once at stop from the full `recordingLocations` / `richRoutePoints` (not from the bounded buffer).
