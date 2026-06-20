# R5: Achievements + Notifications Fixes

Date: 2026-06-19
Branch: `fix/ios-audit-r5-achievements`
Scope: iOS only (`ios/FastTrack/FastTrack/`)

## Tasks

1. **Secret badges not tappable** — add `isSecret` to `Achievement` (backward-compatible
   Codable decode), mark `speed_150` + `smooth_operator` as secret in the catalog, gate
   `AchievementsView` `.onTapGesture` so `.unknown` (??? ) badges are not tappable.
2. **Local unlock logic for zeroToSixty + smoothness** — implement `calculateProgress`
   cases that currently return `0.0`. zeroToSixty uses best `best060Time` across drives;
   smoothness uses a brake-events-per-mile proxy.
3. **Streak same-day + markAllRead local + unlock toast**
   - 3a: `calculateConsecutiveDays` resets streak on same-day drives (dayDiff 0) — skip
     instead of reset.
   - 3b: `markAllRead` updates each local notification row's `readAt`, not just `unreadCount`.
   - 3c: toast on new `recentUnlocks` (requires `Achievement: Equatable`).
4. **Notification deep-linking by kind** — tapping a notification navigates to the
   relevant drive (`RemoteDriveDetailLoader`) or actor profile (`PublicProfileView`),
   and marks it read.

## Verification

- `xcodebuild build-for-testing` (generic/iOS Simulator, no signing).
- Run existing achievement tests if present.

## Backward compatibility

- `Achievement.isSecret` decodes via `decodeIfPresent ?? false` so existing
  `user_achievements_v2` UserDefaults data (without the key) still decodes — users keep
  their unlocked state. No server/API changes; no DB migrations.
