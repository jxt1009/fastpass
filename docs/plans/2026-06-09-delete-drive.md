# Delete Drive — Design Spec

**Date:** 2026-06-09
**Worktree:** `feat/integration`
**Status:** Approved (pending spec review)

## Summary

Add a way to permanently delete a single drive. Two entry points: a trash icon on the individual drive overview page, and swipe-to-delete-with-confirm on drive rows in the history and recent-drives lists. Both go through a single shared `DriveManager.deleteDrive(id:)` flow. The server gets one new additive endpoint.

## Goals

- A user can delete a drive they own from the drive overview page.
- A user can delete a drive they own from any list that surfaces it (history, car detail, garage).
- Destructive action is always confirmed; never silent.
- The deleted drive disappears from every list on next render.
- Downstream `UserAchievement.source_drive_id` references are cleaned up so PB events stay consistent.

## Non-Goals

- Undo / restore. Not consistent with the existing delete-account and delete-car-photo flows.
- Bulk delete / multi-select.
- Soft delete / archive. The codebase has no `gorm.DeletedAt` on `Drive` and the team's `deleteCurrentUser` is a hard delete. Documented as a possible follow-up.
- Web SPA parity. The SPA has no drive detail page; out of scope.
- Sharing / un-sharing. Out of scope.

## User-Visible Behavior

### Entry point 1: trash icon on `DriveDetailView`

- Visible only to the drive owner (`drive.userID == AuthManager.shared.getUser()?.id`).
- Tapping it opens a confirmation alert: **"Delete Drive?"** with message **"This permanently removes the drive from your history. This can't be undone."** Buttons: **Cancel** (default), **Delete** (destructive role, red).
- Confirming starts the request. The Delete button shows "Deleting…" and is disabled until the request returns.
- On success: the view pops. The row disappears from the underlying list on next render.
- On error: a second alert **"Unable to Delete Drive"** shows the localized error; the user remains on the detail page.

### Entry point 2: swipe-to-delete-with-confirm on lists

- Available on:
  - `DriveHistoryView` rows (the full history list).
  - `CarDetailView` "Recent Drives" section rows.
  - `GarageView` "Recent Drives" section rows.
- Swiping a row reveals a single destructive **Delete** action.
- Tapping it opens the same confirmation alert as the trash icon. The row is **not** removed on swipe alone.
- Confirming deletes and the row disappears on the same render pass (via the same shared `DriveManager.deleteDrive(id:)` flow).
- Non-owner rows do not show the swipe action.

## Architecture

Two entry points, one shared flow:

```
┌──────────────────────┐    ┌──────────────────────┐
│ DriveDetailView      │    │ List view swipe      │
│ toolbar trash icon   │    │ (history / car /     │
│ (owner only)         │    │  garage)             │
└──────────┬───────────┘    └──────────┬───────────┘
           │                           │
           │  show alert               │  set drivePendingDelete
           │  performDelete()          │  show alert
           ▼                           ▼
   DriveManager.deleteDrive(id:)  ← called from the list's
                                    alert action handler
           │
           ▼
   APIService.deleteDrive(id:)
           │  DELETE /api/v1/drives/:id
           ▼
   Backend handler deleteDrive(c)
           │  tx: NULL source_drive_id → Delete(drive) → evaluateForUser
           ▼
   200 {ok: true} | 404 | 500
           │
           ▼
   remove from drives array
   rebuild CarStatsManager
   refreshAchievementsFromServer()
```

The delete logic lives on `DriveManager`, not in the views. The views own the alert state and the trigger.

## Server Changes

### Route

`backend/internal/app/routes_drive.go` — add one line:
```go
api.DELETE("/drives/:id", deleteDrive)
```

### Handler

`backend/internal/app/handlers.go` — add `deleteDrive(c *gin.Context)` next to `getDrive` and `updateDrive`. Modeled on those handlers for auth and ownership checks.

Steps:
1. `userID, exists := getUserID(c)` — return 401 if missing.
2. `id, err := strconv.Atoi(c.Param("id"))` — return 400 on bad integer.
3. `db.Where("id = ? AND user_id = ?", id, userID).First(&drive)` — return 404 on `gorm.ErrRecordNotFound`. Same convention as `getDrive`/`updateDrive`; do not leak existence.
4. Transaction:
   - `tx.Model(&UserAchievement{}).Where("source_drive_id = ?", id).Update("source_drive_id", nil)` — NULL dangling pointers.
   - `tx.Delete(&drive)` — hard delete. No `gorm.DeletedAt` on `Drive`; matches the existing `deleteCurrentUser` pattern in `auth_handlers.go:615-678`.
   - Call `evaluateForUser(userID)` so PB events stay consistent and any newly-broken records are re-evaluated.
5. On transaction failure, return 500 with `{"error": "Failed to delete drive"}`.
6. On success, return 200 with `{"ok": true}`.

### Response Shape

```json
// success
{ "ok": true }

// 404 (not found / not yours)
{ "error": "Drive not found" }

// 500 (tx failure)
{ "error": "Failed to delete drive" }
```

### Backward Compatibility

- The new endpoint is purely additive. No existing client behavior changes.
- The response shape (`{ok: true}`) is novel; no decoder conflict with existing iOS decoders.
- No schema change. `UserAchievement.source_drive_id` is already nullable.
- No migration needed.
- Old clients do not call this endpoint, so they cannot break.
- Litmus test: "Would this break last week's App Store release?" — No. ✅

## iOS Changes

### `APIService.swift`

Add one method, modeled on `unfollowUser` at `APIService.swift:310`. Place next to the other drive methods (around line 182).

```swift
func deleteDrive(id: Int) async throws {
    try await delete(endpoint: "/drives/\(id)")
}
```

### `DriveManager.swift`

Add one method, modeled on the existing car-reassignment flow (see `DriveDetailView.swift:791`) and the `refreshAchievementsFromServer` call in `stopRecording` at `DriveManager.swift:292`.

```swift
@MainActor
func deleteDrive(id: Int) async throws {
    try await apiService.deleteDrive(id: id)
    drives.removeAll { $0.id == id }
    CarStatsManager.shared.rebuildStats(from: drives)
    await refreshAchievementsFromServer()
}
```

### `DriveDetailView.swift`

- Add three `@State` vars:
  ```swift
  @State private var showingDeleteConfirmation = false
  @State private var isDeleting = false
  @State private var deleteError: String?
  ```
- Add `@Environment(\.dismiss) private var dismiss`.
- Add an `isOwner` computed property: `drive.userID == AuthManager.shared.getUser()?.id`.
- Add a `.toolbar` modifier on the body, conditional on `isOwner`, with a destructive `trash` `Button` (disabled while `isDeleting`).
- Add two stacked `.alert` modifiers mirroring `ProfileView.swift:88-104`:
  - Confirmation: "Delete Drive?" with Cancel + destructive Delete. Delete button label is "Deleting…" and is disabled while in flight.
  - Error: "Unable to Delete Drive" with OK, message bound to `deleteError`.
- Add a `@MainActor private func performDelete()` with the same re-entrancy guard and `defer` shape as `ProfileView.deleteAccount` (lines 373–398). On success: `dismiss()`. On failure: set `deleteError`.

### `DriveHistoryView.swift`, `CarDetailView.swift`, `GarageView.swift`

For each file:
- Add `@State private var drivePendingDelete: Drive?` and `@State private var deleteError: String?` at the top of the view.
- Add `@EnvironmentObject` reference to `DriveManager` if not already present.
- On each drive row, add `.swipeActions(edge: .trailing) { Button(role: .destructive) { drivePendingDelete = drive } label: { Label("Delete", systemImage: "trash") } }`.
- Add two stacked `.alert` modifiers on the parent list (not on the row):
  - Confirmation, gated on `drivePendingDelete != nil`, with Cancel + destructive Delete. The Delete button calls a `@MainActor private func performDelete()` that awaits `driveManager.deleteDrive(id: drivePendingDelete!.id)` and clears `drivePendingDelete` on success or sets `deleteError` on failure.
  - Error, gated on `deleteError != nil`, with OK.
- Only render the swipe action for rows the user owns: guard with `if drive.userID == AuthManager.shared.getUser()?.id { ... }`.

**Care point:** these three files have uncommitted in-progress changes for the `CarDetailGauge` refactor (commit `6a39eaf`). The new swipe/alert code must be additive and not interfere with the gauge refactor. Re-read each file before editing.

## Local State Consistency

`DriveManager.deleteDrive(id:)` runs three steps in order after the server returns success:

1. Remove the drive from `self.drives`.
2. `CarStatsManager.shared.rebuildStats(from: drives)` — same as the existing car-reassignment path.
3. `await refreshAchievementsFromServer()` — flushes local achievement cache so any `sourceDriveId` that was NULLed server-side doesn't surface a stale "view drive" link.

`DriveHistoryView`'s existing `.onAppear { driveManager.fetchDrives() }` plus the 10s polling timer in `DriveManager.startPolling` will reconcile any race. The car-detail and garage views rely on the polling timer.

## Error Handling

- **Network failure** (timeout, offline, 5xx): the second alert shows the error. The drive remains in the local list. The user can retry from the same screen.
- **404** (drive already deleted on another device): **treated as success at the UI level.** The goal state (drive no longer in the list) is already achieved. The iOS layer swallows `APIError.serverError(404)` from `deleteDrive`; the local `removeAll` runs unconditionally before the request returns, so the list is consistent either way. The second alert is suppressed on 404.
- **401** (token expired): show the error. The user can sign in again. Existing `APIService` flow handles token refresh; the iOS layer surfaces the error from the catch block.
- **Re-entrancy:** the `isDeleting` flag plus `guard !isDeleting { return }` prevents double-tap races (same pattern as `ProfileView.deleteAccount`).

## Testing

### Backend (Go)

Add to `backend/internal/app/handlers_test.go` (SQLite in-memory, matches existing pattern):

- `TestDeleteDrive_Unauthorized` — no auth, expects 401.
- `TestDeleteDrive_BadID` — non-integer `:id`, expects 400.
- `TestDeleteDrive_NotFound` — nonexistent id, expects 404.
- `TestDeleteDrive_WrongOwner` — another user's drive, expects 404 (no leak).
- `TestDeleteDrive_HappyPath` — owner deletes their drive, expects 200 `{ok: true}`, expects `db.First(&Drive{}, id).Error == gorm.ErrRecordNotFound`.
- `TestDeleteDrive_NullsAchievementSource` — pre-seed an achievement with `SourceDriveID = id`, then delete the drive, expect `SourceDriveID == nil` after.
- `TestDeleteDrive_RunsAchievementEvaluation` — stub or spy on `evaluateForUser`; assert it's called with the user id.

### iOS (XCTest)

In `ios/FastTrack/FastTrackTests/`:

- `DriveManagerTests`:
  - `testDeleteDrive_RemovesFromArray` — populate `drives`, stub `APIService.deleteDrive` to succeed, assert `drives` is empty.
  - `testDeleteDrive_CallsRebuildStats` — assert `CarStatsManager.shared.rebuildStats` is invoked (or stub and assert call).
  - `testDeleteDrive_RefreshesAchievements` — assert `refreshAchievementsFromServer` is awaited.
  - `testDeleteDrive_PropagatesError` — stub `APIService.deleteDrive` to throw, assert the error propagates and the array is unchanged.
- `APIServiceTests`:
  - `testDeleteDrive_HitsCorrectEndpoint` — URLSession stub, assert request is `DELETE /api/v1/drives/123`, no body, 200 returns normally.
  - `testDeleteDrive_ThrowsOnNon2xx` — 404, 500 paths throw `APIError.serverError`.
- `DriveDetailViewTests` (if ViewInspector is in use; otherwise omit):
  - `testDeleteButton_HiddenForNonOwner`
  - `testDeleteButton_VisibleForOwner`
  - `testConfirmingDelete_CallsDriveManagerAndDismisses` (verifies `dismiss()` and `DriveManager.deleteDrive` are called on success).
  - `testErrorAlert_PresentedOnDeleteFailure`.
- `DriveHistoryViewTests`:
  - `testSwipeAction_SetsPendingDelete` — swipe row, assert `drivePendingDelete == drive`, row still in list.
  - `testSwipeAction_HiddenForNonOwner`.
  - `testConfirmingDelete_CallsDriveManager` — confirms alert, assert `DriveManager.deleteDrive(id:)` was awaited.

If ViewInspector is not available in the test target, skip the view-level tests and rely on the `DriveManager` and `APIService` unit tests for behavioral coverage.

## File Touch List

Server:
- `backend/internal/app/routes_drive.go` — add one line.
- `backend/internal/app/handlers.go` — add `deleteDrive` handler.
- `backend/internal/app/handlers_test.go` — add new tests.

iOS:
- `ios/FastTrack/FastTrack/Services/APIService.swift` — add `deleteDrive(id:)`.
- `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift` — add `deleteDrive(id:)`.
- `ios/FastTrack/FastTrack/Views/DriveDetailView.swift` — toolbar trash icon, two alerts, perform-delete func.
- `ios/FastTrack/FastTrack/Views/DriveHistoryView.swift` — swipe action, alerts, perform-delete func.
- `ios/FastTrack/FastTrack/Views/CarDetailView.swift` — swipe action on Recent Drives rows, alerts.
- `ios/FastTrack/FastTrack/Views/GarageView.swift` — swipe action on Recent Drives rows, alerts.
- `ios/FastTrack/FastTrackTests/...` — new unit tests as listed above.

## Open Questions

None. All decisions captured above.

## Proposed Commit / PR Title

`feat(ios+backend): delete a drive from the detail page and lists` (62 chars)

This is the single squash commit / PR title. Within the worktree, intermediate commits should follow the conventional format and stay under 100 chars per AGENTS.md §2.

## Follow-Ups (out of scope for this spec)

- Open a follow-up issue: "Evaluate soft delete / archive for drives" — referenced from the existing `docs/plans/2026-06-08-fasttrack-garage-stats-competition-ux.md` discussion.
- Web SPA parity: add a delete control on the public drive detail page (separate spec).
