# Achievements + 0-60 Attempts on the Map (iOS + Web)

**Date:** 2026-06-01
**Branch:** `feat/achievements-060-attempts` (worktree at `.worktrees/achievements-060`)

## Status

- [x] Worktree + plan artifact
- [ ] Backend: model + migration + evaluator + new endpoints + handler tests
- [ ] iOS: multi-attempt capture + 0-60 map overlay + PB history highlight + profile row → drive
- [ ] Web: public drive endpoint + public drive page + achievements section on public profile
- [ ] PRs (split backend + iOS + web)

## Context

The user wants:

1. **Achievement → source drive**: every achievement, when unlocked, links to the
   drive that produced it. Tapping the achievement in the iOS profile opens that
   drive.
2. **Multiple 0-60 attempts per drive**: a single recording session can produce
   many launches. The map shows each attempt as a highlighted polyline segment
   with a "speech-bubble" marker showing the elapsed time.
3. **PB highlight in history**: the row corresponding to the drive that first
   set the all-time 0-60 PB gets a small badge / color accent.
4. **Achievements on profile for iOS and web**: server-authoritative; the public
   web profile shows the same unlocked achievements as the iOS profile.

## Decisions Locked

- **PB highlight** = the drive whose `best_060_time` *first* set the all-time
  minimum. Source drive id is stored on the `sub_6_club` `UserAchievement` row
  when it unlocks; if no such achievement exists yet, fall back to the drive
  with `MIN(best_060_time)` (lex tie-break: most recent).
- **Backend = source of truth** for `user_achievements`. Evaluator runs on
  `createDrive` / `updateDrive` and returns `unlocked_achievements` in the
  response so iOS can celebrate and merge the server's canonical list.
- **Achievement → drive link** persisted as `source_drive_id` + `source_kind`
  on the `user_achievements` row.
- **0-60 attempts** persisted as a typed JSON column on `Drive`
  (`zero_to_sixty_attempts: []ZeroToSixtyAttempt`). A `zero_to_sixty` event is
  also emitted in the `route_data` JSON for legacy clients to read.
- **Map marker** = thick orange polyline over the attempt segment +
  speech-bubble annotation at the midpoint showing `"{time}s"`.
- **iOS profile row** tap → `DriveDetailView` (when `source_drive_id` set).

## High-level Architecture

- Backend adds `UserAchievement` table + `Drive.zero_to_sixty_attempts`
  (GORM `serializer:json`).
- New endpoints: `GET /api/v1/me/achievements`,
  `GET /api/v1/users/:username/achievements`,
  `GET /api/v1/drives/:id/public`.
- Evaluator lives in `backend/internal/app/achievements.go` (pure Go port of
  the Swift `AchievementManager.calculateProgress(...)` logic).
- iOS captures all valid launches in `LaunchTracker`, builds
  `[ZeroToSixtyAttempt]`, flushes to `Drive` + emits a route event.
- iOS `DriveDetailView` renders attempt segments + speech bubbles.
- iOS `DriveHistoryView` rows highlight the PB drive via `pb060DriveId` on
  `DriveManager`.
- iOS profile rows become `NavigationLink` to `DriveDetailView` for unlocked
  achievements.
- Web SPA gets a `/d/[id]` drive page and a new "Achievements" section on
  `/u/[username]`.

## Backward Compatibility

- `zero_to_sixty_attempts` defaults to `[]` for existing rows. A backfill
  migration synthesizes one "legacy" attempt from each existing `best_060_time`
  so the history list keeps showing a PB for pre-feature drives.
- `zero_to_sixty` route event is additive (existing clients ignore unknown
  event types).
- `unlocked_achievements` field on `createDrive` response is additive.
- `getPublicDrive` is a brand-new endpoint — the existing auth-only
  `getDrive` is unchanged.

## Verification

Backend:
- `CGO_ENABLED=1 go build ./...`
- `CGO_ENABLED=1 go vet ./...`
- `go test ./... -v -timeout 60s` — extend `handlers_test.go` with:
  - `TestUserAchievements_AreUnlockedOnDriveSave`
  - `TestPublicAchievements_HiddenForPrivateUser`
  - `TestPublicDrive_OnlyForPublicUser`
  - `TestAchievementEvaluation_BackfillsZeroToSixtyAttempts`
  - `TestAchievementEvaluation_RecordsPBZeroSixtySourceDrive`

iOS:
- `cp FastTrack/Secrets.swift.template FastTrack/Secrets.swift`
- `xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`
- `xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack -destination "platform=iOS Simulator,name=iPhone 17 Pro" CODE_SIGNING_ALLOWED=NO` — extend `DriveCalculationTests.swift` with:
  - `testLaunchTracker_RecordsMultipleAttemptsInOneDrive`
  - `testZeroToSixtyAttempt_EncodesRoundTrip`
  - `testPB060DriveId_PrefersSub6ClubSourceDrive`

Web:
- `cd website/spa && npm run build` — clean static build.
- Manual smoke against the public API.

## Open Items

- Speech-bubble orientation: always pointing down? confirmed default in plan.
- Map library on web: **Leaflet** (smaller footprint than MapLibre).
- Locked-but-progressing achievements on iOS profile: deferred to follow-up.
