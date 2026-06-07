# Plan: Issue #64 — Profile, Achievements, Garage, PBs overhaul

**Target issue:** #64 ([jxt1009/fastpass#64](https://github.com/jxt1009/fastpass/issues/64)) — "Improve achievements section and profile tab view"
**Plus:** leaderboard "You" marker bug (car-centric leaderboard → up to 3 rows per user, marker only highlights one)
**Date:** 2026-06-07
**Status:** Approved, in execution
**Style:** additive-only API, additive-by-default migrations, worktrees per AGENTS.md, conventional commits, branch off latest `main`

## 0. Summary of decisions

| Question | Decision |
|---|---|
| Scope | Full phased rollout: Phase 1 (quick wins) → Phase 2 (garage + per-car PBs) → Phase 3 (notifications + avatar crop) |
| Reactions bullet | Skip (no code change). Reactions don't exist in the codebase, so there's no "currently unavailable" UI to remove. Close the bullet as informational. |
| Follower notifications | In-app feed only, no APNs. Server-side event store, polled endpoint, iOS feed view. APNs can come later as its own track. |
| Garage shape | NavigationLink pushed destination from a "View Garage" button in the profile garage section. New `GarageView` (own) and `CarDetailView` (one per car). |
| Per-car PBs data | Reuse `CarStats` blob (no new table, no migration). "Liven it up" — showy polish (radial gauge, sparkline, hero photo, animations, confetti on new PB). |
| Avatar crop | Full pan/zoom crop UI after `PhotosPicker`, fixed 1:1 aspect, upload via existing `PUT /profile/avatar`. |
| Public SPA | Keep public-only. No Svelte changes. |
| Uncommitted work in main | Leave alone. All work happens in fresh worktrees off latest `main`. |
| Leaderboard "You" marker | Compare `entry.userId == currentUserId` (not `carId == selectedCarId`). Add `id: Int?` to `UserProfile` populated from `serverUser.id`. |

## 1. What's already shipped (so we don't redo it)

Per `2026-06-06-leaderboard-cars-profile-nav-redesign.md`, PR 4 of the in-flight redesign plan already landed (`7573c89 feat(ios): redesign public and own profile with narrow header, garage, zoom`). It covers:
- ✅ Tap avatar → `AvatarZoomView` (own + public)
- ✅ Public profile garage section with photos + short stats (`PublicGarageCard`)
- ✅ Own profile mirrored with the same redesign
- ✅ Top stat bar reordered to Top Speed / 0-60 / Total Distance

So this plan picks up where that left off.

## 2. Phased tracks

All worktrees branch off `origin/main` and follow the `git fetch origin main && git rebase origin/main && git push --force-with-lease` rhythm from `AGENTS.md`.

```
Phase 1 (parallel, 4 tracks, no inter-deps) ─────────────────────────────────
  Track A: leaderboard You-marker fix           (1 PR, multiple files)
  Track B: PB top-speed History marker          (1 PR, multiple files)
  Track C: profile layout reorder + achievements surfacing (1 PR, multiple files)
  Track D: reactions no-op grep + close-out note in plan (no PR; just a doc check)
       │
       └─► rebase + merge all → main
              │
Phase 2 (parallel, 2 tracks; Track E may need Track F for backend first)
  Track E: garage as its own view + CarDetailView (iOS, 1-2 PRs)
  Track F: per-car PBs surfacing in CarDetailView (iOS, included in E; no backend needed — CarStats blob already exists)
       │
       └─► rebase + merge → main
              │
Phase 3 (parallel, 3 tracks)
  Track G: backend notifications (server + migration, 1 PR)
  Track H: iOS notification feed view + polling (1 PR, after G merges)
  Track I: avatar crop UI (iOS, 1 PR, independent)
```

Tracks inside a phase can run in parallel. Phases are sequential because the plan artifacts need to land in order (Phase 1's plan is the foundation, Phase 2 expands it, Phase 3 builds on the new layouts).

### 2.1 Why this parallelizes well

- **No shared file edits inside a phase.** Track A touches `SocialView.swift`; Track B touches `DriveHistoryView.swift` + `DriveManager.swift`; Track C touches `ProfileView.swift`; Track D is grep-only.
- **No backend in Phase 1.** No coordination with the shared Postgres, no migrations, no schema risk.
- **CarStats blob is read-only data in Phase 2.** We don't add tables; we just render the existing JSON.
- **Notifications backend (Track G) is self-contained.** New table + endpoints. iOS feed (Track H) depends only on G merging first.

## 3. Phase 1 — Quick wins (no backend)

### Track A — Leaderboard "You" marker fix
**Issue:** `SocialView.swift:151-152` matches on `carId == selectedCarId`. With the car-centric leaderboard, a user has up to 3 rows, so only the row matching their currently-selected car gets the "You" badge.

**Files:**
- `ios/FastTrack/FastTrack/Views/SocialView.swift:151-152` — change predicate
- `ios/FastTrack/FastTrack/Models/UserProfile.swift:59-89` — add `let id: Int?` to `UserProfile`
- `ios/FastTrack/FastTrack/Models/UserProfile.swift:242-273` — populate `id` from `serverUser.id` in `restoreFromServer`
- `ios/FastTrack/FastTrack/Models/SocialModels.swift:11` — `LeaderboardEntry.userId: Int` already exists, no change
- Tests: `FastTrackTests/ProfileRedesignTests.swift` (or new `LeaderboardYouMarkerTests.swift`) — add `testIsCurrentUserRow_MatchesByUserIdNotCarId` and a snapshot-style test that 3 rows for the same userId all light up.

**Plan:**
1. In `SocialView`, replace:
   ```swift
   let isCurrentUserCar = entry.carId != nil
       && entry.carId == currentSelectedCarId
   ```
   with a call to a pure helper that does the nil-guard properly (extracted for testability — `entry.userId` is `Int` while `profileManager.profile?.id` is `Int?`, so the predicate needs an explicit unwrap, not a `&&` against an optional):
   ```swift
   let isCurrentUserRow = LeaderboardYouMarker.isCurrentUser(
       entry: entry,
       currentUserId: profileManager.profile?.id
   )
   ```
   with the helper defined as a small, unit-testable free function (in `Models/LeaderboardYouMarker.swift` or alongside `SocialModels.swift`):
   ```swift
   enum LeaderboardYouMarker {
       static func isCurrentUser(
           entry: LeaderboardEntry,
           currentUserId: Int?
       ) -> Bool {
           guard let currentUserId else { return false }
           return entry.userId == currentUserId
       }
   }
   ```
2. Rename the prop on `LeaderboardRow` from `isCurrentUserCar` to `isCurrentUserRow` (one-line rename — the existing badge/background logic is correct, just wrongly scoped).
3. In `UserProfile`, add `let id: Int?` (optional, decode-if-present from `User.id`). Backward-compatible — old client/server data without `id` decodes fine.
4. In `ProfileManager.restoreFromServer`, set `id: serverUser.id` when building the restored `UserProfile`.

**Acceptance:**
- A user with 3 cars sees "You" on all 3 of their leaderboard rows in every category and every period.
- Tapping any of those 3 rows opens their own `PublicProfileView` (which is already gated to hide the follow button when `isOwnProfile`).
- No regressions in the existing `ProfileRedesignTests`.

**Worktree:** `.worktrees/ios-leaderboard-you-marker` → branch `fix/ios-leaderboard-you-marker`

**Commit/PR:** `fix(ios): mark all of the current user's rows on the car-centric leaderboard`

### Track B — Top-speed PB History marker
**Issue:** Per the PR 4 plan, only the 0-60 PB has a yellow row + trophy pill in `DriveHistoryView`. The user wants the same treatment for top-speed PBs.

**Files:**
- `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift:353-373` — add `pbTopSpeedDriveId: Int?` (mirror of `pb060DriveId`)
- `ios/FastTrack/FastTrack/Views/DriveHistoryView.swift:65-110` — extend `DriveRowView` with `isPersonalBestTopSpeed: Bool = false`, render a second pill (red `flame.fill` + "PB Top Speed") when true
- `ios/FastTrack/FastTrack/Views/DriveHistoryView.swift:23-33` — pass both flags into `DriveRowView`, tint the row background to match
- Tests: `FastTrackTests/DriveCalculationTests.swift` or a new `PersonalBestsTests.swift` — `testPBTopSpeedDriveId_PrefersCenturyClubSourceDrive`, `testPBTopSpeedDriveId_FallsBackToLocalScan`

**Plan for the precedence rule** (mirror the 0-60 rule from `DriveManager.swift:353-373`):
1. Server-authoritative `speed_150` (150 mph) source drive — take its `sourceDriveId`.
2. Server-authoritative `speed_100` (100 mph, "Century Club") source drive — same precedence (fallback when no `speed_150` unlock exists).
3. Fallback: most recent drive whose `maxSpeed == MAX(maxSpeed)`.

The "showy" requirement applies here too — the pill should animate in (a small springy entry) when the row is the new PB.

**Acceptance:**
- The drive with the all-time `MAX(maxSpeed)` is highlighted with a red "PB Top Speed" pill + a row background tint (different from yellow so both PBs can show together on the same drive).
- A drive that holds both PBs shows both pills.
- Tests pass.

**Worktree:** `.worktrees/ios-pb-top-speed-marker` → branch `feat/ios-pb-top-speed-marker`

**Commit/PR:** `feat(ios): highlight top-speed personal best in drive history`

### Track C — Profile layout: surface achievements up; consolidate analytics overlap
**Issue:** Achievements are still tucked in the lower part of the profile (line 89 of `ProfileView.swift`). The user wants them more prominent, and notes that Analytics and Achievements overlap.

**Files:**
- `ios/FastTrack/FastTrack/Views/ProfileView.swift:70-95` — reorder the VStack
- `ios/FastTrack/FastTrack/Views/ProfileView.swift:512-554` — extend the achievements card to a richer summary (a horizontal scroll of recent unlocks with cover photos) — keep "View All" link
- New: `ios/FastTrack/FastTrack/Views/Components/RecentAchievementsStrip.swift` — extracted `RecentAchievementsStrip` view (3-5 cards in an HStack)
- New: `ios/FastTrack/FastTrack/Views/Components/AchievementCelebrationCard.swift` — used by Track C and the future Track H (notification → "X just hit sub-6" deep-link)
- Tests: existing `ProfileRedesignTests.swift` should still pass; add `testProfileView_AchievementsSection_PrecedesManeuvers` to lock the order.

**Proposed new order on `ProfileView`:**
1. `profileHeader`
2. **`RecentAchievementsStrip`** ← moved up
3. `garageSection` (with a new "View Garage" button → Phase 2 `GarageView`)
4. `mainStatsGrid`
5. `topSpeedCard`
6. `best060Card`
7. `SectionHeader("Maneuvers")` + `maneuvorsGrid`
8. `TurnPreferenceBar`
9. `SectionHeader("Performance")` + `performanceGrid`
10. `SectionHeader("More Stats")` + `moreStatsGrid`
11. `privacyToggleCard`
12. `SectionHeader("Settings")` + `settingsSection`
13. `deleteAccountButton` + `signOutButton`

The "consolidate analytics + achievements" bullet is addressed in spirit by the strip — the most-glanceable achievement (the latest one) sits right under the header, ahead of the analytics-style stat grid. A future Phase 4 could add a "Trends" card on the profile that surfaces a per-metric mini-trend, but that's out of scope for this issue.

**Acceptance:**
- Achievements section is visible without scrolling on iPhone 15 Pro (verify via snapshot test).
- "View All" still navigates to `AchievementsView`.
- Per-row deep-link to source drive still works (logic unchanged).

**Worktree:** `.worktrees/ios-profile-achievements-surfacing` → branch `feat/ios-profile-achievements-surfacing`

**Commit/PR:** `feat(ios): surface achievements above the fold in profile tab`

### Track D — Reactions bullet close-out
**Issue:** The issue's last bullet is "Reactions are currently unavailable." My read of the codebase shows no reactions code anywhere — no model, no endpoint, no UI, no Svelte component, no migration. The user's answer was "skip — no code change."

**Action:** Grep the repo one more time (defensively) for any string matching reactions-flavored UI text, to be 100% sure there's no stale "Reactions" UI to remove. Run the following from the repo root (uses `rg` / ripgrep; adjust excludes if your checkout adds new vendor trees):
```bash
rg -nI -i -e 'react|emoji|fire|love|thumbs|like' \
  ios/ backend/ website/spa/ docs/ \
  -g '!ios/Pods' -g '!*.lock'
```
If the grep returns no on-screen text, no PR is opened. Mention in the closing comment of the issue that the bullet is informational; reactions are not in scope for #64 and would be a follow-up issue if prioritized.

**Worktree:** none (no code change).
**PR:** none.

## 4. Phase 2 — Garage as its own view + showy per-car detail

### Track E — GarageView (pushed destination) + CarDetailView (per-car)

**Files (iOS):**
- New: `ios/FastTrack/FastTrack/Views/GarageView.swift` — full-screen pushed `GarageView`
  - Header: "Your Garage" + a single big "Add Car" button
  - Body: a `LazyVGrid` (2-column on iPhone, 3-column on iPad) of `GarageCarCard` rows. Each row: hero photo (160pt), nickname (large), make/model, total drives, total distance, top PB.
  - Re-uses the existing `CarGarageCard` styling for cards (or a richer variant)
  - Tapping a card pushes `CarDetailView`
  - Re-uses the existing `EditCarView` and `AddCarView` sheets (no new add/edit flows)
- New: `ios/FastTrack/FastTrack/Views/CarDetailView.swift` — showy per-car detail
  - Inputs: `let car: UserCar`
  - **Hero section**: full-width photo, year/make/model/trim overlay, nickname. If no photo, a "gradient" placeholder with the car's initials.
  - **PB hero numbers** (showy, the centerpiece): two big `MetricGauge` cards side-by-side
    - Top Speed (large numeric, radial gauge arc) with the source drive name as subtitle ("Set on May 14")
    - Best 0-60 (large numeric, radial gauge arc) similarly
  - **Sparkline**: a `Chart` (SwiftUI Charts, already used by `AnalyticsView`) showing this car's per-drive `maxSpeed` over the last N drives, with the PB point highlighted
  - **0-60 histogram** (optional in this PR; minimal first version is fine)
  - **Driving style badge**: computed from this car's drives — `Sporty` / `Smooth` / `Balanced` based on brake-events-per-mile
  - **Stats grid** (the existing `CarStatsRow` lifted to the page level)
  - **PB list**: any unlocked achievements that came from a drive using this car (`sourceDriveId` joined with `drive.carId`), with a "View Drive" deep-link
  - **Confetti animation** on first appear if this car has a new PB that was unlocked in the last 7 days (lightweight `ConfettiView` from `SharedComponents.swift`, gated on the newness check — does not fire on every open)
- New: `ios/FastTrack/FastTrack/Views/Components/MetricGauge.swift` — a radial gauge variant (extending the existing `MetricGauge` in `SharedComponents.swift`)
- Modified: `ios/FastTrack/FastTrack/Views/ProfileView.swift:255-302` — add a "View Garage" `NavigationLink` to the garage section header next to the `+` button
- Tests:
  - `FastTrackTests/ProfileRedesignTests.swift` — add `testGarageView_RendersAllCars` and `testCarDetailView_HeroShowsNicknameAndMakeModel`
  - New `FastTrackTests/CarDetailTests.swift` for the per-car analytics: `testCarDetail_DrivingStyle_BrakeEventsThreshold`, `testCarDetail_SparklineData_UsesOnlyThisCar`

**Data sources (all already in the codebase):**
- `CarStats` for the per-car aggregate (`Models/CarStats.swift:6-47`)
- `driveManager.drives.filter { $0.carId == car.id }` for the sparkline + style badge
- `AchievementManager.shared.achievements.filter { /* joined to this car via a source drive */ }` for the PB list

**No backend changes. No new table. No migration.**

**Acceptance:**
- From the own profile, "View Garage" pushes a full GarageView listing all cars.
- Tapping a car pushes CarDetailView with hero, gauges, sparkline, and stats.
- The sparkline animates in.
- The confetti fires once per car per PB-newer-than-7-days (no infinite spam).

**Worktree:** `.worktrees/ios-garage-car-detail` → branch `feat/ios-garage-car-detail`

**Commits/PRs (split if > 600 lines):**
- `feat(ios): promote garage to its own view with grid of cars` (GarageView + the Profile button)
- `feat(ios): add per-car detail view with hero, gauges, and sparkline` (CarDetailView)

### Track F — Per-car PBs in the public garage (leaderboard profile overview)
**Issue:** "The garage summaries should also be accessible (albeit a bit more minimal) in the user's profile overview in the leaderboard area."

The PR 4 work already added `PublicGarageCard` in the public profile. This track is the minimal polish:
- The existing `PublicGarageCard` is fine. Add one small "Tap to view" chevron hint, and link the public card to a public `PublicCarDetailView` (read-only, no confetti, no edits).

**Files:**
- `ios/FastTrack/FastTrack/Views/PublicGarageCard.swift:12-45` — wrap the card in a `Button` that calls `onTap`
- New: `ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift` — read-only twin of `CarDetailView` (same layout, but no edit/confetti, no driving-style badge)

**No backend changes. The `PublicProfile` already carries `carStatsData` and `garage` additively.**

**Acceptance:**
- A public profile visitor can tap a car card to see the full per-car stats.
- "Read-only" — no Add Car, no Edit, no PB celebration.

**Worktree:** `.worktrees/ios-public-car-detail` → branch `feat/ios-public-car-detail`

**Commit/PR:** `feat(ios): add read-only per-car detail on public profile`

## 5. Phase 3 — Engagement (notifications feed + avatar crop)

### Track G — Backend: notification event store + fan-out on PB
**Issue:** "Enable notifications to a users followers when a new personal best for an area is set."

**Decision:** in-app feed only (no APNs). Store events in a new `notifications` table, fan out on PB event, expose via `GET /api/v1/me/notifications`.

**Files (backend):**
- New: `backend/internal/app/notifications.go`
  - `Notification` struct: `ID, UserID, Kind, ActorID, DriveID, AchievementID, Message, ReadAt, CreatedAt`
  - `CreateNotification(tx, userID, kind, actorID, driveID, achievementID, message)` — idempotent (dedupes within a short window)
  - `GetMyNotifications(userID, limit, cursor)` — paginated, newest first
  - `MarkRead(userID, notificationID)`
  - `MarkAllRead(userID)`
  - `UnreadCount(userID)`
  - `FanOutPBNotification(tx, actorID, drive, achievementID, message)` — inserts one row per follower of `actorID`, skipping self
- New: `backend/internal/app/routes_notifications.go` — `GET /api/v1/me/notifications`, `POST /api/v1/me/notifications/:id/read`, `POST /api/v1/me/notifications/read-all`, `GET /api/v1/me/notifications/unread-count`
- New: `backend/internal/app/notifications_test.go` — `TestFanOutPBNotification_SkipsSelfAndDeduplicates`, `TestMarkRead_*`, `TestUnreadCount_*`
- Modified: `backend/internal/app/handlers.go:41-128` (`createDrive` + `updateDrive`) — call `FanOutPBNotification(...)` after `evaluateForUser(...)` returns new unlocks (only for the unlocks flagged `IsPersonalBest`)

**Migration:** `2026060601_add_notifications_table`
```go
{
    version:     "2026060601",
    description: "add notifications table for follower PB events",
    up: func(tx *gorm.DB) error {
        if !tx.Migrator().HasTable(&Notification{}) {
            if err := tx.Migrator().CreateTable(&Notification{}); err != nil {
                return err
            }
        }
        // Index for the per-user feed: "newest first, unread first"
        if err := addIndexByNameIfMissing(tx, &Notification{}, "idx_notification_user_created"); err != nil {
            return err
        }
        return nil
    },
},
```
Additive only — no column changes, no drops, no renames.

**Wire types (additive to `UserAchievement` envelope):**
- `GET /api/v1/me/notifications` returns:
  ```json
  {
    "notifications": [
      {"id": 1, "kind": "pb_set", "actor": {"id": 7, "username": "fastdriver99", "avatar_url": "..."}, "drive_id": 42, "achievement_id": "sub_6_club", "message": "fastdriver99 just hit sub-6 0-60", "read_at": null, "created_at": "2026-06-07T..."}
    ],
    "next_cursor": null,
    "unread_count": 3
  }
  ```
- Existing endpoints (`/me/achievements`, `/drives`, `/users/:username`) are unchanged.

**Acceptance:**
- A user who follows 5 other users and has 0 drives sees `unread_count = 0` and an empty feed.
- After any followed user saves a drive that unlocks `sub_6_club`, the follower sees one new notification within 5 seconds (next poll).
- Tapping the notification deep-links to the actor's `PublicProfileView(username:)` — which the Svelte SPA route also supports, but the iOS app uses its own NavigationLink.

**Worktree:** `.worktrees/notifications-pb-fanout` → branch `feat/notifications-pb-fanout`

**Commit/PR:** `feat(backend): in-app notification feed with PB-event fan-out`

### Track H — iOS notification feed view + polling
**Note on naming:** the iOS model and manager are named `InAppNotification` / `InAppNotificationsManager` to avoid shadowing `Foundation.Notification` (which collides with the same name and is heavily used for `NotificationCenter` foreground/background observers). The HTTP endpoint path stays `GET /api/v1/me/notifications` (no collision server-side, and the Svelte SPA's `notification` type is unaffected — only Swift needs the prefix).
**Files (iOS):**
- New: `ios/FastTrack/FastTrack/Services/InAppNotificationsManager.swift` — `@MainActor ObservableObject` polling the `/me/notifications` endpoint on a 30-second timer (paused when app is backgrounded), exposing `[InAppNotification]` and `unreadCount`
- New: `ios/FastTrack/FastTrack/Models/InAppNotification.swift` — `InAppNotification` struct + `InAppNotificationsResponse` envelope + `InAppNotificationActor` sub-struct
- New: `ios/FastTrack/FastTrack/Views/NotificationsView.swift` — full-screen `List` view of notifications, grouped by day, with an unread badge
- New: `ios/FastTrack/FastTrack/Views/NotificationsBell.swift` — small `bell` icon with a red unread-count badge, rendered in the leaderboard's top-right toolbar (and later, the profile tab)
- Modified: `ios/FastTrack/FastTrack/Services/APIService.swift` — add `fetchNotifications(cursor:)`, `markNotificationRead(id:)`, `markAllNotificationsRead()`, `fetchUnreadNotificationCount()`
- Modified: `ios/FastTrack/FastTrack/Views/SocialView.swift` (or wherever the leaderboard toolbar lives) — add the `NotificationsBell` with badge
- Modified: `ios/FastTrack/FastTrack/FastTrackApp.swift` — inject `InAppNotificationsManager` as an `@StateObject` in `FastTrackApp` and pass via `environmentObject`; start polling on sign-in, stop on sign-out
- Tests:
  - `FastTrackTests/NotificationsTests.swift` — `testInAppNotificationsManager_StopsPollingOnSignOut`, `testInAppNotification_DeepLinkToActorProfile`, `testUnreadBadge_ShowsCountForUnreadOnly`

**Wire contract is purely additive.** Old clients just don't call the new endpoints. New `InAppNotification` model is decodable with `decodeIfPresent` for all fields so any old server returns an empty feed.

**Acceptance:**
- Bell shows on the leaderboard with a red badge when unread > 0.
- Tapping a notification navigates to the actor's `PublicProfileView`.
- Polling pauses when the app is backgrounded (use `UIScene.willEnterForegroundNotification` to restart).

**Worktree:** `.worktrees/ios-notifications-feed` → branch `feat/ios-notifications-feed`

**Commit/PR:** `feat(ios): in-app notification feed with bell badge on leaderboard`

### Track I — Avatar crop UI
**Issue:** "enable the user to view and crop their profile picture."

**Files (iOS):**
- New: `ios/FastTrack/FastTrack/Views/AvatarCropView.swift` — square crop surface with pinch-zoom and pan, fixed 1:1 aspect, "Save" / "Cancel" toolbar
  - Use `UIViewRepresentable` wrapping a `UIScrollView` with `UIImageView` (the standard SwiftUI-crop recipe)
  - On Save: extract a square `UIImage` from the image at the current zoom/pan, run through `resizedForAvatar(maxDimension: 800)`, upload via `ProfileManager.saveAvatar`
- Modified: `ios/FastTrack/FastTrack/Views/ProfileSetupView.swift:24-52` — after `PhotosPicker` selection, push `AvatarCropView` instead of uploading raw
- Modified: `ios/FastTrack/FastTrack/Views/AvatarZoomView.swift:12-62` — add a "Edit" toolbar button (top-leading) that pushes the same `AvatarCropView`
- New: `ios/FastTrack/FastTrack/Views/Components/CropOverlayView.swift` — a dimmed overlay with a circular or square cutout
- Tests: `FastTrackTests/AvatarCropTests.swift` — `testCropExtraction_ProducesSquareImage`, `testCropExtraction_HonorsZoomAndPan` (test the pure function that does the image extraction, not the SwiftUI view itself)

**No backend changes.** Reuse `PUT /profile/avatar`.

**Acceptance:**
- New profile-picture flow: PhotosPicker → AvatarCropView (pinch/pan) → save.
- Existing `AvatarZoomView` gains an "Edit" affordance that opens the same crop view.
- The crop produces a square image with a max edge of 800px JPEG.

**Worktree:** `.worktrees/ios-avatar-crop` → branch `feat/ios-avatar-crop`

**Commit/PR:** `feat(ios): pan/zoom crop UI for profile picture`

## 6. PR/commit matrix

| Phase | Track | Branch | Commit | Notes |
|---|---|---|---|---|
| 1 | A | `fix/ios-leaderboard-you-marker` | `fix(ios): mark all of the current user's rows on the car-centric leaderboard` | iOS only |
| 1 | B | `feat/ios-pb-top-speed-marker` | `feat(ios): highlight top-speed personal best in drive history` | iOS only |
| 1 | C | `feat/ios-profile-achievements-surfacing` | `feat(ios): surface achievements above the fold in profile tab` | iOS only |
| 1 | D | n/a | n/a | grep + issue comment |
| 2 | E | `feat/ios-garage-car-detail` | `feat(ios): promote garage to its own view with grid of cars` + `feat(ios): add per-car detail view with hero, gauges, and sparkline` | iOS only, possibly 2 PRs |
| 2 | F | `feat/ios-public-car-detail` | `feat(ios): add read-only per-car detail on public profile` | iOS only |
| 3 | G | `feat/notifications-pb-fanout` | `feat(backend): in-app notification feed with PB-event fan-out` | Backend, migration `2026060601` |
| 3 | H | `feat/ios-notifications-feed` | `feat(ios): in-app notification feed with bell badge on leaderboard` | iOS only, merges after G |
| 3 | I | `feat/ios-avatar-crop` | `feat(ios): pan/zoom crop UI for profile picture` | iOS only |

All PR titles ≤ 100 chars (commitlint header-max-length). All merges use `--squash`.

## 7. Verification

### Per-track
- **A, B, C, E, F, H, I** (iOS):
  - `xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack -destination "platform=iOS Simulator,name=iPhone 17 Pro" -only-testing:FastTrackTests/<target> CODE_SIGNING_ALLOWED=NO`
  - `bundle exec fastlane test` for the full lane
- **G** (backend):
  - `cd backend && CGO_ENABLED=1 go test ./... -v -timeout 60s -run TestNotifications`
  - `CGO_ENABLED=1 go vet ./...`

### Per-phase
- After all Phase 1 PRs land and `main` is updated, every other worktree rebases (`git fetch origin main && git rebase origin/main`) before starting Phase 2.
- Hand-test on simulator: create a 3-car profile, set PBs across two cars, verify both "You" marker and the per-car PB highlight in history.

### Final smoke
- After all phases, the iOS app supports: car-centric leaderboard with multi-row You marker, top-speed PB history marker, achievements strip on profile, pushed Garage + CarDetail views, public read-only car detail, in-app notification feed with bell badge, avatar crop UI.

## 8. Out of scope (explicit)

- **Reactions feature** — no model, no UI, no backend. Per the user's decision.
- **APNs / push notifications** — in-app feed only. APNs would be a follow-up track.
- **Public Svelte SPA** at `/u/:username` — left unchanged. Per the existing convention.
- **New achievements** for the per-car breakdown — informational only, not tracked server-side. The CarStats blob is the source for per-car PBs.
- **Account-deletion UX changes** — out of scope.
- **Achievements + Analytics true consolidation** — addressed in spirit by the surfacing reorder, but a deep merge of the two screens is out of scope.
- **Migrating legacy garage data** — the existing JSON blob migration already happened in PR 4 of the in-flight plan; we just extend.

## 9. Risks and mitigations

| Risk | Mitigation |
|---|---|
| Car-centric leaderboard bug fixes interact with the in-flight PR 4 rebase | All Phase 1 worktrees start from latest `main`; if PR 4 hasn't merged, wait. Coordinate with the PR 4 owner. |
| CarStats blob out of sync between device + server (existing race in `CarStatsManager.saveCarStats`) | Not in scope to fix; Track E reads from the local blob and the in-memory `driveManager.drives` as fallback. |
| 30s notification polling could be too chatty | Start with 30s on foreground only; revisit with a `Task.sleep` and backoff if battery is a concern. |
| AvatarCropView is the most UI-heavy piece | Pure-function extraction (`testCropExtraction_HonorsZoomAndPan`) keeps the SwiftUI view untested but the math verifiable. |
| The "showy" CarDetailView PR could exceed the 600-line guideline | Pre-commit guard: if the diff is > 600 lines, split into two commits (the Hero/PR-shown PR + the Sparkline/Stats PR). |
| Breaking the additive-only contract | All new types use `decodeIfPresent`; all new fields have safe defaults; no removed or renamed fields anywhere in the plan. |

## 10. Plan artifact

This plan is the work artifact. Track status in this file as PRs land. Update at each phase boundary.
