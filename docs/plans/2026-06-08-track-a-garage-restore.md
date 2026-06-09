# Track A: Profile Privacy & Garage Restore Fixes

**Date:** 2026-06-08  
**Branch:** `fix/ios-profile-garage-restore`

## Problems

1. **Profile privacy can silently reset (HIGH)** — `AuthManager.User` doesn't decode `is_public`, so `restoreFromServer` and `ProfileSetupView.save()` both default it to `true`, overwriting a user's private setting.
2. **Garage restore ignores same-count edits (HIGH)** — `restoreFromServer` only trusts the server when `serverGarage.count > profile.garage.count`, missing renames, photo changes, and same-count replacements.
3. **Car stats rebuild uploads N times (MEDIUM)** — `rebuildStats(from:)` calls `updateStats` per drive, each of which calls `saveCarStats()` which uploads to the server, causing N network calls.
4. **Missing tests** — No coverage for the above bugs.

## Changes

### `AuthManager.swift`
- Add `isPublic: Bool` field to `User` struct with `CodingKey` `is_public`, decoded with `decodeIfPresent` defaulting `true`.

### `UserProfile.swift`
- `restoreFromServer`: pass `serverUser.isPublic` when constructing the restored `UserProfile`.
- `restoreFromServer`: replace `serverGarage.count > profile.garage.count` with `!serverGarage.isEmpty` so server always wins when it returns data.

### `ProfileSetupView.swift`
- `save()`: read `profileManager.profile?.isPublic ?? true` and pass it to the `UserProfile` initializer.

### `CarStats.swift`
- Add `suppressUpload: Bool = false` parameter to `saveCarStats()`.
- `rebuildStats(from:)`: pass `suppressUpload: true` to each `updateStats` call (via a new internal helper), then call `saveCarStats()` once at the end.

### `ProfileRestoreTests.swift` (new file)
- `testRestoreFromServer_preservesIsPublicFalse`
- `testRestoreFromServer_usesServerGarageOnSameCount`
- `testRebuildStats_uploadsOnce`

## Verification
Build with `xcodebuild build-for-testing` in the iOS project directory.
