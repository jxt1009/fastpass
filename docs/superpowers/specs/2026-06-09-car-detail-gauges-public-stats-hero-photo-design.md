# Car Detail Polish: Animated Gauges, Public Car Detail Stats, Hero Photo Edit

**Date:** 2026-06-09
**Status:** Approved design, ready for implementation plan
**Source branch:** `feat/integration` (merged to `main` at `703f4c7`)
**Target branch(es):** three PRs from `main` once worktrees are cut
**Worktrees:** `.worktrees/ios-pb-gauges-animated`, `.worktrees/ios-public-car-stats-fix`, `.worktrees/ios-hero-photo-edit`
**Style:** additive iOS-only changes, no backend changes, no API or schema changes, conventional commits

## 0. North star

The `CarDetailView` (own-profile per-car hub) and `PublicCarDetailView` (read-only
per-car hub for another user's garage) should feel like a credible per-car
performance dashboard. Today they:

- Render a **decorative** `CarDetailGauge` arc with no progress signal — users
  see a constant background bar regardless of how fast their car actually is.
- Show **"No driving data recorded for this car yet."** on the public side for
  users whose `car_stats_data` blob is non-empty but doesn't contain a key
  matching the garage car id (or whose stats haven't been uploaded by the
  other device). The stat grid below is fine; the gauges and the empty state
  fight each other.
- Render a public garage card with **two chevrons** (system disclosure
  indicator + card's own `chevron.right`).
- Force users to open the full `EditCarView` sheet to change a car photo,
  with no way to re-crop an existing photo without picking it again from the
  Photos library (which is impossible — they only have the existing photo).

This spec addresses all four, iOS-only, in three small PRs.

## 1. Product principles

| Principle             | Meaning                                                                              |
|-----------------------|--------------------------------------------------------------------------------------|
| Car-first             | Stats belong to a car; per-car surfaces are the primary view.                        |
| Credible over flashy  | Progress bars, gauges, and stats should reflect real data, not decorative fills.     |
| Additive compatibility| No backend or API changes; old app releases remain valid.                            |
| Surgical changes      | Touch only the four call-sites; do not refactor surrounding structure.               |

## 2. Three PRs, three small worktrees

All three branch from latest `origin/main`. They can ship in any order; the
PRs are independent. They are sequenced here roughly by risk (lowest first):

1. `fix(ios): animate PB gauges on car detail view` — `.worktrees/ios-pb-gauges-animated`
2. `fix(ios): render public car detail stats and remove duplicate chevron` — `.worktrees/ios-public-car-stats-fix`
3. `feat(ios): edit car photo from the hero in car detail view` — `.worktrees/ios-hero-photo-edit`

## 3. PR 1: Animated PB gauges on own-profile `CarDetailView`

### 3.1 Current state (verified on `main` @ `703f4c7`)

- `ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift` — the gauge
  takes `title`, `value`, `unit`, `color`, optional `setOn`. It draws a
  decorative `GaugeArc()` twice (lines 57-63) with no `trim`, no
  `progress` parameter, and no animation modifier.
- `ios/FastTrack/FastTrack/Views/CarDetailView.swift:227-244` — the gauge
  calls in `pbGauges` don't pass any progress hint.
- `CarDetailData.derive(...)` already exposes `bestTopSpeed: Double?` and
  `bestZeroToSixty: Double?` (m/s and seconds respectively), which is all
  the new wiring needs.

### 3.2 Scope

- **Add a `progress: Double?` parameter to `CarDetailGauge`.** When `nil`,
  render the arc decorative (current behavior). When non-nil, render two
  stacked arcs: a faded full track (`color.opacity(0.18)`) and a colored
  arc trimmed `from: 0, to: progress` with `.animation(.easeInOut(0.35),
  value: progress)`.
- **Add `ios/FastTrack/FastTrack/Models/CarDetailGaugeProgress.swift`** — a
  pure `enum` with three statics:
  - `topSpeedProgress(speedMps:fullScaleMps:)` — defaults to `fullScaleMps = 80`
    (≈ 179 mph), clamps to `[0, 1]`.
  - `zeroSixtyProgress(seconds:best:worst:)` — defaults to `best = 2, worst = 8`,
    maps `seconds` so 2s = 1.0, 8s = 0.0, clamped to `[0, 1]`.
  - `visualProgress(_:minimumVisible:)` — for the visible-safety boost:
    tiny non-zero values get a 0.12 floor so the arc stays visible.
- **Update `CarDetailView.pbGauges`** to pass:
  - `progress: data?.bestTopSpeed.map(CarDetailGaugeProgress.topSpeedProgress)`
  - `progress: CarDetailGaugeProgress.zeroSixtyProgress(seconds: data?.bestZeroToSixty)`
- **Update the doc comment on `CarDetailGauge`** to describe the progress
  parameter and its animation behavior.

### 3.3 Edge cases

- `data == nil` (car removed) — `progress` is `nil`; gauge renders decorative arc.
- `data.bestTopSpeed == 0` (no drives) — `topSpeedProgress` returns 0, which
  `visualProgress` boosts to 0.12 minimum so the arc still shows a sliver.
- `data.bestZeroToSixty == nil` — `zeroSixtyProgress` returns 0 → 0.12 floor.
- Unit change (mph ↔ km/h) — `value` is unit-converted, `progress` is in
  raw m/s. Progress stays stable across unit changes (intentional: the arc
  represents the magnitude of the metric, not the displayed number).
- Animation re-trigger on PB change — SwiftUI's `.animation(_:value:)` on
  `progress` retriggers on every value change. The token-driven confetti
  in `CarDetailView` already gates unrelated re-renders; we rely on
  `LifecycleModifier` to rebuild `data` on drive-count changes and the
  gauge re-renders accordingly.

### 3.4 Tests

- `ios/FastTrack/FastTrackTests/CarDetailGaugeProgressTests.swift` (new) —
  pure unit tests on the helper, covering:
  - nil and out-of-range inputs
  - canonical inputs at 0%, 50%, 100% of each scale
  - `visualProgress` minimum-visible boost
- A source-order guard in `CarDetailDataTests.swift` or a small new
  `CarDetailGaugeProgressWiringTests.swift` that asserts `CarDetailView`'s
  `pbGauges` passes a non-nil `progress` when `data?.bestTopSpeed` is set.
  Use the same `readSourceFile` pattern that `PublicProfileRedesignTests`
  uses (read the file from disk, regex-assert presence).

### 3.5 Likely files

- `ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift`
- `ios/FastTrack/FastTrack/Models/CarDetailGaugeProgress.swift` (new)
- `ios/FastTrack/FastTrack/Views/CarDetailView.swift`
- `ios/FastTrack/FastTrackTests/CarDetailGaugeProgressTests.swift` (new)
- `ios/FastTrack/FastTrackTests/CarDetailGaugeProgressWiringTests.swift` (new, source guard)

### 3.6 Acceptance

- Both `CarDetailGauge` calls in `CarDetailView.pbGauges` receive a non-nil
  `progress` derived from `data`.
- The arc animates with `.easeInOut(0.35)` whenever the underlying value
  changes (verified by hand, plus the wiring test).
- `CarDetailGauge` retains backward compatibility: existing call sites
  without a `progress` argument still compile and render decoratively.

## 4. PR 2: Public car detail stats not loading + duplicate chevron

### 4.1 Current state (verified on `main` @ `703f4c7`)

- `ios/FastTrack/FastTrack/Views/PublicProfileView.swift:302-308` —
  `statsByCarId(blob:)` decodes the JSON blob into `[String: CarStats]`
  and returns `[:]` for any decode failure (empty, malformed, missing).
- The Garage section in `PublicProfileView.swift:81-104` passes
  `stats: statsByCarId[car.id]` to `PublicCarDetailView` and the
  `PublicGarageCard`.
- `ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift:131-167` — when
  `stats == nil`, the `statsGrid` shows "No driving data recorded for
  this car yet." The `pbgaugeRow` (lines 101-116) calls
  `PublicCarDetailGauge` with `value: topSpeedDisplay` and
  `value: zeroSixtyDisplay`, both of which are `nil` when `data.bestTopSpeed`
  is `nil` (which is the case when `stats == nil` or `stats.bestTopSpeed <= 0`).
  `PublicCarDetailGauge` renders "—" when `value` is nil.
- `ios/FastTrack/FastTrack/Views/PublicGarageCard.swift:47-50` — explicit
  `chevron.right` Image, alongside the `NavigationLink` in the parent that
  (in iOS 17+ `List`) still renders the system disclosure indicator
  despite `.buttonStyle(.plain)`.

### 4.2 Scope

#### 4.2.1 Investigate the empty-state mismatch

- Add a `#if DEBUG` `os_log` in `PublicProfileView.statsByCarId(blob:)`
  that records, for a non-empty blob:
  - decoded key count
  - first key (truncated)
  - the first garage car id (truncated)
  This is the diagnostic that proves the key-mismatch hypothesis. The log
  is `#if DEBUG` so it does not ship to TestFlight builds.
- Hit a known-good public profile via `curl /api/v1/users/<u>` against
  staging. Capture the raw `garage` and `car_stats_data` JSON to confirm
  whether the keys align. The expected answer (per
  `backend/internal/app/handlers_test.go:1364-1398` and
  `ios/FastTrack/FastTrack/Services/APIService.swift:264-268`):
  - Backend stores `car_stats_data` as an opaque text blob.
  - iOS uploads the dictionary keyed by the `CarStats.carId` (which equals
    the `UserCar.id` UUID).
  - Both should line up; the failure is in some user account where the
    blob is empty (legacy signup, web-only signup, or a stats upload
    that silently failed).

#### 4.2.2 Promote `statsByCarId(blob:)` to a testable static

- Move it from a `private` instance method to
  `enum PublicProfileStatsLookup { static func byCarId(blob: String?) -> [String: CarStats] }`
  in `ios/FastTrack/FastTrack/Models/ProfileRedesignHelpers.swift` (the
  file already holds `PublicProfileStats` and `GarageCardShortStats`).
- Update `PublicProfileView` to call the static.
- Add a `decodingTrace` (still `#if DEBUG`) that records: blob length,
  decoded key count, sample key, the lookup miss for each car.

#### 4.2.3 Distinguish "no data" from "data not synced"

- In `PublicCarDetailView.statsGrid` empty state, render **two** cases:
  - Blob empty (or `profile.carStatsData == nil`) → "No driving data
    recorded for this car yet." (current copy, unchanged).
  - Blob non-empty but no key matches `car.id` → "Stats haven't synced
    for this car yet." (new copy, plus a one-line subtle hint).
- This is a small, additive UI change. No new components.

#### 4.2.4 Remove the duplicate chevron

- **Recommended:** drop the explicit `chevron.right` from
  `PublicGarageCard`. The system disclosure indicator (when present) is
  the consistent affordance and matches the rest of the `List`
  (Stats rows, Followers, etc.). The card already says "tap to view"
  via its `accessibilityLabel` and the `NavigationLink` wrap.
- Update the regression test
  `ios/FastTrack/FastTrackTests/PublicProfileRedesignTests.swift:44-48`
  to assert the chevron is **absent**.
- Add a new test
  `testPublicProfileView_KeepsNavigationLinkToPublicCarDetailView` that
  re-asserts the `PublicProfileView` Garage section still wires
  `NavigationLink { PublicCarDetailView(...) }` so we did not regress
  navigation.
- The existing `testPublicGarageCard_DoesNotOwnItsOwnTapHandler` (lines
  55-76) stays unchanged.

### 4.3 Tests

- `ios/FastTrack/FastTrackTests/PublicProfileStatsLookupTests.swift` (new)
  — pure unit tests on the static:
  - `nil` blob → `[:]`
  - empty string → `[:]`
  - malformed JSON → `[:]`
  - valid JSON with one key → `["c1": stats]`
  - valid JSON with multiple keys, no missing → correct map
  - valid JSON with extra keys not in garage → ignored
  - JSON with leading/trailing whitespace (defensive) → handled
- Update `PublicProfileRedesignTests`:
  - flip the `HasTrailingChevronHint` test to assert the chevron is absent
  - add a source-order guard for the new empty-state string
- A source-order guard in a new
  `PublicCarDetailViewEmptyStateTests.swift` asserting the new copy
  appears for the non-empty-blob, no-key-match path.

### 4.4 Likely files

- `ios/FastTrack/FastTrack/Views/PublicProfileView.swift`
- `ios/FastTrack/FastTrack/Views/PublicGarageCard.swift`
- `ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift`
- `ios/FastTrack/FastTrack/Models/ProfileRedesignHelpers.swift`
- `ios/FastTrack/FastTrackTests/PublicProfileStatsLookupTests.swift` (new)
- `ios/FastTrack/FastTrackTests/PublicProfileRedesignTests.swift` (update)
- `ios/FastTrack/FastTrackTests/PublicCarDetailViewEmptyStateTests.swift` (new)

### 4.5 Acceptance

- A public profile with a non-empty `car_stats_data` blob that contains
  the matching car id renders the gauges and stat grid with the user's
  data (no regression on the happy path).
- A profile with an empty blob shows "No driving data recorded for this
  car yet." (unchanged).
- A profile with a non-empty blob but no matching key shows the new
  "Stats haven't synced for this car yet." copy.
- A render check (manual screenshot, or a SwiftUI preview) of
  `PublicProfileView` shows exactly **one** right-pointing chevron per
  garage card.

## 5. PR 3: Edit car photo from the hero in own-profile `CarDetailView`

### 5.1 Current state (verified on `main` @ `703f4c7`)

- `ios/FastTrack/FastTrack/Views/CarDetailView.swift:176-211` — `hero` is a
  `ZStack(alignment: .bottomLeading)` with the photo, a gradient overlay,
  and the nickname/display text. The whole stack has a single tap
  gesture that opens `AvatarZoomView` via `zoomedPhoto`.
- `ios/FastTrack/FastTrack/Views/CarDetailView.swift:93-98` — the
  toolbar trailing `pencil` button opens the full `EditCarView` sheet
  (for nickname + photo).
- `ios/FastTrack/FastTrack/Views/EditCarView.swift:42-50` — the Photo
  section uses `CarPhotoEditorSection`, which handles
  `PhotosPickerItem` → `PhotoCropView` → `uploadCarPhoto` for new picks.
  It does **not** support "use the existing photo as the crop source".
- `ios/FastTrack/FastTrack/Models/PhotoCropContext.swift` — defines
  `enum PhotoCropContext { case car, avatar }` and
  `struct CropImageSource: Identifiable { let image: UIImage; let context: PhotoCropContext }`.
- `ios/FastTrack/FastTrack/Views/PhotoCropView.swift` — full-screen
  cropper that takes `image: UIImage` and `context: PhotoCropContext`
  and returns a cropped `UIImage?` via the trailing closure.

### 5.2 Scope

#### 5.2.1 New `CarHeroPhotoEditorSheet`

- New file: `ios/FastTrack/FastTrack/Views/Components/CarHeroPhotoEditorSheet.swift`
  — a small self-contained sheet view that:
  - Owns `@State` for `pickedPhoto: PhotosPickerItem?`,
    `sourceImage: UIImage?` (the loaded existing photo or the picked photo),
    `croppingImage: CropImageSource?`,
    `isLoading: Bool`, `isUploading: Bool`, `errorMessage: String?`.
  - Public API:
    - `let carId: String`
    - `let existingPhotoURL: String?` (i.e. `car.photoUrl`)
    - `var onUploadComplete: (URL) -> Void` — called with the new photo
      URL after a successful upload; the parent is responsible for
      updating `profileManager.profile.garage[carId].photoUrl`.
  - On appear, if `existingPhotoURL` is non-nil, kick off a
    `URLSession.shared.data(from:)` on a background actor, decode to
    `UIImage`, hop back to `@MainActor`, set `sourceImage`. While in
    flight, render a small spinner. On failure, fall through to the
    picker (no error dialog).
  - When `sourceImage` is set, present `PhotoCropView(image: sourceImage,
    context: .car)` via a `.fullScreenCover` on `croppingImage`.
  - On crop confirm, resize to 800px max
    (`image.resizedForAvatar(maxDimension: 800)`), call
    `APIService.shared.uploadCarPhoto(carId:carId:data:)`,
    fire `onUploadComplete(url)`, dismiss the sheet.
  - On crop cancel, dismiss the sheet, no upload, no state change.
  - On upload failure, show an inline `errorMessage` in red below the
    controls (matches `CarPhotoEditorSection` styling).

#### 5.2.2 Wire the sheet into `CarDetailView.hero`

- Add `@State private var showingHeroPhotoEditor = false` and
  `@State private var heroPhotoError: String?` to `CarDetailView`.
- Add a pencil overlay on the bottom-trailing corner of the hero.
  The current `hero` is a `ZStack(alignment: .bottomLeading)` with the
  photo, a gradient overlay, and the bottom-leading text. We add a
  fourth child: a `Button` containing the pencil SF Symbol, aligned
  to the bottom-trailing edge via a wrapping
  `HStack { Spacer(); button }` and a wrapping
  `VStack { Spacer(); button }` (or, equivalently, set
  `.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)`
  on the button). The button label is the SF Symbol; tap target is at
  least 44pt (use `.frame(width: 44, height: 44)`). Color is
  `Color.white` with a translucent black circle background to remain
  legible over both photo and gradient overlay.
- The button sets `showingHeroPhotoEditor = true`.
- The button has `accessibilityLabel("Edit car photo")`.
- A `.sheet(isPresented: $showingHeroPhotoEditor)` presents
  `CarHeroPhotoEditorSheet` with the `carId`, the `photoUrl` from
  `car?.photoUrl`, and an `onUploadComplete` callback that:
  - Reads `var profile = profileManager.profile`.
  - Updates `profile.garage[i].photoUrl = newURL` (find by `carId`).
  - Calls `profileManager.saveProfile(profile)`.
  - Triggers `refresh()` to recompute `data`.
- The existing toolbar pencil button stays (it opens the full
  `EditCarView` for nickname + photo). The hero button is a focused
  photo-only entry point.

#### 5.2.3 Why a new component, not extending `CarPhotoEditorSection`

- `CarPhotoEditorSection` is a `Form` row used by `AddCarView` and
  `EditCarView`. Its API is `pickedImage: Binding<UIImage?>` plus
  `existingPhotoURL: String?` plus `onRemove` — it owns the picker and
  the cropper, but **not** the "use existing photo as crop source" flow.
- Extending it would force `AddCarView` and `EditCarView` to plumb a
  new `onUseExisting` callback that they don't need. The cost of
  teaching two unrelated callers about a feature they don't use is
  higher than the cost of a sibling component.
- The new `CarHeroPhotoEditorSheet` is a *sheet*, not a form row, so
  the visual surface is different anyway.

### 5.3 Edge cases

- **No existing photo:** `existingPhotoURL == nil` → skip the download,
  show `PhotosPicker` only. The user can pick a new photo; the crop flow
  is the same.
- **Download fails (404, timeout, no network):** fall through to the
  picker. No error dialog; the user can pick a new photo from the
  library instead.
- **User cancels crop:** no upload, sheet dismisses, the existing photo
  stays. (Confirmed in design discussion.)
- **Upload fails (network, 5xx):** show inline red `errorMessage`,
  leave the sheet open, let the user retry. The spinner stops.
- **Race condition — user taps the pencil again while a previous
  edit's sheet is open:** the existing `.sheet(isPresented:)` will be
  no-op because the bool is already `true`. The download task may
  restart; add a guard that bails if a download is already in flight
  (`@State private var isLoading: Bool`).
- **Car removed from garage while sheet is open:** the callback's
  `first(where: { $0.id == carId })` returns nil, so no state change
  happens. Sheet can still dismiss; the next refresh will show
  "Car Removed".

### 5.4 Tests

- A `URLProtocol` mock test in
  `ios/FastTrack/FastTrackTests/CarHeroPhotoEditorSheetTests.swift`:
  given a known `photoUrl`, the sheet's "load existing photo" step
  returns the expected `UIImage`. Mock the response with a tiny PNG.
  Verify the resize path (`resizedForAvatar(maxDimension: 800)`) is
  called.
- A source-order guard in the same test file asserting
  `CarDetailView` includes a `pencil.circle.fill` overlay and presents
  `CarHeroPhotoEditorSheet` (read the file, regex-assert presence).
- A pure `CarHeroPhotoEditorSheetLogicTests.swift` (or extension of
  an existing logic test) for any pure helper logic added to the sheet
  (e.g. URL normalization, file-size cap).

### 5.5 Likely files

- `ios/FastTrack/FastTrack/Views/Components/CarHeroPhotoEditorSheet.swift` (new)
- `ios/FastTrack/FastTrack/Views/CarDetailView.swift`
- `ios/FastTrack/FastTrack.xcodeproj/project.pbxproj` (add the new file)
- `ios/FastTrack/FastTrackTests/CarHeroPhotoEditorSheetTests.swift` (new)

### 5.6 Acceptance

- Tapping the new pencil overlay on `CarDetailView`'s hero presents the
  editor sheet.
- Choosing "Use existing photo" (when one exists) downloads the current
  photo and shows it in `PhotoCropView`. The user can pan/zoom/crop and
  confirm; the cropped result uploads and the hero photo updates in
  place.
- Cancel does not change the photo.
- The existing toolbar pencil button (opens `EditCarView`) remains
  functional and unchanged.

## 6. Backward compatibility

- **No backend changes.** No migrations, no API additions, no JSON
  contract changes.
- **No shared types change.** `CarDetailGauge` gains an optional
  parameter with a default of `nil`; existing call sites compile
  unchanged.
- **No component deletions.** `CarPhotoEditorSection` stays as-is for
  `AddCarView` and `EditCarView`.
- **Old app releases** are unaffected: this is additive UI work that
  ships in a new iOS build.

## 7. Risks

| Risk                                                                 | Mitigation                                                                                 |
|----------------------------------------------------------------------|--------------------------------------------------------------------------------------------|
| `CarDetailGauge` API change breaks the public variant.               | We do not change `PublicCarDetailGauge` in PR 1. PR 1 is own-profile only.                  |
| Public stats lookup fix masks a real backend key-mismatch bug.       | The `#if DEBUG` trace exposes the raw key shape; if a true mismatch surfaces, file a backend issue rather than a silent client-side fix. |
| Hero photo editor changes photo state on a sheet that's outside `EditCarView`. | The save flow mirrors `EditCarView.save()` and the `onUploadComplete` callback updates the profile via the same `profileManager.saveProfile` path. Round-trip tests on `EditCarView` continue to pass. |
| `URLSession.shared.data(from:)` runs on a background actor.         | The task is cancelled if the sheet dismisses before completion (use a `Task` stored in `@State`). |
| Confetti/lifecycle re-renders interfere with progress animation.     | The gauge's `.animation(.easeInOut(0.35), value: progress)` is local to the gauge. Confetti is an overlay and does not affect arc re-renders. |

## 8. Verification commands

```bash
cd ios/FastTrack
cp FastTrack/Secrets.swift.template FastTrack/Secrets.swift
xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Per-PR:

- PR 1: `xcodebuild test ... -only-testing:FastTrackTests/CarDetailGaugeProgressTests`
- PR 2: `xcodebuild test ... -only-testing:FastTrackTests/PublicProfileStatsLookupTests`
- PR 3: `xcodebuild test ... -only-testing:FastTrackTests/CarHeroPhotoEditorSheetTests`

Manual verification per PR:

- PR 1: open the app, navigate to any car in the garage, confirm the
  top-speed and 0-60 arcs reflect a non-decorative value (e.g. 110 mph
  fills to ~60% of the arc; 4.5s 0-60 fills to ~58% of the 1-8s arc).
- PR 2: navigate leaderboard → a user with multiple cars → confirm
  one chevron per card. Tap a card; if the user has stats, the gauges
  render; if the blob is non-empty but no key matches, the new
  "haven't synced" copy shows.
- PR 3: open any car with a photo, tap the new pencil overlay on the
  hero, confirm "Use existing photo" downloads the photo into the
  cropper. Cancel: photo unchanged. Crop and confirm: photo updates.

## 9. Plan maintenance

- Update this file at each PR's merge.
- Each PR body links back to this spec and calls out which section it
  implements.
- If the diagnostic in PR 2 surfaces a real backend key-mismatch bug,
  open a separate issue and link it from the PR body. Do not silently
  work around it on the client.
