# Plan: car-centric leaderboard, profile redesign, and nav reorder

**Target issue:** [#57](https://github.com/jxt1009/fastpass/issues/57)
**Date:** 2026-06-06
**Status:** Approved, in execution

## Background

Today the leaderboard groups by user only, so a user with three cars in their
garage shows up as one row attributed to whichever car happened to produce the
aggregate. The period picker only knows "This Week" (Monday-anchored) and "All
Time", the category picker includes a low-value "Total Drives" option, and
`Best 0–60` is buried below `Total Distance` in public profile stats. The
bottom nav puts `Social` last even though it is the discovery surface, and
tapping a user's Followers/Following counts on the public profile is a dead
end. Per-car photos are not possible at all today.

## Goals (from the issue)

1. One user can have multiple leaderboard entries, one per car.
2. Add a "Last 24 hours" timeframe; switch "Week" to a rolling "Last 7 Days".
3. Reorder the top stat bar: Top Speed, 0–60, Total Distance; remove "Total
   Drives".
4. Move Social to the second tab; History and Analytics shift left by one.
5. Improve the public profile: narrow header, garage overview with per-car
   photo and short stats, tappable Followers/Following lists, tap-avatar-to-
   zoom, move Best 0–60 directly under Top Speed in the stats list.
6. Mirror the same improvements on the user's own profile and add per-car
   photo upload in the garage editor.

## Locked decisions

| Question | Decision |
|---|---|
| Per-car photo storage | Add `photo_url: string \| null` to `UserCar` inside the `User.Garage` JSON blob. New `PUT /api/v1/garage/cars/:carId/photo` endpoint mirrors the existing `PUT /api/v1/profile/avatar` pattern. |
| Drive → car grouping | Group by `Drive.CarID`; fall back to `LOWER(TRIM(car_make)) \|\| '\|' \|\| LOWER(TRIM(car_model))` when `CarID` is null. Same key in both leaderboard subquery and the per-user aggregation. |
| Per-user entry cap | 3 rows per user per category. Enforced server-side via `ROW_NUMBER() OVER (PARTITION BY user_id ORDER BY <agg_expr> <direction>)`; the `<direction>` is per-category — `DESC` for `top_speed` / `total_distance`, `ASC` for `best_060` — so the cap keeps the user's best 3 cars by the metric's natural sort. |
| Default period | All Time (unchanged). |
| PR strategy | 5 PRs, split by area. |
| Wire format | Additive. New fields default sensibly so old clients keep working. New `period` values rejected with `400` by old backend. |
| Migrations | None at the DB layer. All new state lives inside the `users.garage` JSON blob and is forward-compatible. |

### Wire contract changes (additive only)

`LeaderboardEntry` gains:

```go
type LeaderboardEntry struct {
    Rank        int     `json:"rank"`
    UserID      uint    `json:"user_id"`
    Username    string  `json:"username"`
    Country     string  `json:"country"`
    AvatarURL   string  `json:"avatar_url"`
    Value       float64 `json:"value"`
    CarID       *string `json:"car_id"`        // new
    CarKey      string  `json:"car_key"`       // new: synthetic key
    CarMake     string  `json:"car_make"`
    CarModel    string  `json:"car_model"`
    CarYear     *int    `json:"car_year"`      // new
    CarTrim     *string `json:"car_trim"`      // new
    CarNickname *string `json:"car_nickname"`  // new
    CarPhotoURL *string `json:"car_photo_url"` // new
}
```

- Period enum (final): `last_24h | last_7_days | all_time`. Old `week` →
  `400 invalid period`.
- Category enum (final): `top_speed | best_060 | total_distance`. Old
  `drive_count` → `400`.

## Out of scope

- "Month" timeframe. (Easy follow-up if the three values feel sparse.)
- Web profile page at `website/spa/src/routes/u/[username]/+page.svelte`
  (served at URL `/u/:username`). Only the `/leaderboard` SPA is updated
  to match the new API; the profile page is left for a follow-up.
- iOS deep-link to a specific leaderboard category.
- New achievements. (Car-per-row is informational only.)
- Server-side janitor for orphan `uploads/garage_cars/*` files. Best-effort
  unlink on photo replace/remove; deferred cleanup is acceptable.

## Parallelization

3 tracks, 1 subagent per track, each track subagent dispatches its own
intra-PR fan-out:

```
PR1 backend leaderboard ──► PR2 iOS leaderboard
PR3 backend car-photo   ──► PR4 iOS profile redesign
   + iOS upload/editor
PR5 iOS nav reorder  (no deps)
```

| Track | Worktrees | Branches |
|---|---|---|
| A — Leaderboard | `.worktrees/leaderboard-car-centric` → `.worktrees/ios-leaderboard-car-centric` | `feat/leaderboard-car-centric` → `feat/ios-leaderboard-car-centric` |
| B — Photos + profile | `.worktrees/garage-car-photos` → `.worktrees/profile-redesign` | `feat/garage-car-photos` → `feat/profile-redesign` |
| C — Nav reorder | `.worktrees/nav-reorder` | `feat/nav-reorder` |

### Merge-order guardrails

- Track A PR1 must merge to `main` before Track A PR2 rebases.
- Track B PR3 must merge to `main` before Track B PR4 rebases.
- Track C PR5 is independent.
- After every merge to `main`, every other worktree must `git fetch origin
  main && git rebase origin/main` per repo `AGENTS.md`.

---

## PR 1 — Backend: car-centric leaderboard + new timeframes + drop `drive_count`

**Files:**
- `backend/internal/app/social_handlers.go:14-23, 85-227` — extend
  `LeaderboardEntry`, rewrite `getLeaderboard` SQL.
- `backend/internal/app/social_handlers.go:59-67` — delete
  `startOfCurrentWeek`; replace with `startOfLast7Days` /
  `startOfLast24Hours`.
- `backend/internal/app/handlers_test.go` — add `TestLeaderboard_*` block
  using in-memory SQLite.
- `website/spa/src/routes/leaderboard/+page.svelte:14-30, 113-121, 25-30` —
  category list, period buttons, copy.
- `website/spa/src/routes/+page.svelte:23` — home stat strip (drop Drives).

**SQL shape (sketch):**

```sql
WITH ranked AS (
  SELECT
    d.user_id, d.car_id,
    COALESCE(d.car_id, LOWER(TRIM(d.car_make)) || '|' || LOWER(TRIM(d.car_model))) AS car_key,
    d.car_make, d.car_model, d.car_year, d.car_trim, d.car_nickname,
    <agg_expr> AS value,
    ROW_NUMBER() OVER (PARTITION BY d.user_id ORDER BY <agg_order>) AS rn
  FROM drives d
  WHERE d.start_time >= <period_cutoff or '0001-01-01'>
    AND <scope_in or 1=1>
    AND <car_filter or 1=1>
    AND <agg_extra_where>
  GROUP BY d.user_id, d.car_key, d.car_id, d.car_make, d.car_model,
           d.car_year, d.car_trim, d.car_nickname
)
SELECT r.*, u.username, u.country, u.avatar_url
FROM ranked r
JOIN users u ON u.id = r.user_id
WHERE u.is_public = true AND r.rn <= 3
ORDER BY value <ASC_OR_DESC>
LIMIT 50;
```

**Tests:**
- `TestLeaderboard_OneUserMultipleCarsAppearAsSeparateRows`
- `TestLeaderboard_LegacyDrivesWithoutCarID_GroupedByMakeModel`
- `TestLeaderboard_PeriodLast24Hours`
- `TestLeaderboard_PeriodLast7Days`
- `TestLeaderboard_DriveCountCategoryRejected`
- `TestLeaderboard_CapAt3CarsPerUser`
- `TestLeaderboard_PrivateUsersExcluded`

**Verification:**
- `cd backend && CGO_ENABLED=1 go build ./...`
- `cd backend && CGO_ENABLED=1 go vet ./...`
- `cd backend && go test ./... -run TestLeaderboard -v`
- `cd backend && go test ./... -timeout 60s`
- Manual: `curl https://fast.toper.dev/api/v1/leaderboard?category=top_speed&period=last_7_days`
  returns per-car rows.
- Web SPA builds and shows per-car rows at `fast.toper.dev/leaderboard`.

---

## PR 2 — iOS: leaderboard updates to match

**Files:**
- `ios/FastTrack/FastTrack/Models/SocialModels.swift:5-98` — add fields to
  `LeaderboardEntry`; trim `LeaderboardCategory` to three cases (drop
  `driveCount`, order `.topSpeed, .best060, .totalDistance`); add
  `.last24Hours`, rename `.week` → `.last7Days` and change `displayName` to
  "Last 7 Days".
- `ios/FastTrack/FastTrack/Services/APIService.swift:282-297` — update
  query string for new period values.
- `ios/FastTrack/FastTrack/Views/SocialView.swift:1-323` — render car row
  with car photo thumbnail + nickname, the same car can appear multiple
  times for one user without a "You" highlight on every row (highlight only
  the row whose `carId == currentUserSelectedCarId`).
- `ios/FastTrack/FastTrack/Views/SharedComponents.swift:319-337` — adjust
  `LeaderboardSkeletonRow` width if the avatar gains a car thumbnail.
- `ios/FastTrack/FastTrack/AppStoreScreenshotMode.swift:60-79` — update
  mock categories and entries.
- `ios/FastTrack/FastTrackTests/SocialModelsTests.swift` (new) —
  `testLeaderboardEntry_DecodesCarFields`,
  `testLeaderboardCategory_ExcludesDriveCount`,
  `testLeaderboardPeriod_IncludesLast24Hours`.

**Verification:**
- `xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack
  -destination "platform=iOS Simulator,name=iPhone 17 Pro"
  -only-testing:FastTrackTests/SocialModelsTests CODE_SIGNING_ALLOWED=NO`
- `xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme
  FastTrack -destination "generic/platform=iOS Simulator" -configuration
  Debug CODE_SIGNING_ALLOWED=NO`
- Confirm no AppStoreScreenshotMode crashes.

---

## PR 3 — Per-car photos end-to-end

**Backend files:**
- `backend/internal/app/auth_handlers.go` — new `uploadCarPhoto(c
  *gin.Context)`. Path: `PUT /api/v1/garage/cars/:carId/photo`. Body:
  `{image_data: <base64>}`. Validates with `image.DecodeConfig`, writes
  `uploads/garage_cars/<userID>_<carID>.<ext>`, mutates `User.Garage` JSON
  to set the matching `UserCar.photo_url`, persists via GORM save, returns
  `{photo_url: <BASE_URL>/uploads/garage_cars/<file>}`.
- `backend/internal/app/auth_handlers.go` — new `deleteCarPhoto(c
  *gin.Context)` that nulls the field and unlinks the file.
- `backend/internal/app/routes_account.go:5-18` — register the two new
  routes (auth required).
- `backend/internal/app/auth_models.go:7-54` — add `CarPhotoResponse`.
- `backend/k8s/` — confirm the `uploads` volume mount covers
  `garage_cars/` (it does: same path used for avatars).
- `backend/internal/app/handlers_test.go` — `TestUploadCarPhoto_*`.

**iOS files:**
- `ios/FastTrack/FastTrack/Models/UserProfile.swift:7-41, 71-75, 81-103` —
  add `var photoUrl: String?` to `UserCar`; add `CodingKey photo_url =
  "photo_url"`; update `init`; update `displayString` to skip when no
  photoUrl; add `updateCarPhotoUrl(id:url:)` helper.
- `ios/FastTrack/FastTrack/Services/APIService.swift:317-326` — add
  `uploadCarPhoto(carId:data:)` and `deleteCarPhoto(carId:)`.
- `ios/FastTrack/FastTrack/Models/UserProfile.swift:108-298` — extend
  `saveProfile` so a `photoUrl` change persists; extend `restoreFromServer`
  to parse the new field.
- `ios/FastTrack/FastTrack/Views/CarSelectorView.swift:65-132` — add a
  "Set Photo" / "Change Photo" / "Remove Photo" row in `AddCarView` using
  `PhotosPicker`. Resize to 800px JPEG before upload (reuse compression in
  `ProfileManager.saveAvatar`).
- `ios/FastTrack/FastTrack/Views/ProfileView.swift:766-870` — render
  `photoUrl` thumbnail in `CarGarageCard`.
- `ios/FastTrack/FastTrack/Views/PublicProfileView.swift` — render
  `photoUrl` thumbnail in the garage section added in PR 4 (read-only).

**Tests:**
- Backend: `TestUploadCarPhoto_RoundTrips`,
  `TestUploadCarPhoto_RejectsOversizeImage` (8 MB cap),
  `TestUploadCarPhoto_NilData400`, `TestDeleteCarPhoto_RemovesFileAndField`.
- iOS: `testUserCar_DecodesPhotoUrlFromServer`,
  `testUserCar_RoundTripsPhotoUrl`.

**Verification:**
- Backend `go test ./... -v` green.
- iOS `xcodebuild test` green.
- Manual: add a car with a photo in iOS, sign out, sign in on a fresh
  simulator, confirm the photo is restored.
- Manual: `curl` the photo URL on `fast.toper.dev` after deploy, confirm
  200.

---

## PR 4 — Public profile + own profile redesign

**Files:**
- `ios/FastTrack/FastTrack/Models/SocialModels.swift:102-130` — add
  `garage: String?` and `carStatsData: String?` to `PublicProfile`
  CodingKeys (the server already returns both; the Swift model currently
  ignores them).
- `ios/FastTrack/FastTrack/Views/PublicProfileView.swift:40-148` — full
  header redesign.
- `ios/FastTrack/FastTrack/Views/PublicProfileView.swift` — add a Garage
  section (parses `garage` string into `[UserCar]`, shows the photo
  thumbnail + nickname + a per-car stat row pulled from `carStatsData`).
- `ios/FastTrack/FastTrack/Views/PublicProfileView.swift:84-87` — convert
  `countView` to a `NavigationLink` to a new `FollowersListView` /
  `FollowingListView`.
- `ios/FastTrack/FastTrack/Views/PublicProfileView.swift:46-61` — add
  `.onTapGesture` on the avatar that presents a `.fullScreenCover` with the
  high-res image.
- `ios/FastTrack/FastTrack/Views/PublicProfileView.swift:116-145` — reorder
  Stats: Top Speed, Best 0–60, Total Distance (drop Total Drives).
- `ios/FastTrack/FastTrack/Views/FollowersListView.swift` (new) and
  `FollowingListView.swift` (new) — list backed by
  `APIService.fetchFollowers` / `fetchFollowing` (both already exist at
  `social_handlers.go:424, 443`); tap row → `PublicProfileView`. Add
  `APIService.fetchFollowers(username:)` and `fetchFollowing(username:)`
  methods.
- `ios/FastTrack/FastTrack/Services/APIService.swift:299-301, 303-315` —
  add the two fetches; reuse `FollowUserEntry` decode.
- `ios/FastTrack/FastTrack/Views/ProfileView.swift:147-196` (own profile
  header) — mirror narrow-header layout and tap-to-zoom avatar.
- `ios/FastTrack/FastTrack/Views/ProfileView.swift:77-78, 305-360` — swap
  the `topSpeedCard` and `best060Card` order so 0–60 sits directly under
  Top Speed.
- `ios/FastTrack/FastTrackTests/PublicProfileDecodingTests.swift` (new) —
  `testPublicProfile_DecodesGarageString`,
  `testPublicProfile_DecodesCarStatsBlob`.
- `testAPIService_BuildsFollowersEndpointURL`.

**Verification:**
- `xcodebuild test` green.
- Manual: visit a friend's public profile, tap Followers, see list, tap a
  follower, see their profile, tap their avatar, see full-screen zoom.
- Manual: own profile, tap avatar, see zoom; verify 0–60 appears
  directly under Top Speed.

---

## PR 5 — Bottom navigation reorder

**Files:**
- `ios/FastTrack/FastTrack/FastTrackApp.swift:110-127` — swap
  `SocialView` to position 1, `DriveHistoryView` to position 2,
  `AnalyticsView` to position 3. Retag so `Social = 1`, `History = 2`,
  `Analytics = 3`, `Profile = 4` (Track stays 0).
- `ios/FastTrack/FastTrack/FastTrackApp.swift:71, 144` — extract
  `socialTabTag = 1` constant; update `tabResetIDs = (0..<5).map { _ in
  UUID() }`; update the `oldTab > 0 && oldTab != 3` check to `oldTab > 0
  && oldTab != socialTabTag` so Social still does not reset on leave.
- `ios/FastTrack/FastTrack/AppStoreScreenshotMode.swift:9-25, 60-79` —
  keep mock ordering in sync.
- `ios/FastTrack/FastTrack/FastTrackApp.swift:152` — Live Activity
  deep-link still switches to `selectedTab = 0` (Track), unchanged.

**Verification:**
- `xcodebuild build-for-testing` green.
- Manual: every tab still loads, the reset-on-leave behaviour for
  History/Analytics/Profile still works, Social still preserves its nav
  stack when switched away and back, Track still preserves an active
  recording.

---

## Cross-cutting checklist (every PR)

- `cd backend && CGO_ENABLED=1 go build ./...`
- `cd backend && CGO_ENABLED=1 go vet ./...`
- `cd backend && go test ./... -timeout 60s`
- `cd ios/FastTrack && xcodebuild test -project FastTrack.xcodeproj
  -scheme FastTrack -destination "platform=iOS Simulator,name=iPhone 17
  Pro" CODE_SIGNING_ALLOWED=NO`
- No new lint rule violations; commitlint header ≤ 100 chars; squash
  merge per repo policy.
- `Secrets.swift` recreated from template before each iOS build in CI.
- `X-Request-ID` and `request_id` log fields still emitted on all routes.

## Open risks

1. **Synthesizing `car_key` from `make + model`** treats different years of
   the same model as one row. Acceptable for v1.
2. **Per-user cap of 3** is leaderboard-only. The user's own profile garage
   still shows all their cars.
3. **Photo file cleanup** is best-effort; no nightly janitor.
4. **Public profile `carStatsData`** is the raw iOS-uploaded blob. If the
   user has never opened iOS since the field was introduced, the public
   profile garage cards will show "No stats yet". Acceptable; documented in
   PR 4.
5. **Svelte profile page (`/u/:username`)** is not updated. Will drift
   from the iOS UI. Calling out as a follow-up.
6. **Tag-number refactor in PR 5** turns the literal `3` into a constant;
   non-functional cleanup, included with the reorder.
