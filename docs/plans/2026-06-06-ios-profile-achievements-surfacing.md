# iOS: Surface Achievements Above the Fold (Phase 1 / Track C, issue #64)

**Date:** 2026-06-06
**Branch:** `feat/ios-profile-achievements-surfacing`
**Worktree:** `.worktrees/ios-profile-achievements-surfacing`
**Target issue:** #64

## Status

- [x] Worktree + plan artifact
- [x] Extract `RecentAchievementsStrip` SwiftUI component
- [x] Reorder profile VStack (strip right under header, ahead of garage)
- [x] Preserve source-drive deep-link behavior
- [x] Add tests (ordering, local + remote link resolution, structural order)
- [x] Build + run iOS tests
- [x] Conventional commit + push + open PR

## Decisions Locked

- **Strip header**: "Achievements" title on the left, "View All" `NavigationLink` to
  `AchievementsView()` on the right. Mirrors the in-card summary header that the
  old `achievementsSection` had, so the move feels like a redesign, not a removal.
- **Card layout**: each card = large (40 pt) category-colored icon + title +
  one-line description. Width ~160 pt. Tappable rectangle with the same
  NavigationLink semantics as the original `achievementRow`.
- **Sort order**: most recently unlocked first (`unlockedDate` desc), then by
  `id` as a stable tiebreaker. Catalog order (what the old `prefix(3)` did) is
  not "most recent" — the new component fixes that.
- **Source-drive resolution**: local `driveManager.drives` first, then
  `RemoteDriveDetailLoader(driveId:)`. Mirrors the existing `achievementRow`
  semantics exactly. Extracted into a `RecentAchievementsStripLogic` helper so
  the resolution is unit-testable without a SwiftUI view tree.
- **Empty state**: "Complete a drive to start unlocking achievements" inside an
  `InstrumentCard` so the visual weight matches the rest of the profile.
- **Reusability for Track H**: the strip takes an `achievementManager:`
  `AchievementManager` + `driveManager: DriveManager` and a list of
  `Achievement`s. `AchievementManager` only exposes `.shared` (its
  initializer is private), so the notification feed (Phase 3) will
  reuse the existing `RecentAchievementCard` directly: it surfaces a
  `UserAchievement` from the server as a tile by mapping the server
  payload into a lightweight `RecentAchievementTile` value
  (id, title, icon, sourceDriveId, achievedAt) that the card accepts
  as a variant input — no ad-hoc manager instance required.

## Files

- `ios/FastTrack/FastTrack/Views/Components/RecentAchievementsStrip.swift` — new
- `ios/FastTrack/FastTrack/Views/ProfileView.swift` — reorder, remove
  `achievementsSection` and its section header
- `ios/FastTrack/FastTrackTests/RecentAchievementsStripTests.swift` — new
  (helper + ordering + link resolution + structural order)
- `ios/FastTrack/FastTrackTests/ProfileRedesignTests.swift` — add the
  `testProfileView_AchievementsStripAboveGarage` line-order guard here so the
  existing file owns the regression guard for #57 + #64

## Backward compatibility

No API change, no schema change, no removed/renamed field. Pure iOS UI work.
