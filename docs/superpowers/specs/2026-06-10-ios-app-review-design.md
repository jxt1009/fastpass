# iOS App Review & Improvement Plan

**Status:** Active — R5 in progress (Workstreams 6+7)
**Date:** 2026-06-10 (added 2026-06-11 release notes inline; see §11)
**Audit type:** Read-only full-sweep across performance, security, UX/design system, and stability/architecture
**Files audited:** 60+ Swift files in `ios/FastTrack/FastTrack/`, plus tests in `ios/FastTrack/FastTrackTests/`
**Findings total:** ~85 unique issues (de-duplicated from ~120 raw findings across 4 parallel audits)

---

## 1. Goal

Produce a prioritized catalog of iOS app improvements across all quality dimensions — performance, user experience, security, stability, design-system uniformity, and code architecture — and define sequenced workstreams so each can be planned and shipped as its own PR/branch.

This spec is **not** a single implementation. It is a menu. Each workstream will be planned separately via the `writing-plans` skill before any code is written.

## 2. Non-Goals

- Backend changes. Findings that touch the backend API (e.g. double-encoded `routeData`) are flagged with additive-only constraints per the project's backward-compat rules; server changes are out of scope.
- New features or product surface area. The audit covers improvements to existing behavior; it does not propose new screens, flows, or capabilities.
- iPad-specific work. The app's `UIScene` configuration supports iPad, but the audit ran on iPhone-first assumptions.
- TestFlight / App Store submission work. Privacy manifest and App Review risks are flagged but the cutover plan is the user's call.

## 3. Background & Context

The iOS app has matured rapidly over the last month:

- **Recent wins** (per `git log --oneline -20 ios/FastTrack/`): drive recording actor-based rewrite (Phases 1 & 2), PB gauge animations, public/private car detail unification, profile/garage/leaderboard redesign, in-app notification feed, car photo crop, delete-drive flow.
- **Current state**: 919-line `DriveManager` split across 3 files, 884-line `CarDetailView`, 910-line `DriveDetailView`, 642-line `SharedComponents.swift`. Six of eight managers are singletons; the other two are environment-injected.
- **Testing**: recent additions to recording hot path (`RecordingActorTests`, `RouteDecimatorTests`, `RouteSerializerTests`, `RunningSpeedStatsTests`) are strong. `FastTrackUITests/` does not exist.

The audit identified that the most impactful issues are **correctness/blocker (P0)**, **recording reliability (P1)**, **App Review/location-permission compliance (P1)**, and **design system enforcement (P1)**. The rest are quality, performance, and structure improvements that compound over time.

## 4. Findings Catalog

Severity scale: **P0** = blocker / compile error / data corruption / security, **P1** = user-visible bug or App Review risk, **P2** = quality / consistency, **P3** = nit / nice-to-have. Effort scale: **S** = ≤ half a day, **M** = 1-2 days, **L** = 3+ days.

### 4.1 P0 — Fix immediately

| ID | Cluster | Issue | Files | Effort |
|----|---------|-------|-------|--------|
| P0-1 | Stability | `CarStats.swift:88-94` uses `?? 0` on `Drive.maxAcceleration`, `maxDeceleration`, `peakGForce`, `brakeEvents`, `leftTurns`, `rightTurns`, but those fields are declared **non-optional** in `Models/Drive.swift:32-37` (a drive always has at least a zero value recorded). The `?? 0` is dead code; drop it. If the file currently compiles, the fields may be optional — verify and unify. | `Models/CarStats.swift`, `Models/Drive.swift` | S |
| P0-2 | Performance | `LiveMapView.displayCoordinates` re-runs the `RouteDecimator` (RDP, `O(n log n)`) on **every SwiftUI body call**. During recording, `routeCoordinates` is `@Published` and updates ~1 Hz, so the decimator runs 600 times for a 10-minute drive. Plus `MapKit` redraws on every pass. | `Views/ContentView.swift:390-393` | S |
| P0-3 | Security | OAuth `state` parameter is generated (`GoogleSignInManager.swift:24, 34`) but never verified on the callback. An attacker who can open `com.toper.fasttrack:/oauth2callback?code=ATTACKER_CODE&state=ANYTHING` could link the attacker's Google account to the victim's FastTrack user. | `Services/GoogleSignInManager.swift:24, 34` | S |

### 4.2 P1 — High-impact user-facing

#### Cluster A: Recording drive loss (4 ways to lose a drive)

| ID | Issue | Files | Effort |
|----|-------|-------|--------|
| A-1 | `stopRecording` catches `createDrive` errors with only a DEBUG print (`DriveManager.swift:303-307`). The user sees a successful "Stop" with no drive saved. | `ViewModels/DriveManager.swift:303-307` | M |
| A-2 | Sign-out does not `stopRecording` if a recording is in progress (`FastTrackApp.swift:104-112`). The in-flight `processLocation` continues to append to `recordingLocations` etc., which the next sign-in user inherits. | `FastTrackApp.swift:104-112` | M |
| A-3 | No `authorizationStatus` check before `startUpdatingLocation`. If the user revoked location permission, `clManager` silently fails; the recording runs to zero and saves a 0-distance drive. | `Services/LocationManager.swift:65-82`, `ViewModels/DriveManager.swift:117-211` | M |
| A-4 | No local persistence of in-flight `routeData` for retry on background-task expiration. The 30-second bg task may expire mid-upload on slow networks. | `ViewModels/DriveManager.swift:213-308` | M |

#### Cluster B: Location permission / App Review risk

| ID | Issue | Files | Effort |
|----|-------|-------|--------|
| B-1 | `requestAlwaysAuthorization()` is called immediately at first launch (`LocationManager.swift:61-63`). HIG and App Review guidance require WhenInUse first, then upgrade to Always when the user starts recording. | `Services/LocationManager.swift:61-63` | S |
| B-2 | `allowsBackgroundLocationUpdates = true` is set unconditionally in `init` (`LocationManager.swift:40-46`), not gated on `isRecording`. Increases always-on exposure surface. | `Services/LocationManager.swift:40-46` | S |
| B-3 | `PrivacyInfo.xcprivacy` is missing `NSPrivacyCollectedDataTypeEmail` and `NSPrivacyCollectedDataTypeUserID` declarations. App Review may flag as incomplete. | `PrivacyInfo.xcprivacy` | S |
| B-4 | `baseURL` is hardcoded (`APIService.swift:9`) with no `Debug`/`Release` switching. Footgun for dev pointing at staging. | `Services/APIService.swift:9` | S |

#### Cluster C: Design system enforcement gap

`DesignSystem.swift` defines a usable foundation (colors, spacing, motion, `InstrumentCard`, `DashboardGauge`, `ftMono`) but enforcement is weak. ~100+ ad-hoc literals should funnel through tokens.

| ID | Issue | Files | Effort |
|----|-------|-------|--------|
| C-1 | 39 hard-coded `cornerRadius` values across the codebase (3, 4, 6, 8, 10, 12, 14, 18) — no `Radius` enum. `DashboardGauge` uses 12, `CarDetailGauge` uses 14 for visually identical "PB hero" — real inconsistency. | `DesignSystem.swift` (add), 12+ view files | S |
| C-2 | 28 raw `.font(.system(size:))` calls — fixed point sizes that bypass Dynamic Type. Sites ≤13pt with critical information should move to relative styles (`.caption`, `.footnote`, etc.). | 14 view/component files | M |
| C-3 | 26 raw `Color.*` / `Color(.system*)` calls bypassing `ft*` tokens. Includes `Color.red`, `Color.blue`, `Color(.systemGray6)`, `Color(.systemFill)`, `Color.white.opacity(0.1)`, etc. | 15+ view/component files | M |
| C-4 | Two near-identical `CarPhotoThumbnail` helpers (`ProfileView.swift:548`, `SocialView.swift:370`, `CarPhotoEditorSection.swift:98`) and two `CarDetailGauge` variants (own vs public) and a `MetricGauge` that overlaps with `DashboardGauge.large`. Consolidate into one parameterized `Gauge` family and one `CarPhotoThumbnail(size:)`. | `DesignSystem.swift`, 4 component files | L |
| C-5 | Two near-identical follow-toggle button variants (`FindPeopleView.swift:160`, `PublicProfileView.swift:205`) and a notification row that mirrors a follower row (`NotificationsView.swift:50`, `FollowersListView.swift:91`). Extract `FollowButton` and `UserRow`. | 4 view files | S |
| C-6 | 6+ inline "badge pill" implementations (PB 0-60, PB Top Speed, "SELECTED", "Active", "You" marker) all share the same recipe (`.padding(.horizontal, 6-8)` + `.padding(.vertical, 2-4)` + `Capsule()`). Extract `BadgePill(text:icon:style:)`. | 5 view files | S |
| C-7 | 2 hand-rolled empty states (`CarDetailView.swift:388`, `GarageView.swift:179`, `RecentAchievementsStrip.swift:47`) should use `ContentUnavailableView` for consistency. | 3 view files | S |
| C-8 | 3 hand-rolled "stats grid (2×2)" patterns in 8+ sites. Extract `StatsGrid(cells:)`. | 6 view files | S |

#### Cluster F: UX silent failures

| ID | Issue | Files | Effort |
|----|-------|-------|--------|
| F-1 | Follow/unfollow button: 2 sites silently swallow errors (`FindPeopleView.swift:193-207`, `PublicProfileView.swift:323-359`). A failed follow leaves the UI in a misleading state. | 2 view files | M |
| F-2 | Notifications: `markRead` / `markAllRead` / fetch errors never surfaced to the user (`NotificationsManager.swift:42, 60, 75, 99, 109`). | `Services/NotificationsManager.swift`, `Views/NotificationsView.swift` | S |
| F-3 | Delete-drive: no undo / no toast in 4 sites. The row simply disappears. | 4 view files | S |
| F-4 | Sign-out leaves no confirmation toast; privacy toggle (public/private profile) persists silently with no feedback. | `Views/ProfileView.swift:302-318` | S |
| F-5 | Add a `Toast` / `Snackbar` component (does not exist) and route all silent-failure paths through it. | new component | M |

#### Cluster G: Accessibility & reduce-motion

| ID | Issue | Files | Effort |
|----|-------|-------|--------|
| G-1 | Zero `@Environment(\.accessibilityReduceMotion)` gates across 24 infinite-loop animations (splash dots, recording red ring, shimmer, confetti). | 5 files | S |
| G-2 | Only 4 explicit VoiceOver labels in the entire app. Map annotations, gps status dot, speed hero ring, avatar tap-zoom all unlabeled. | 6+ files | M |
| G-3 | Notifications bell is 32pt (`NotificationsBell.swift:10`); public profile follow button is 28pt tall. Both below the 44pt minimum. | 2 files | S |
| G-4 | Dynamic Type scaling absent: every `.font(.system(size:))` is fixed-point; no `@ScaledMetric` use anywhere. | 14 files (overlaps with C-2) | M |
| G-5 | `Color.secondary.opacity(0.5)` on `Color(.systemFill)` in the 80×28 follow button (`GarageView.swift:442`) is likely below WCAG AA contrast. | `Views/GarageView.swift:442` | S |

#### Cluster D: Hot-path performance

| ID | Issue | Files | Effort |
|----|-------|-------|--------|
| D-1 | `LocationManager.handleMotionUpdate` runs at 25 Hz on main thread with 3 `@Published` writes per tick (`LocationManager.swift:108-112`). | `Services/LocationManager.swift:108-112` | S |
| D-2 | `currentDrive` struct copy (28 fields including full `richRoutePoints`) on every 10 Hz `processSpeedSample` write → `ContentView.body` re-evaluates 10×/sec. | `ViewModels/DriveManager+Processing.swift:88-90` | M |
| D-3 | `processLocation` updates 3 redundant main-thread arrays per GPS tick (`recordingLocations`, `routeCoordinates`, `richRoutePoints` — all carry the coordinate). | `ViewModels/DriveManager+Processing.swift:26-34` | S |
| D-4 | `processLocation` O(n) total-distance loop on every GPS tick (`DriveManager+Processing.swift:54-57, 219-223`). Per-tick cost grows linearly with drive length. | `ViewModels/DriveManager+Processing.swift` | S |
| D-5 | `URLCache` default is 4 MB. Car/avatar photos re-fetched constantly. | `Services/APIService.swift:11` | S |
| D-6 | `AsyncImage` per cell, no shared cache. Same photo downloaded 2-3× across different views. | `Views/ProfileView.swift:548-588`, `Views/GarageView.swift:343-348`, `Views/ContentView.swift:22` | M |
| D-7 | `createDrive` double-encodes `routeData` (inner JSON string wrapped in outer `Encodable` struct → ~30% payload inflation). | `Services/APIService.swift:112-141` | M |
| D-8 | `processHeadingBackground` (`DriveManager+Processing.swift:134-175`) is **dead code** — never called. Either wire it up (heading → turn/lane-change counting) or delete. | `ViewModels/DriveManager+Processing.swift:134-175` | L |
| D-9 | `LiveMapView.onChange(of: userLocation)` re-creates the region and animates the camera on every GPS tick (`ContentView.swift:427-434`). | `Views/ContentView.swift:427-434` | S |
| D-10 | Many rows (`DriveRowView`, `LeaderboardRow`, `NotificationRow`, `GarageCarCard`) lack `Equatable` conformance, so Lists re-evaluate all rows on every change. | 4 view files | S |
| D-11 | No request deduplication in `APIService.fetchDrives` — the 10-second poll + `ProfileView.onAppear` race to fire concurrent requests. | `Services/APIService.swift:33-94` | M |
| D-12 | `createDrive` upload uses foreground `URLSession`. If app is suspended, upload is paused. Use a `URLSessionConfiguration.background` for the route JSON (write to temp file first). | `Services/APIService.swift:112-141` | L |
| D-13 | `parseRouteData` runs synchronously on main in `DriveDetailView.onAppear` (10-30ms hitch on push for a 600-point route). | `Views/DriveDetailView.swift:224-227, 561-604` | S |
| D-14 | `DriveDetailView.playbackPoint` does O(n) lookup per 20 Hz playback tick. | `Views/DriveDetailView.swift:475-492` | S |
| D-15 | `RecordingActor.ingest` allocates a `CLLocation` per GPS sample (1.7 perf). | `ViewModels/RecordingActor.swift:78-86` | S |

#### Cluster E: Stability & concurrency

| ID | Issue | Files | Effort |
|----|-------|-------|--------|
| E-1 | `fatalError("No window available")` in sign-in managers (`AppleSignInManager.swift:188`, `GoogleSignInManager.swift:125`) will crash the app on multi-scene. | 2 files | S |
| E-2 | `DriveManager` is non-`@MainActor` `ObservableObject`; recording state mutated from `.main` OperationQueue and via `await MainActor.run`. Implicit boundary, brittle to refactor. | `ViewModels/DriveManager.swift` | M |
| E-3 | `AuthManager.isAuthenticated` is `@Published` and mutated across actor boundaries (`AuthManager.swift:130-132`). Will fail under Swift 6 strict concurrency. | `Services/AuthManager.swift` | M |
| E-4 | `SocialView.swift:217` — `let make = parts.count > 0 ? String(parts[0]) : ""`. `parts.count > 0` is always true for `String.split(...)`; crashes on empty input. | `Views/SocialView.swift:217-218` | S |
| E-5 | `PublicCarDetailView.swift:113` — `URL(string: car.photoUrl ?? "")` parses empty string to non-nil `URL`; `AsyncImage` silently fails. Use `car.photoUrl.flatMap { URL(string: $0) }`. | `Views/PublicCarDetailView.swift:113` | S |
| E-6 | `processHeadingBackground` does 7 `await MainActor.run` round-trips per call (`DriveManager+Processing.swift:134-175`). | (overlaps with D-8) | M |
| E-7 | Force-unwraps on `routeCoordinates.first!` / `.last!` in `DriveDetailView.swift:322, 328` outside the gate that ensures non-empty. | `Views/DriveDetailView.swift:322, 328` | S |
| E-8 | 5 force-unwraps in `regionForRoute` (`DriveDetailView.swift:550-555`) on `.min()!` / `.max()!` (redundant — those return non-optional). | `Views/DriveDetailView.swift:550-555` | S |
| E-9 | `existingPhotoURL!.isEmpty` classic unwrap-the-checked value (`CarPhotoEditorSection.swift:110`). | `Views/Components/CarPhotoEditorSection.swift:110` | S |
| E-10 | `Drive.swift:309` `@retroactive Equatable` for `CLLocationCoordinate2D` is not transitively safe for floating point. Will warn under Swift 6 strict concurrency. | `Models/Drive.swift:309-313` | M |
| E-11 | `LiveActivity` `Task { await activity.update(...) }` pile-up when `processLocation` fires faster than OS applies updates (`DriveManager+LiveActivity.swift:44-46`). | `ViewModels/DriveManager+LiveActivity.swift` | S |
| E-12 | `NotificationsManager` polling Task writes to `self` even after sign-out → sign-in creates a new instance; in-flight `refresh()` writes to stale instance. Add a token. | `Services/NotificationsManager.swift:20-28` | S |
| E-13 | Sign-out's `clearLocalData` does not stop an in-flight recording; see A-2. | (overlaps with A-2) | M |
| E-14 | `recordingStartTime!` force-unwrap in DEBUG print (`DriveManager.swift:136`). Currently safe (set on line 124) but gratuitous. | `ViewModels/DriveManager.swift:136` | S |
| E-15 | `URLSession.shared` used everywhere with no `URLSessionDelegate` → no opportunity for cert pinning. (Pinning is a separate workstream; flagged here.) | `Services/APIService.swift:11` and 4 other files | M |

#### Cluster H: Architecture (large files / DI inconsistency)

| ID | Issue | Files | Effort |
|----|-------|-------|--------|
| H-1 | `DriveManager` is 919 lines across 3 files combining recording state, GPS ingestion, math, actor coordination, LiveActivity, achievement fetching, polling timer, and route serialization orchestration. Split into `DriveRecordingController`, `DriveStatsComputer`, `LiveActivityCoordinator`, `DrivePoller`. | `ViewModels/DriveManager*.swift` | L |
| H-2 | `CarDetailView` is 884 lines combining hero, PB gauges, sparkline, performance breakdown, period comparison, trends, recent drives, hero photo editor, driving-style guide, confetti overlay. Split into focused sub-views. | `Views/CarDetailView.swift` | M |
| H-3 | `DriveDetailView` is 910 lines combining map, playback, 0-60 attempts, gauges, trip details, delete, car-reassignment. Split similarly. | `Views/DriveDetailView.swift` | M |
| H-4 | `SharedComponents.swift` is 642 lines including the 150-line `StatInfo` glossary. Move `StatInfo` to a JSON resource, split `InstrumentCard.swift`. | `Views/SharedComponents.swift` | M |
| H-5 | Inconsistent DI: 6 managers are singletons (`ProfileManager`, `CarStatsManager`, `AppSettings`, `AchievementManager`, `AuthManager`, `APIService`); 2 are environment-injected (`LocationManager`, `DriveManager`). Pick a single pattern. | `FastTrackApp.swift:12-17` and 6 manager files | L |
| H-6 | `CarDetailData.derive` couples the data layer to `CarStatsManager.shared` (`CarDetailData+Derive.swift:179`). Pass the calculator in or extract the formula to a free function. | `Models/CarDetailData+Derive.swift:179` | S |
| H-7 | Parallel "own" and "public" car detail data structures (`CarDetailData` vs `PublicCarDetailData`, plus their `+Derive.swift` counterparts) with similar derive logic. Extract a shared `deriveCarStats(for:drives:stats:)` helper. | 4 model files | M |
| H-8 | `Achievement.swift` mixes model, requirement types, manager (200+ lines), and a private `createDefaultAchievements` factory. Split into `AchievementModel`, `AchievementManager`, `AchievementCatalog`. | `Models/Achievement.swift` | M |
| H-9 | `RecordingActor.shared.previousRoutePoint()` (`DriveManager+Processing.swift:106`) is a Sendable value type that should be explicitly `Sendable`-conformed. | `ViewModels/RecordingActor.swift` | S |
| H-10 | `GarageView` and `GarageCarCard` both `@StateObject` the same `profileManager` / `carStatsManager` singletons; the child also `@ObservedObject`s them. Redundant. Inject via environment. | `Views/GarageView.swift:18-20, 240-241` | S |

#### Cluster I: Test coverage gaps

| ID | Issue | Files | Effort |
|----|-------|-------|--------|
| I-1 | No `FastTrackUITests/` directory exists. | new directory | L |
| I-2 | `DriveManager.startRecording` / `stopRecording` / `pb060DriveId` / `pbTopSpeedDriveId` / `refreshAchievementsFromServer` are untested. | `FastTrackTests/` (new) | M |
| I-3 | No 401/403/timeout/JSON-decode-failure tests for any `APIService` call. | `FastTrackTests/` (new) | M |
| I-4 | No route-parsing edge-case tests (empty `routeData`, malformed JSON, missing `v` key, v2 with no `points`, unknown event types). | `FastTrackTests/DriveDetailParsingTests` (new) | S |
| I-5 | `AuthManager` keychain helpers (`keychainSave`, `keychainLoad`, `keychainDelete`) and `refreshTokenIfNeeded` are untested. | `FastTrackTests/AuthManagerKeychainTests` (new) | S |
| I-6 | `ProfileManager.restoreFromServer` migration paths (`localIsEmpty` / `serverGarage.isEmpty` branches) are untested and bug-prone (see also 1.12 in stability report). | `FastTrackTests/ProfileRestoreTests` (extend) | M |
| I-7 | `ZeroToSixtyAttempt.init(from:)` custom decoder behavior (id == nil → synthesize, legacy default) is untested. | `FastTrackTests/ZeroToSixtyAttemptTests` (new) | S |
| I-8 | `RouteSerializer.encodeV2` round-trip test uses `try!` and `as!` (`FastTrackTests/RouteSerializerTests:21-32`) — defeats the test's purpose. Use `XCTUnwrap` and explicit casts. | `FastTrackTests/RouteSerializerTests.swift` | S |
| I-9 | `RecordingActor.snapshot()` coalescing boundary (first snapshot always publishes) is not pinned. | `FastTrackTests/RecordingActorTests` (extend) | S |

#### Cluster J: Cert pinning / transport security

| ID | Issue | Files | Effort |
|----|-------|-------|--------|
| J-1 | No certificate pinning. `URLSession.shared` is used everywhere with no `URLSessionDelegate`. A user behind a corporate or state-level MITM proxy with a trusted root CA can intercept all API traffic. The JWT bearer token is sent in plain headers. | `Services/APIService.swift:11` and 4 other files | M |
| J-2 | Server-supplied `avatarURL` is fetched without host allowlist (`UserProfile.swift:299-303`). Validate against `fast.toper.dev` and `lh3.googleusercontent.com` etc. before fetching. | `Models/UserProfile.swift:299-303` | S |
| J-3 | `URLQueryItem` injection: `carMake.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)` allows `&` and `=` in values (`APIService.swift:294-299, 346`). | `Services/APIService.swift:294-299, 346` | S |
| J-4 | Sign-out does not call a server `POST /auth/logout` to revoke the JWT. Currently relies on natural server-side expiry. | `Services/AuthManager.swift:71-76` | S-M |
| J-5 | Sign-in callback raw server error body is shown to the user (`GoogleSignInManager.swift:88-91`). Show a generic message, log details via `os.Logger`. | `Services/GoogleSignInManager.swift:88-91` | S |
| J-6 | No 401 interceptor. A 401 response silently leaves the user in an authenticated-UI-but-failing-API state. Add a `URLSessionTaskDelegate` that triggers `signOut()`. | `Services/APIService.swift` and `Services/AuthManager.swift` | M |

### 4.3 P2 — Quality / consistency

| ID | Cluster | Issue | Files | Effort |
|----|---------|-------|-------|--------|
| P2-1 | D | `processLocation` heading & brake thresholds applied after clamp to ±5g (`DriveManager+Processing.swift:118`). Add comment. | `ViewModels/DriveManager+Processing.swift:118-128` | S |
| P2-2 | D | `SpeedColor.color(for:)` is purely color — when shown as text the numeric value carries the info, OK. No fix. | — | — |
| P2-3 | D | `CarStatsManager` `@Published carStats` invalidates every observer on any per-car change. Coalesce writes. | `Models/CarStats.swift:54` | M |
| P2-4 | E | `RouteDecimator` allocates a `[Bool]` of `points.count` per call. Use `UInt8` bitset or `Set<Int>`. | `ViewModels/RouteDecimator.swift:19` | S |
| P2-5 | E | 4× real-time drive playback in `DriveDetailView` is documented but jarring. Expose speed control. | `Views/DriveDetailView.swift:519` | S |
| P2-6 | E | `parseZeroToSixtyAttempts.nearestIndex` is O(attempts × points) on appear. Build `[TimeInterval: Int]` index once. | `Views/DriveDetailView.swift:738-750` | S |
| P2-7 | E | `Drive.swift:309-313` `Equatable` for `CLLocationCoordinate2D` only compares lat/lng, not altitude. Document contract. | `Models/Drive.swift:309-313` | S |
| P2-8 | C | Avatar `UIImage` (`UserProfile.swift:154`) lives in memory forever. Decode on demand. | `Models/UserProfile.swift:154` | S |
| P2-9 | G | No haptics on "Start Drive" button. Add medium impact via `sensoryFeedback`. | `Views/ContentView.swift:209-230` | S |
| P2-10 | B | 0.8s pulse around Start button runs forever while recording, even on other tabs or backgrounded. Gate on reduce-motion and pause when not visible. | `Views/ContentView.swift:236-241` | S |
| P2-11 | H | `AppStoreScreenshotMode.swift:97` mutates `carStats` singleton from outside. Acceptable in DEBUG; document. | `AppStoreScreenshotMode.swift:97` | S |
| P2-12 | E | `LiveActivity` start is not surfaced if `areActivitiesEnabled` is false. Wrap in `try?` + log. | `ViewModels/DriveManager+LiveActivity.swift:8-26` | S |
| P2-13 | E | `UserProfile.swift:340` uses `urls(...)[0]` — Apple guarantees non-empty on iOS, but use `.first` + `guard let`. | `Models/UserProfile.swift:340` | S |
| P2-14 | F | `AppStoreScreenshotMode.swift` exists. Verify it's not shipped to release. | `AppStoreScreenshotMode.swift` | S |
| P2-15 | C | Drive history / garage list rows aren't `Equatable` (overlaps with D-10). | 4 files | S |
| P2-16 | F | Privacy toggle (public/private profile) persists silently with no feedback. | `Views/ProfileView.swift:302-318` | S |

### 4.4 P3 — Nits

(47 P3 items catalogued in the full audit; full list in the cluster summaries above. Examples: stray `<` glyph in `DriveManager.swift:276` comment, duplicate `// MARK: - Main Profile View` in `ProfileView.swift:4-5`, `addCar` celebration not gated on reduce-motion, `parseRouteData` v3 schema not surfaced as a log, etc.)

## 5. Design — Sequenced Workstreams

Implementation is **not** a single PR. The workstreams below are sequenced so each is shippable independently and roughly ordered by impact-to-effort ratio. Each workstream will get its own plan via the `writing-plans` skill before code is written.

### Workstream 1: P0 sweep (1 PR)
**Items:** P0-1, P0-2, P0-3.
**Goal:** Fix the three blockers. Small surface area, ~half a day total.
**Verification:** Tests for `CarStats` PB lookup with the corrected `?? 0` removal; manual drive + map render perf check; OAuth state CSRF regression test.

### Workstream 2: Recording drive loss (1 PR)
**Items:** A-1, A-2, A-3, A-4.
**Goal:** Make it impossible to lose a recorded drive.
**Design notes:**
- Persist in-flight `routeData` to a temp file on `stopRecording` start; if `createDrive` fails, leave the file and re-upload on next app launch.
- Add a `lastError: APIError?` `@Published` to `DriveManager` and a toast/alert path.
- Sign-out path: if `driveManager.isRecording`, `stopRecording` first (with persistence) before clearing local data.
- `LocationManager` exposes `authorizationStatus`; `DriveManager.startRecording` refuses to start unless `.authorizedAlways` (or the new `requestWhenInUse` flow per B-1).
**Verification:** Network failure injection (404, 500, timeout) → drive persisted → re-upload on next launch. Sign-out while recording → drive persisted.

### Workstream 3: Location permission / App Review (1 PR)
**Items:** B-1, B-2, B-3, B-4.
**Goal:** Pass App Review and reduce always-on exposure.
**Design notes:**
- New permission flow: `requestWhenInUse()` on first launch; `requestAlways()` on first recording start (the first time the user taps Start, not via a separate Settings toggle).
- `allowsBackgroundLocationUpdates = true` set inside `startUpdatingLocation`, off inside `stopUpdatingLocation`.
- Privacy manifest: add `NSPrivacyCollectedDataTypeEmail` and `NSPrivacyCollectedDataTypeUserID`.
- `baseURL` driven by a build configuration (`.xcconfig` or `#if DEBUG` branch) with the existing value as the default.
**Verification:** Manual reinstall; first-launch prompts WhenInUse; first recording prompts Always. TestFlight review.

### Workstream 4: Design system — token additions & swaps (1-2 PRs)
**Items:** C-1, C-2, C-3.
**Goal:** Add `Radius` enum, `FTFont` style enum, missing `Color.ft*` tokens; swap call sites.
**Design notes:**
- `enum Radius { static let xs = 4, sm = 8, md = 10, lg = 12, xl = 14, xxl = 18 }`.
- `enum FTFont { static let gaugeNumber = Font.system(size: 32, weight: .bold, design: .monospaced); static let pill = Font.system(size: 9, weight: .bold); /* ... */ }`. Most fixed-point sites migrate to relative `.caption`, `.footnote`, etc. with `@ScaledMetric` and `.minimumScaleFactor`.
- New color tokens: `Color.ftShimmer`, `Color.ftScrim`, `Color.ftRankGold/Silver/Bronze`, `Color.ftOnDarkDivider`, `Color.ftHairline`, `Color.ftSkeleton`, `Color.ftPB060Tint`, `Color.ftPBTopSpeedTint`.
- Migration is mechanical (one token per literal). 100+ sites; bundle into 1-2 PRs by view file.
**Verification:** Visual diff of every screen; Dynamic Type scaling test on iPhone SE (smallest), Pro Max (largest).

### Workstream 5: Design system — component consolidation (1 PR)
**Items:** C-4, C-5, C-6, C-7, C-8.
**Goal:** Consolidate the duplicated components.
**Design notes:**
- One `Gauge` family: `Gauge.hero`, `Gauge.compact`, `Gauge.statCell`. Replace `DashboardGauge`, `MetricGauge`, `CarDetailGauge`, `PublicCarDetailGauge`. The 14 vs 12 corner-radius discrepancy is the most visible inconsistency and gets resolved here.
- One `CarPhotoThumbnail(photoURL:size:)` in `Components/`. `CarPhotoView` made flexible enough for tiny sizes.
- One `FollowButton(isFollowing:isLoading:action:)` in `Components/`. One `UserRow(avatar:primary:secondary:trailing:)`.
- One `BadgePill(text:icon:style:)` with cases `.pb060, .pbTopSpeed, .current, .selected, .carChip`.
- One `StatsGrid(cells:)` for the 2×2 grid pattern (8+ sites).
- Migrate hand-rolled empty states to `ContentUnavailableView`.
**Verification:** Visual diff; ensure all variants of each pattern are exercised (own profile, public profile, garage, drive history).

### Workstream 6: Hot-path performance (1-2 PRs)
**Items:** D-1, D-2, D-3, D-4, D-5, D-6, D-7, D-9, D-10, D-11, D-13, D-14, D-15.
**Goal:** Cut the recording-UI cost roughly in half.
**Design notes:**
- IMU callback runs on a dedicated `OperationQueue`; only the `@Published` write hops to main.
- Maintain `runningDistanceMeters` incrementally; drop the O(n) loop in `updateCurrentDrive` and `stopRecording`.
- Drop `recordingLocations` (or keep only a debug opt-in); keep `richRoutePoints` as the single source of truth.
- Configure `URLCache` to 50 MB / 250 MB; introduce a shared `RemoteImage` view that uses it.
- Switch `createDrive` to send the inner `routeData` JSON as a single field (additive only — keep the existing field, add `route_data_v2` that the server can ignore if not present).
- `parseRouteData` runs in a `Task.detached`.
- Add `Equatable` to row views.
- D-8 (`processHeadingBackground`) is **kept and wired up**: the drive summary view surfaces left/right turns and lane changes, so the heading detection path must be active. Move heading state into `RecordingActor` (consolidate with the running-speed-stats pattern) and ensure turn/lane-change counts flow into `Drive` on stop.
**Verification:** Profile-in-Instruments time-since-start, frame-time instruments trace during a 10-minute drive, network payload size before/after.

### Workstream 7: Stability & concurrency (1-2 PRs)
**Items:** E-1, E-2, E-3, E-4, E-5, E-7, E-8, E-9, E-10, E-11, E-12, E-14, E-15.
**Goal:** Eliminate the implicit-main-actor and `fatalError` landmines; resolve the dead `processHeadingBackground` (covered by D-8).
**Design notes:**
- Sign-in managers: emit `error` instead of `fatalError`.
- Decide `DriveManager` actor-isolation strategy: either `@MainActor` class with `nonisolated` heavy math, or move recording state into a dedicated `DriveRecordingState` actor.
- `AuthManager`: `@MainActor` with `nonisolated` keychain accessors.
- Force-unwrap cleanup pass.
- `LiveActivity` update task coalescing.
**Verification:** Swift 6 strict-concurrency compile check on a branch; crash test of multi-scene sign-in; concurrent test exercising `processLocation` / `processSpeedSample` interleavings.

### Workstream 8: UX silent failures & toasts (1 PR)
**Items:** F-1, F-2, F-3, F-4, F-5, P2-16.
**Goal:** No silent failures. Every async action has visible success/failure feedback.
**Design notes:**
- New `Toast` component (snackbar at bottom) with action affordance.
- Follow/unfollow errors → toast.
- Notifications mark-read errors → toast; fetch errors → banner above list.
- Delete-drive: toast with "Undo" (iOS 17+ `Text("Undo")` pattern).
- Privacy toggle: brief confirmation toast.
**Verification:** Manual: force a network failure for each flow and confirm the toast appears.

### Workstream 9: Accessibility (1 PR)
**Items:** G-1, G-2, G-3, G-4, G-5, P2-9, P2-10.
**Goal:** Pass basic accessibility audits.
**Design notes:**
- `@Environment(\.accessibilityReduceMotion)` guards on the 4 infinite-loop animations.
- Add `accessibilityLabel` / `accessibilityValue` to map annotations, GPS status dot, speed hero ring, avatar tap-zoom.
- Notifications bell frame → 44pt; follow button frame → 44pt.
- Dynamic Type migration (overlaps with C-2).
- Increase contrast on the `Color.secondary.opacity(0.5)` site.
**Verification:** VoiceOver walkthrough of every tab; Dynamic Type walkthrough on largest and smallest settings; reduce-motion enabled.

### Workstream 10: Architecture (large-file split + DI) (2-3 PRs)
**Items:** H-1, H-2, H-3, H-4, H-5, H-6, H-7, H-8, H-9, H-10.
**Goal:** No file over ~500 lines. Consistent DI.
**Design notes:**
- Split `DriveManager` into `DriveRecordingController` + `LiveActivityCoordinator` + `DrivePoller`. Move `RouteSerializer` orchestration to a free function.
- Split `CarDetailView` and `DriveDetailView` into focused sub-views; keep one public surface area.
- Move `StatInfo` glossary to a JSON resource.
- Pick one DI pattern: convert all managers to environment-injected (no singletons). This future-proofs the app for any feature that needs per-screen or per-tab state and makes every manager unit-testable without a global. This bumps Workstream 10 effort from L to XL. The `preview()` instances already in the codebase are a useful starting point.
- Extract shared car-stats derive logic.
- Split `Achievement.swift` into `AchievementModel`, `AchievementManager`, `AchievementCatalog`.
- Make `RecordingActor` `Sendable` explicit.
**Verification:** File-line count check (CI lint or pre-commit); test suite still green after each split.

### Workstream 11: Test coverage (continuous; 1 catch-up PR)
**Items:** I-1 through I-9.
**Goal:** New test files for the gaps; bring coverage of `DriveManager` recording paths from 0% → reasonable.
**Design notes:**
- Add `FastTrackUITests/` with one happy-path sign-in test and one record-drive test (uses the in-process test target, not a real backend).
- `DriveManagerTests` for `startRecording` / `stopRecording` / `pb060DriveId` / `pbTopSpeedDriveId` / `refreshAchievementsFromServer`.
- `APIServiceErrorTests` for 401/403/timeout/decode-failure paths.
- `RouteParsingTests` for empty / malformed / missing-`v` / unknown-event-type.
- `AuthManagerKeychainTests`.
- Extend `ProfileRestoreTests` for the migration branches.
- `ZeroToSixtyAttemptTests`.
- Fix `RouteSerializerTests` to use `XCTUnwrap`.
- Extend `RecordingActorTests` for the coalescing boundary.
**Verification:** Code coverage report; CI green.

### Workstream 12: Transport security (1 PR, after Workstream 3)
**Items:** J-1, J-2, J-3, J-4, J-5, J-6.
**Goal:** Defense-in-depth on the network layer.
**Design notes:**
- `URLSessionDelegate` that pins the leaf cert for `fast.toper.dev` (pin the SPKI, not the cert, to allow rotation).
- Allowlist hosts for server-supplied `avatarURL` (allow `fast.toper.dev`, `lh3.googleusercontent.com`).
- Use `URLQueryItem` for `carMake` and search queries.
- Sign-out calls server `POST /auth/logout` (additive — the existing `clearTokens` stays as a fallback).
- Generic error message on sign-in failure; details in `os.Logger`.
- 401 interceptor triggers `signOut()` and a "Session expired" toast.
**Verification:** Pinning test (rejects MITM proxy); allowlist test; server-logout test.

## 6. Phasing

Recommended execution order, each row a "release":

| Release | Workstreams | Cumulative effort | Notes |
|---------|-------------|-------------------|-------|
| R1 (this week) | 1: P0 sweep | S | No design dependency. Ship in one PR. |
| R2 | 2: Recording drive loss, 3: Location permission / App Review | M + S | User-visible bug + App Review risk. Both ready to implement in parallel branches. |
| R3 | 4: Design system tokens, 9: Accessibility | M + S | Both are visual; do together to avoid two visual diff passes. |
| R4 | 5: Design system component consolidation, 8: UX silent failures | L + M | Both touch view files; coordinate. |
| R5 | 6: Hot-path performance, 7: Stability & concurrency | M + M | Recording path is sensitive; do them sequentially, performance first. |
| R6 | 12: Transport security, 10: Architecture | M + L | Architecture split happens last to avoid premature restructuring. |
| R7 (continuous) | 11: Test coverage | M-L | Add tests in each PR; catch-up PR for the gap. |

## 7. Resolved Decisions

1. **D-8 (`processHeadingBackground`)**: keep and wire up. The drive summary view surfaces left/right turns and lane changes; the heading detection path is a real feature. Heading state moves into `RecordingActor` (consolidate with the running-speed-stats pattern).
2. **H-5 (DI)**: full environment injection for all managers (no singletons). Future-proofs per-screen/per-tab state needs and makes every manager unit-testable. Bumps Workstream 10 effort from L to XL.
3. **P0-1 (`?? 0` cleanup)**: confirmed `Drive` fields are non-optional — drop the `?? 0` in `CarStats.swift`. If the file currently compiles, the `Drive` field declarations need a follow-up read in the implementation branch.
4. **B-1 UX**: prompt for Always on the user's first recording start (not via a separate Settings toggle).
5. **J-4 (server logout)**: in scope. The `POST /auth/logout` endpoint is in this repo and we own the deployment.

## 8. What is intentionally not changing

- The `RecordingActor` global-actor pattern (it is correct as designed).
- The route format v1/v2 fallback in `DriveDetailView.parseRouteData` (additive compat for old server payloads).
- The `Codable` additive patterns in `Drive.init(from:)` and `User.init(from:)`.
- The `FollowListView` factoring in `FollowersListView.swift` (exemplary).
- The `CarPhotoView` centralization.
- The Keychain accessibility class (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
- The HTTPS-only transport and absence of ATS exceptions.
- The `Secrets.swift` gitignore + template placeholder pattern.

These are working as designed. Don't refactor them.

## 9. Verification

For each workstream, before merge:
- `cd backend && CGO_ENABLED=1 go vet ./...` and `go test ./... -v -timeout 60s` (only if backend touched).
- `xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`.
- `xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack -destination "platform=iOS Simulator,name=iPhone 17 Pro" CODE_SIGNING_ALLOWED=NO`.
- For UI-touching workstreams: `bundle exec fastlane test`.
- For workstreams 2, 6, 7: manual drive-record-stop cycle on a real device (backgrounding the app mid-drive, signing out mid-drive, killing the app mid-upload).
- For workstream 12: MITM proxy test against the pinned endpoint.

## 10. Out-of-Scope

- Backend API changes (any non-additive).
- New features or screens.
- iPad-specific work.
- App Store / TestFlight submission mechanics (cutover plan for any breaking change is the user's call).
- Migrating to a different architecture (e.g. TCA) — too speculative for this pass.

---

## 11. Release notes

### R4 (2026-06-11) — Workstreams 5+8 — SHIPPED via PR #93

**What landed:** Component consolidation (Workstream 5) and error/toast feedback (Workstream 8).

**C-4 — Gauge consolidation**: `FTGauge` (`.hero` / `.compact` / `.statCell`) replaces `DashboardGauge`, `MetricGauge`, `CarDetailGauge`, `PublicCarDetailGauge`. 9 call sites migrated, 2 files deleted. Standardized corner radius on 12.

**C-4b — CarPhotoView thumbnail**: Added `size: CGFloat?` parameter. Thumbnail mode swaps gradient+initials placeholder for car-icon. 3 call sites migrated.

**C-5 — UserRow**: Generic `UserRow<Avatar, Primary, Secondary, Trailing>` with `@ViewBuilder` closures, extracted from 3 view files.

**C-6 — BadgePill**: 6 styles (`.you`, `.selected`, `.pb060`, `.pbTopSpeed`, `.carChip`, `.count`). 5 view files migrated. The `ProfileView` "SELECTED" rounded-rect was intentionally **not** migrated (visual treatment differs by design).

**C-7 — ContentUnavailableView**: 4 hand-rolled empty states replaced (CarDetailView sparkline, GarageView garage, RecentAchievementsStrip, PublicCarDetailView stats).

**C-8 — StatsGrid**: Generic `StatsGrid<Content>` wrapper for 2-flexible-column `LazyVGrid`. 16 call sites migrated.

**F-5 — Toast**: `ToastManager` (singleton `ObservableObject`), `ToastView`, `.toastOverlay()` modifier. Auto-dismiss 3s (4s with action). Wired into `WindowGroup` so it sits above sheets/fullScreenCovers.

**F-1 — FollowButton + follow errors**: New `FollowButton(isFollowing:username:isSelf:onError:)` replaces two private implementations. Errors surface via Toast.

**F-2 — Notification errors**: `NotificationsManager` exposes `@Published lastError`; 5 silent catch blocks (refresh, refreshUnreadCount, loadMore, markRead, markAllRead) now set it. `NotificationsView` observes and toasts.

**F-3 — Delete-drive Undo**: `DriveManager.restoreDrive(_:)` re-uploads a captured `Drive`. 4 delete-drive sites (`CarDetailView`, `GarageView`, `DriveHistoryView`, `DriveDetailView`) enqueue "Drive deleted" toast with Undo action.

**F-4 + P2-16 — Sign-out / privacy**: `ProfileView` shows toast on privacy toggle; sign-out gets confirmation dialog + "Signed out" toast.

**PRs:**
- #90 — R1 (P0 sweep) — MERGED
- #91 — R2 (Recording reliability + Location) — MERGED
- #92 — R3 (Design tokens + Accessibility) — MERGED
- #93 — R4 (Component consolidation + Toasts) — MERGED

**Quality issues caught + fixed during R4:**
- Toast review: sheet overlay placement, `@MainActor` precedent, dead `Equatable` on `ToastMessage` (closures), fragile test sleep. Fixed in `ac9265a` before Task 2.
- UserRow fidelity regression: lost bold-when-unread (notifications) and multi-line secondary (user search). Caught in self-review, fixed by switching `primary`/`secondary` to `@ViewBuilder` closures. Recorded in commit `4a5c515`.
- Lost commits after rebase: `d41b6b2` (FTGauge) and `597818d` (CarPhotoView) were skipped by the rebase because they conflicted with PR #92's design-token swaps. Recovered via `git cherry-pick` from reflog; conflict markers cleaned up in `d506ad7` and `d3cb00c`.

**Verification at merge:**
- `xcodebuild build-for-testing` — passes
- 11 new tests added (Toast, FollowButton, FTGauge, BadgePill, NotificationsManager `lastError`)
- Full suite: 244 passed, 4 pre-existing `*Redesign` source-string regression failures (not introduced here)

---

### R5 (next) — Workstreams 6+7 — Hot-path performance + stability/concurrency

**Scope:** D-1, D-3, D-4, D-7, D-9, D-10, D-11, D-13, D-14, D-15, D-8 (heading detection), E-1, E-3, E-4, E-5, E-7, E-8, E-9, E-10, E-12, E-14, E-2, E-15.

**Excluded from R5** (already addressed by prior workstreams):
- D-12 (background upload) — overlap with R2/Workstream 2.
- E-6 (`processHeadingBackground` actor round-trips) — folded into D-8.
- E-13 (sign-out clears recording) — fixed in R2/Workstream 2 (`cae92f4`).
- E-11 (LiveActivity coalescing) — already implemented in R2/Workstream 2.

**Why not a single PR:** Recording path is sensitive. D-2/D-3/D-4, D-7/D-11, E-2, E-3 all touch `DriveManager`/`APIService`/`RecordingActor`. Strictly parallel sub-branches on those files conflict. We split into tracks that share **no overlapping files**.

**Execution plan — 4 tracks, 2 worktrees, 1 PR per track:**

| Track | Worktree | Scope | Sequence | PR base |
|---|---|---|---|---|
| **A — WS6 perf (recording hot path)** | `feat/ws6-perf` | D-1, D-3, D-4, D-7, D-9, D-10, D-11, D-13, D-14, D-15 | Sequential within track | `main` |
| **B — WS6 heading detection (D-8)** | `feat/ws6-d8-heading` | D-8 + folded E-6 | Standalone, runs concurrent with A/C | `main` |
| **C — WS7 stability (non-recording)** | `feat/ws7-stability` | E-1, E-3, E-4, E-5, E-7, E-8, E-9, E-10, E-12, E-14 | Sequential within track | `main` |
| **D — WS7 actor isolation** | `feat/ws7-actor-isolation` | E-2, E-15 (pinned-cert foundation) | **Last** — after A+B+C merge to a release branch | Release branch |

**Cross-track file-touch map (enforced in plan files):**
- Track A owns: `DriveManager+Processing.swift`, `DriveManager+LiveActivity.swift`, `LocationManager.swift`, `RecordingActor.swift`, `ContentView.swift` (LiveMap region), `DriveDetailView.swift` (parseRouteData), `APIService.swift` (createDrive payload).
- Track B owns: `DriveManager+Processing.swift` (processHeadingBackground block), `Drive.swift` (turn/lane-change counts), `DriveDetailView.swift` (heading surface).
- Track C owns: `AppleSignInManager.swift`, `GoogleSignInManager.swift`, `AuthManager.swift`, `NotificationsManager.swift`, `SocialView.swift:217`, `PublicCarDetailView.swift:113`, `CarPhotoEditorSection.swift:110`, `DriveDetailView.swift:322,328,550-555`, `Drive.swift:309-313` (Equatable), `DriveManager.swift:136`.
- Track D owns: `DriveManager.swift` (actor annotation), `AuthManager.swift` (@MainActor), `APIService.swift` (URLSessionDelegate hook).

A and B both touch `DriveManager+Processing.swift`; they must be merged sequentially (A first, then B rebases onto A's branch). A and B do NOT touch B's `Drive.swift` field changes, so no data-model conflict.

**File-ownership rules in the orchestrator plan:**
- A subagent dispatched to track A may NOT edit files in C's list.
- A subagent dispatched to track C may NOT edit files in A's list.
- Track B is a "sublane" of A: spawned after A's first commit lands locally; B rebases onto A's branch head, not main.

**Operating model for subagents (per the user request "optimize for me to not get involved"):**
- Per-task implementer subagent writes the diff and runs `xcodebuild build-for-testing`. **No per-task spec-compliance or code-quality review subagents** — that's what generated the most user-involvement in R4. One final code review per track before PR.
- Subagents **decide autonomously** on minor design choices (e.g. method signature, test naming) and log the decision in the plan file under a `## Decisions` heading.
- Q's only for **truly blocking** questions: compile errors, conflicting edits, missing API. These go into a `BLOCKING_QUESTIONS.md` file the orchestrator reads at checkpoint boundaries.

**Verification at the end of R5:**
- `xcodebuild build-for-testing` — passes per track.
- `xcodebuild test` — full suite, all 244 prior tests still pass, new tests for the 23 items pass.
- Manual drive-record-stop cycle on a real device (backgrounding, sign-out mid-drive, kill mid-upload) — required by spec §9.
- `fastlane test` for UI-touching items.
- Profiling: Instruments time-since-start + frame-time trace during a 10-minute drive (verifies D-2, D-3, D-4, D-13 outcomes).
- Network payload before/after (verifies D-7).
- Pinning test (verifies D-15 / E-15).

**Risk to manage:**
- D-2, D-3, D-4 stack — all incremental-stat changes. If implemented out of order, intermediate states are corrupt. Plan enforces **D-15 (RecordingActor allocation) → D-4 (runningDistanceMeters) → D-3 (drop redundant arrays) → D-2 (currentDrive copy diff) → D-1 (IMU queue)** order.
- D-8 (heading) is L-sized on its own. Estimated 2-3 sub-tasks. Plan lists them.

**Plans to be created for R5 (one per track):**
- `docs/superpowers/plans/2026-06-12-ios-ws6-perf.md`
- `docs/superpowers/plans/2026-06-12-ios-ws6-d8-heading.md`
- `docs/superpowers/plans/2026-06-12-ios-ws7-stability.md`
- `docs/superpowers/plans/2026-06-12-ios-ws7-actor-isolation.md`

**Orchestrator:** a single subagent that owns the 4 worktrees, dispatches implementer subagents per track, runs the final code review per track, opens the PR, and returns the PR URLs.

---

**End of design.**

**End of design.**
