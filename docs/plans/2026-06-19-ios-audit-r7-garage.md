# iOS Audit R7 — Garage / Car-Detail Fixes

Date: 2026-06-19
Scope: `ios/FastTrack/FastTrack/`

## Tasks

### Task 1 — Photo-zoom vs edit-button conflict (CarDetailHero)

**Problem:** The hero photo's tap-to-zoom gesture was attached to the outer
`ZStack` that also contains the `pencil.circle.fill` edit button. A tap on the
edit button could bubble up to the parent `.onTapGesture` and trigger zoom
(the SwiftUI parent-gesture + child-button hazard).

**Fix:** Nest the photo, gradient, and caption in an inner `ZStack` that owns
the `.contentShape(Rectangle())` + `.onTapGesture { onTapPhoto() }`. The edit
button stays a sibling overlay in the outer `ZStack`, so its taps are resolved
by the button itself and never reach the zoom gesture.

**File:** `Views/CarDetailView/CarDetailHero.swift`

**Note:** `CarHeroPhotoEditorSheetTests.testCarDetailView_heroHasPencilCircleFillOverlay`
is a pre-existing failure on main — it reads `CarDetailView.swift` for the
literal `"pencil.circle.fill"`, but the overlay lives in `CarDetailHero.swift`.
Left unfixed per task instructions; this change does not touch
`CarDetailView.swift` so the test is unaffected.

### Task 2 — GarageView refetch throttle

**Problem:** `GarageView.onAppear` called `driveManager.fetchDrives()` on every
visit with no throttle. Navigating away and back rapidly fired redundant
network fetches. `DrivePoller.fetchDrives()` has no built-in throttle.

**Fix:** Added `@State private var lastDriveFetch: Date?`. `onAppear` skips the
fetch when the last fetch was less than 5 seconds ago; otherwise it records the
time and fetches. First visit always fetches. `@State` persists across
push/pop within the same `NavigationStack`/tab, so the throttle covers the
navigate-away-and-back case. Pull-to-refresh elsewhere still updates
`driveManager.drives`, which the view's computed properties reflect without a
re-fetch.

**File:** `Views/GarageView.swift`

### Task 3 — AddCarView error paths

**Problem:** On profile-save failure the sheet already stayed open and preserved
input. But on **photo upload failure** the sheet dismissed immediately,
swallowing `photoError`, so the user lost their photo selection with no visible
error. A naive "keep the sheet open" fix would let a retry of `Save` create a
**duplicate car** (each `UserCar` gets a fresh `UUID()` and `addCarToGarage`
just appends).

**Fix:**
- Added `@State private var savedCarId: String?`.
- `saveCar()` short-circuits when `savedCarId` is already set: it skips
  `addCarToGarage` + `saveProfile` and only retries the photo step, preventing
  duplicate cars.
- Split the post-save continuation into `completeSave()`, which uploads the
  photo only if it hasn't already succeeded (`uploadedPhotoURL == nil`) and
  only dismisses on success.
- `uploadPhoto` now returns `Bool`; on failure `completeSave` leaves
  `isSavingProfile = false`, keeps the sheet open, and surfaces `photoError`
  (already wired to `CarPhotoEditorSection`). The user can retry `Save` safely.
- On profile-save failure, `savedCarId` is reset to `nil` so a full retry is
  still possible.

**File:** `Views/CarSelectorView.swift` (`AddCarView`)

### Task 4 — Sparkline PB marker

**Outcome:** Already implemented. `CarDetailSparkline` renders a red `PointMark`
+ "PB" annotation at `data?.pbSparklineIndex` (`Views/CarDetailView/
CarDetailSparkline.swift`). No change needed.

## Build

```
cd ios/FastTrack && xcodebuild build-for-testing \
  -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug CODE_SIGNING_ALLOWED=NO
```

## Backward compatibility

All changes are client-only iOS view logic. No API contract or DB migration
changes. No impact on old app releases.
