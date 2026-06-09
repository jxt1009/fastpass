# Plan: Phase 1 — Targeted UX Fixes

**Date:** 2026-06-08
**Status:** Ready for implementation
**Branch:** `feat/garage-hub-ux-fixes`
**Worktree:** `.worktrees/ux-fixes`
**Base:** Latest `main` **after Phase 0 (`feat/design-system-alignment`) has merged**
**Conventional commits:** Required (feat, fix, refactor)

These four changes are independent and ship before the Analytics→Garage merge.

> **Branch order:** Phase 0 (`feat/design-system-alignment`) must be cut from main, implemented, and merged first. Then cut Phase 1 from the post-Phase-0 main.

---

## 1. Add edit car button to CarDetailView toolbar

**Goal:** Users can tap an obvious pencil icon in CarDetailView's toolbar to edit the car's nickname, photo, etc. Currently the only way to edit a car is via a long-press context menu on GarageView or ProfileView, which is undiscoverable.

**Commit:** `feat(ios): add edit car button to CarDetailView toolbar`

### What to change

**File:** `ios/FastTrack/FastTrack/Views/CarDetailView.swift`

1. Add a state variable for the edit sheet:
   ```swift
   @State private var showingEditCar = false
   ```

2. Replace the current toolbar content (which only shows "Active"/"Set Active") with an `HStack` that includes an edit button:
   - The existing active/set-active logic stays
   - Add a `Button` with `Image(systemName: "pencil")` and `.foregroundColor(.ftBlue)` that sets `showingEditCar = true`
   - The pencil icon appears only when `car != nil` (same condition as the active/set-active buttons)

3. Add a `.sheet(isPresented: $showingEditCar)` modifier on the outer `Group` (or on the `content` view), presenting `EditCarView(carId: carId)`.

4. The `EditCarView` already exists at `ios/FastTrack/FastTrack/Views/EditCarView.swift` and accepts `carId: String`. It handles nickname editing and photo upload/removal. No changes needed to EditCarView.

### Verification

- Build succeeds: `xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`
- CarDetailView shows a pencil icon in the trailing toolbar alongside the "Active"/"Set Active" button
- Tapping the pencil icon presents EditCarView as a sheet
- Editing a nickname or photo and tapping Save updates the car in ProfileManager
- Dismissing the sheet returns to CarDetailView with updated data (because CarDetailView reads `car` from `ProfileManager.shared`)

### What NOT to change

- Don't modify EditCarView itself
- Don't change GarageView's context menu (it can coexist with the CarDetailView edit button)
- Don't add edit functionality to the public car detail view (PublicCarDetailView is read-only)

---

## 2. Replace Profile garage section with "Your Garage" link

**Goal:** The ProfileView currently has a full garage section with car cards, add-car button, and selectable car rows. This duplicates GarageView (which is now the dedicated hub). Replace it with a single tappable row that says "Your Garage" with a car count badge and a chevron, placed above the achievements strip.

**Commit:** `refactor(ios): replace profile garage section with link to GarageView`

### What to change

**File:** `ios/FastTrack/FastTrack/Views/ProfileView.swift`

1. **Remove the `garageSection` computed property** (approximately lines 222-284). This includes:
   - The `LazyVGrid` of `CarGarageCard`s
   - The "View Garage" NavigationLink
   - The "+" add-car button
   - The empty state ("No cars in garage")

2. **Remove `@State private var showingAddCar = false`** (line ~14)

3. **Remove the `.sheet(isPresented: $showingAddCar)` modifier** (line ~69-71) that presents `AddCarView()`

4. **Remove `CarGarageCard` struct** (approximately lines 493-589). This struct is only instantiated at the `garageSection` line we're removing. Verify no other file references `CarGarageCard` — it's only in ProfileView.swift.

5. **Remove `selectCar` function** (approximately lines 412-416). It's only called by `CarGarageCard`'s `onSelect` callback.

6. **Add a "Your Garage" NavigationLink row** in the body's `VStack`, placed between `profileHeader` and `RecentAchievementsStrip`. The new row should:
   ```swift
   NavigationLink {
       GarageView()
   } label: {
       HStack {
           Image(systemName: "car.2.fill")
               .foregroundColor(.ftBlue)
           Text("Your Garage")
               .fontWeight(.semibold)
           Spacer()
           if let profile = profileManager.profile, !profile.garage.isEmpty {
               Text("\(profile.garage.count) car\(profile.garage.count == 1 ? "" : "s")")
                   .font(.subheadline)
                   .foregroundColor(.secondary)
           }
           Image(systemName: "chevron.right")
               .font(.caption)
               .foregroundColor(.secondary)
       }
   }
   ```
   Wrapped in an `InstrumentCard` for visual consistency.

7. **Keep `CarPhotoThumbnail`** (lines ~593-633). It's still used by `PublicGarageCard.swift`. Do not delete it.

8. **Keep `CarStatsRow`** (lines ~635-649). It's still used by `CarDetailView.swift`. Do not delete it.

9. **Keep `StatMini`** (lines ~651-661). It's still used by `GarageView.swift`. Do not delete it.

### Body order after changes

```swift
VStack(alignment: .leading, spacing: 14) {
    profileHeader
    garageLinkRow          // NEW
    RecentAchievementsStrip(driveManager: driveManager)
    // garageSection REMOVED
    if driveManager.isLoadingDrives { ... } else {
        mainStatsGrid
        headlineSpeedGrid
    }
    privacyToggleCard
    deleteAccountButton
    signOutButton
}
```

### What NOT to change

- Don't modify `GarageView.swift` — it already has the add-car button and car grid
- Don't modify `PublicGarageCard.swift` or `PublicProfileView.swift`
- Don't delete `CarPhotoThumbnail`, `CarStatsRow`, or `StatMini`
- Don't change the `showingSetup` sheet or the toolbar gear/pencil buttons

### Verification

- Build succeeds
- ProfileView shows "Your Garage" row with car count between header and achievements
- Tapping "Your Garage" pushes GarageView
- "Your Garage" shows "0 cars" or "1 car" / "2 cars" based on garage count
- No `CarGarageCard`, `showingAddCar`, or `selectCar` references remain in ProfileView.swift
- `PublicGarageCard` still compiles (it uses `CarPhotoThumbnail` which we kept)

---

## 3. Add StatInfo glossary to performance breakdown and overview cards

**Goal:** Every analytics card that shows a computed stat now has an ℹ️ button that explains what the stat means and how it's calculated. Currently only "Driving Score" has this. Add it to all four PerformanceBreakdownCards and two overview cards.

**Commit:** `feat(ios): add StatInfo glossary to analytics and car detail cards`

**Important:** `PerformanceBreakdownCard` is moved to `SharedComponents.swift` (from `AnalyticsView.swift`) in this step, so it can be reused in `CarDetailView` (Phase 2.3) after `AnalyticsView` is deleted (Phase 2.4). Do NOT leave `PerformanceBreakdownCard` in `AnalyticsView.swift`.

### What to change

**File:** `ios/FastTrack/FastTrack/Views/SharedComponents.swift`

1. **Add three new `StatInfo` entries** after the existing ones:

   ```swift
   static let cornering = StatInfoEntry(
       "Cornering",
       summary: "The highest lateral G-force recorded during your drives.",
       howCalculated: "Peak lateral G-force is derived from GPS heading changes. The value shown is the maximum across all filtered drives. Values above 0.6g indicate spirited cornering; above 0.8g is race-driver territory.",
       unit: "G"
   )

   static let consistency = StatInfoEntry(
       "Consistency",
       summary: "How repeatable your performance is drive-to-drive.",
       howCalculated: "Coefficient of variation of top speeds across drives. The standard deviation of max speeds is divided by the mean, then inverted to a 0–100 score. Higher means your top speeds are more predictable from drive to drive.",
       unit: "0–100"
   )

   static let periodComparison = StatInfoEntry(
       "Period Comparison",
       summary: "How your average max speed this period compares to the previous equivalent period.",
       howCalculated: "The average max speed across all drives in the current time window minus the same metric from the prior window. A delta above +0.5 speed-units shows as 'Up'; below −0.5 as 'Down'; within ±0.5 as 'Same'.",
       unit: nil
   )

   static let avgMaxSpeed = StatInfoEntry(
       "Avg Max Speed",
       summary: "The average of your highest speeds across all filtered drives.",
       howCalculated: "Sum of each drive's max speed divided by the number of drives. Not the average speed of a single drive — this measures the typical ceiling of your driving sessions.",
       unit: "speed"
   )
   ```

2. **Move `PerformanceBreakdownCard` from `AnalyticsView.swift` to `SharedComponents.swift`** and add the `info` parameter. Copy the struct exactly and add the parameter:

   ```swift
   struct PerformanceBreakdownCard: View {
       let title: String
       let value: String
       let category: String
       let icon: String
       let color: Color
       var info: StatInfoEntry? = nil  // ADD THIS

       var body: some View {
           InstrumentCard {
               VStack(alignment: .leading, spacing: 8) {
                   HStack {
                       Image(systemName: icon)
                           .foregroundColor(color)
                           .font(.title3)
                       Spacer()
                       if let info { StatInfoButton(entry: info) }  // ADD THIS
                   }

                   Text(value)
                       .font(.headline)
                       .fontWeight(.bold)

                   Text(title)
                       .font(.caption)
                       .foregroundColor(.secondary)

                   Text(category)
                       .font(.caption2)
                       .padding(.horizontal, 8)
                       .padding(.vertical, 2)
                       .background(color.opacity(0.2))
                       .foregroundColor(color)
                       .cornerRadius(4)
               }
           }
       }
   }
   ```

**File:** `ios/FastTrack/FastTrack/Views/AnalyticsView.swift`

1. **Remove the `PerformanceBreakdownCard` struct** (it has been moved to `SharedComponents.swift`).
2. **Add `import SharedComponents` if not already present.**
3. **Wire each breakdown card call site** in `performanceBreakdown` with the appropriate `StatInfo`:
   ```swift
   PerformanceBreakdownCard(
       title: "Best 0-60",
       value: ...,
       category: ...,
       icon: "bolt.fill",
       color: .red,
       info: StatInfo.zeroToSixty      // ADD
   )
   PerformanceBreakdownCard(
       title: "Cornering",
       value: ...,
       category: ...,
       icon: "arrow.triangle.turn.up.right.circle.fill",
       color: .purple,
       info: StatInfo.cornering        // ADD
   )
   PerformanceBreakdownCard(
       title: "Driving Style",
       value: ...,
       category: ...,
       icon: "waveform.path",
       color: .cyan,
       info: StatInfo.smoothness       // ADD
   )
   PerformanceBreakdownCard(
       title: "Consistency",
       value: ...,
       category: ...,
       icon: "target",
       color: .mint,
       info: StatInfo.consistency       // ADD
   )
   ```
4. **Add `info` to "Avg Max Speed"** in `performanceOverview` and "vs Previous Period" in `periodComparisonCard` using `StatInfo.avgMaxSpeed` and `StatInfo.periodComparison`.

### What NOT to change

- Do NOT delete `AnalyticsView.swift` — Phase 2.4 handles that
- Do NOT change the `AnalyticsCard` struct (it stays in `AnalyticsView.swift` and is used by the GarageView summary in Phase 2.2)
- Do NOT move `StatInfoButton` — it is already in `SharedComponents.swift`

### Verification

- Build succeeds
- `PerformanceBreakdownCard` is now in `SharedComponents.swift` and has the `info:` parameter
- Tapping ℹ️ on any `PerformanceBreakdownCard` shows a popover with title, summary, and howCalculated
- All 7 `StatInfo` entries exist and have correct content
- Phase 2.3 can now import `PerformanceBreakdownCard` from `SharedComponents.swift` without needing `AnalyticsView.swift`

---

## 4. Fix tappable-in-tappable in PublicProfileView

**Goal:** The public profile header has an `.onTapGesture` on the avatar for zoom, but this sits inside a `List` section row. On some iOS versions, the List row's gesture recognizer conflicts with the avatar tap, making it unresponsive. Replace the `.onTapGesture` with an explicit `Button` so SwiftUI can properly distinguish the tap target.

**Commit:** `fix(ios): resolve tappable-in-tappable conflict in public profile header`

### What to change

**File:** `ios/FastTrack/FastTrack/Views/PublicProfileView.swift`

In the `narrowHeader` function (around line 108), find the avatar section:

```swift
avatarView(profile)
    .onTapGesture { presentAvatarZoom(profile) }
```

Replace with:

```swift
Button {
    presentAvatarZoom(profile)
} label: {
    avatarView(profile)
}
.buttonStyle(.plain)
```

This makes the avatar an explicit button rather than a generic tap gesture, which SwiftUI can properly route through the List row's gesture system without conflict.

### Verification

- Build succeeds
- Tapping the avatar in public profile presents the zoom view
- The followers/following buttons in the same header row still work
- The follow/unfollow button still works
- Garage section cards still navigate to PublicCarDetailView

---

## General verification for all Phase 1 changes

After completing all four changes:

```bash
cd ios/FastTrack
cp FastTrack/Secrets.swift.template FastTrack/Secrets.swift
xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Then run the backend check (no backend changes, but verify nothing broke):

```bash
cd backend
CGO_ENABLED=1 go build ./... && CGO_ENABLED=1 go vet ./... && go test ./... -v -timeout 60s
```