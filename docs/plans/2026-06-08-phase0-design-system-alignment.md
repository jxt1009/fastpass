# Plan: Phase 0 — Design System Alignment

**Date:** 2026-06-08
**Status:** Ready for implementation
**Branch:** `feat/design-system-alignment`
**Worktree:** `.worktrees/design-alignment`
**Base:** Latest `main`
**Conventional commits:** Required (style, refactor)

Must land before Phase 1 and Phase 2. Branch from main, implement, merge, then cut Phase 1 from the post-Phase-0 main.

---

## Audit Summary

The design system (`DesignSystem.swift`) defines a clean "garage" language: `InstrumentCard` (ftCardBg, cornerRadius 12, Spacing.md), `Color.ftBlue/ftAmber/ftGreen/ftRed`, `Spacing` tokens, and `DashboardGauge`. ContentView and GarageView are the gold standard. But most other views regress to system `.blue`, `systemGray6` cards, `List`-style rows, and hardcoded spacing.

**Key inconsistencies:**

| Problem | Affected views |
|---|---|
| `Color.blue` instead of `Color.ftBlue` | DriveDetailView, ProfileView, AnalyticsView, SocialView, DriveHistoryView, PublicProfileView, AchievementsView, NotificationsView, FindPeopleView, CarPickerView, CarSelectorView, RecentAchievementsStrip, CarPhotoEditorSection |
| `StatCard` default uses `systemGray6` inside `InstrumentCard` (double-card) | DriveDetailView, DrivePerformanceDetailView |
| `DashboardGauge` uses `systemGray6` fill + `systemGray4` stroke | ContentView, DriveDetailView |
| All spacing is hardcoded (8, 10, 12, 14, 16, 20) | Every view except ContentView |
| `AchievementCard` uses `systemBackground`/`systemGray6` instead of `InstrumentCard` | AchievementsView |
| `CarPhotoThumbnail` uses `Color.blue.opacity(0.15)` while `CarPhotoView` uses `LinearGradient(.ftBlue, .purple)` | ProfileView, PublicGarageCard |
| `PublicProfileView` and `FindPeopleView` use `LinearGradient(.blue, .purple)` for avatars | PublicProfileView, FindPeopleView, FollowersListView |
| No `ftSurfaceBg` page background on List-based views | NotificationsView, FindPeopleView, FollowersListView, CarPickerView, CarSelectorView |

---

## 0.1 — Replace `Color.blue` with `Color.ftBlue` selectively

**Commit:** `style(ios): replace system blue with ftBlue in target views`

Selective per-file replacement. **Do NOT** globally sweep — some `.blue` uses are intentional (ConfettiView rainbow palette, DrivingStyle.color semantic values). Explicitly excluded: `ConfettiView.swift`, `SignInView.swift`, `ProfileSetupView.swift`, `SettingsView.swift`, `EditCarView.swift`, `CarStats.swift`, `CarDetailData.swift`, any gradient uses in confetti/celebration contexts.

**Files to change — replace only the accent/interactive color uses:**

| File | Lines | What to change |
|---|---|---|
| `DriveDetailView.swift` | ~30 | `.blue` for pencil icon, play button, slider tint, map marker → `.ftBlue` |
| `ProfileView.swift` | ~20, 213, 217, 293, 322, 426, 488, 532, 556, 761, 764, 860, 863 | `Color.blue` (avatar placeholder bg, add-car button, toggle tint, "SELECTED" label, CarGarageCard photo bg/icon) → `Color.ftBlue`; `.tint(.blue)` → `.tint(.ftBlue)`; do NOT change `Color.blue.opacity(0.3)` inside `deleteButton` — that's a destructive styling, keep as system blue |
| `AnalyticsView.swift` | ~112 | `iconColor: .blue` in AnalyticsCarChip → `.ftBlue`; also `RecentBestCard` `.foregroundColor(.blue)` → `.ftBlue` |
| `SocialView.swift` | ~15 | `Color.blue.opacity(0.08)` (current user row highlight) → `Color.ftBlue.opacity(0.08)`; `Color.blue` (car thumbnail placeholder, "You" badge) → `Color.ftBlue` |
| `DriveHistoryView.swift` | ~110, 113 | `Color.blue.opacity(0.1)` (car pill bg), `.foregroundColor(.blue)` (car pill text) → `Color.ftBlue` variants |
| `PublicProfileView.swift` | ~211, 265 | `Color.blue` (follow button gradient) → `Color.ftBlue`; `LinearGradient(.blue, .purple)` → `LinearGradient(.ftBlue, .purple)` |
| `FindPeopleView.swift` | ~12 | `Color.blue` (follow button, "You" badge) → `Color.ftBlue`; `LinearGradient(.blue, .purple)` → `LinearGradient(.ftBlue, .purple)` |
| `FollowersListView.swift` | ~2 | `LinearGradient(.blue, .purple)` → `LinearGradient(.ftBlue, .purple)` |
| `NotificationsView.swift` | ~2 | `Color.blue` (unread dot, avatar placeholder) → `Color.ftBlue` |
| `CarPickerView.swift` | ~51, 130, 163, 215 | `.foregroundColor(.blue)` (checkmark, car icon, confirm button) → `.ftBlue` |
| `CarSelectorView.swift` | ~33, 94, 117, 119 | `.foregroundColor(.blue)` and `.fill(Color.blue.opacity(0.15))` → `.ftBlue` variants |
| `RecentAchievementsStrip.swift` | ~43 | `.foregroundColor(.blue)` ("View All" nav link) → `.ftBlue` |
| `CarPhotoEditorSection.swift` | ~3 | `Color.blue.opacity(0.15)`, `.blue` icon → `Color.ftBlue.opacity(0.15)`, `.ftBlue` |
| `PublicCarDetailView.swift` | ~112, 169 | `LinearGradient(.blue, .purple)` → `LinearGradient(.ftBlue, .purple)`; `.blue` in stat row icon color → `.ftBlue` |

**Verification:**
```bash
cd ios/FastTrack
# Check only the files we changed — should show no ftBlue-missing accent uses
for f in DriveDetailView ProfileView AnalyticsView SocialView DriveHistoryView PublicProfileView FindPeopleView FollowersListView NotificationsView CarPickerView CarSelectorView RecentAchievementsStrip CarPhotoEditorSection PublicCarDetailView; do
  grep -n "foregroundColor(\.blue)\|Color\.blue\|\.tint(.blue)" "FastTrack/Views/$f.swift" FastTrack/Views/Components/"$f.swift" 2>/dev/null | grep -v "ftBlue" | grep -v "// " || true
done
```
Should return no matches for the target files after changes.

---

## 0.2 — Fix `StatCard` default variant to use `ftCardBg`

**Commit:** `style(ios): use ftCardBg in StatCard default variant`

**File:** `ios/FastTrack/FastTrack/Views/SharedComponents.swift`

Change the default `StatCard` variant from:
```swift
.background(
    RoundedRectangle(cornerRadius: 12)
        .fill(Color(.systemGray6))
)
```

To:
```swift
.background(
    RoundedRectangle(cornerRadius: 12)
        .fill(Color.ftCardBg)
)
```

This eliminates the "gray card inside dark card" visual clash in DriveDetailView and DrivePerformanceDetailView.

**Verification:** DriveDetailView's "Driving Stats" grid no longer shows a lighter inner card inside InstrumentCard.

---

## 0.3 — Fix `DashboardGauge` to use `ftSectionBg` and `ftCardBg`

**Commit:** `style(ios): use design system tokens in DashboardGauge backgrounds`

**File:** `ios/FastTrack/FastTrack/DesignSystem.swift`

In the `DashboardGauge` non-compact variant, change:
```swift
.background(
    RoundedRectangle(cornerRadius: 12)
        .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 1)
)
.background(
    RoundedRectangle(cornerRadius: 12)
        .fill(Color(.systemGray6))
)
```

To:
```swift
.background(
    RoundedRectangle(cornerRadius: 12)
        .stroke(Color.ftSectionBg, lineWidth: 1)
)
.background(
    RoundedRectangle(cornerRadius: 12)
        .fill(Color.ftCardBg)
)
```

In the compact variant, change:
```swift
.background(
    RoundedRectangle(cornerRadius: 8)
        .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 1)
)
.background(
    RoundedRectangle(cornerRadius: 8)
        .fill(Color(.systemGray6))
)
```

To:
```swift
.background(
    RoundedRectangle(cornerRadius: 8)
        .stroke(Color.ftSectionBg, lineWidth: 1)
)
.background(
    RoundedRectangle(cornerRadius: 8)
        .fill(Color.ftCardBg)
)
```

**Verification:** DashboardGauge cards in ContentView show the same dark-adaptive background as InstrumentCard.

---

## 0.4 — Unify `CarPhotoThumbnail` placeholder with ftBlue tint

**Commit:** `style(ios): align car photo thumbnail placeholder with ftBlue`

**File:** `ios/FastTrack/FastTrack/Views/ProfileView.swift`

The `CarPhotoThumbnail` placeholder currently uses `Color.blue.opacity(0.15)` with a blue car icon. This is a small 56pt thumbnail in list rows — a full gradient would look muddy at that size. Instead, keep the simple tinted rectangle but switch to `ftBlue`:

```swift
// Before:
RoundedRectangle(cornerRadius: 8)
    .fill(Color.blue.opacity(0.15))

Image(systemName: "car.fill")
    .foregroundColor(.blue)

// After:
RoundedRectangle(cornerRadius: 8)
    .fill(Color.ftBlue.opacity(0.15))

Image(systemName: "car.fill")
    .foregroundColor(.ftBlue)
```

This keeps the lightweight placeholder aesthetic appropriate for a small thumbnail while using the design system color.

**Verification:** `PublicGarageCard` (which uses `CarPhotoThumbnail`) shows the same light-blue tinted placeholder as `CarPhotoView` but at a scale appropriate for the thumbnail size.

---

## 0.5 — Align `AchievementCard` with `InstrumentCard` pattern

**Commit:** `style(ios): restyle AchievementCard with ftCardBg and design system tokens`

**File:** `ios/FastTrack/FastTrack/Views/AchievementsView.swift`

Replace the `AchievementCard`'s manual card styling:

```swift
// Before:
.background(
    unlocked
        ? Color(.systemBackground)
        : Color(.systemGray6)
)
.cornerRadius(12)

// After:
.background(Color.ftCardBg)
.cornerRadius(12)
```

For the **locked variant**: wrap the entire card content in an opacity layer to convey the locked state without a separate background color:
```swift
struct AchievementCard: View {
    let achievement: Achievement
    let unlocked: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // ... existing card content ...
        }
        .opacity(unlocked ? 1.0 : 0.65)  // Replace the grayscale overlay
        .background(Color.ftCardBg)
        .cornerRadius(12)
    }
}
```

The `AchievementCard` still keeps its colored icon and category tint. Only the background treatment changes.

Also add `.ftSurfaceBg` page background:
```swift
ScrollView {
    VStack(spacing: 16) { ... }
}
.background(Color.ftSurfaceBg.ignoresSafeArea())
```

Add `.accentColor(.ftBlue)` to the outer NavigationView if not already set.

**Verification:** AchievementsView shows dark-adaptive cards matching GarageView and CarDetailView in dark mode (ftCardBg), and locked cards appear at 65% opacity with the same card treatment.

---

## 0.6 — Add `ftSurfaceBg` and `ftBlue` accents to social/notification views

**Commit:** `style(ios): apply design system to social and notification views`

Apply color system changes without restructuring the List-based views. Use `.listRowBackground(Color.ftCardBg)`, `.scrollContentBackground(.hidden)`, and page backgrounds.

### `PublicProfileView.swift` — keep List, apply colors

Do NOT convert from `List` to `ScrollView` — the native iOS list aesthetic with section headers ("Stats", "Garage") and insetGrouped style is appropriate here. Apply design system via:
1. Add `.scrollContentBackground(.hidden)` and `.background(Color.ftSurfaceBg.ignoresSafeArea())` to the `List`
2. Add `.listRowBackground(Color.ftCardBg)` to all rows
3. Change `Color.blue` (follow button, avatar gradient) → `Color.ftBlue` and `LinearGradient(.blue, .purple)` → `LinearGradient(.ftBlue, .purple)` — already planned in Phase 0.1

### `FindPeopleView.swift`

1. Change `Color.blue` to `Color.ftBlue` for follow button and "You" badge (Phase 0.1).
2. Change avatar gradient from `LinearGradient(.blue, .purple)` to `LinearGradient(.ftBlue, .purple)` (Phase 0.1).
3. Add `.scrollContentBackground(.hidden)` and `.background(Color.ftSurfaceBg.ignoresSafeArea())`.

### `FollowersListView.swift`

1. Change avatar gradient from `LinearGradient(.blue, .purple)` to `LinearGradient(.ftBlue, .purple)` (Phase 0.1).
2. Add `.scrollContentBackground(.hidden)` and `.background(Color.ftSurfaceBg.ignoresSafeArea())`.

### `NotificationsView.swift`

1. Change `Color.blue` to `Color.ftBlue` for unread dot and avatar placeholder (Phase 0.1).
2. Add `.scrollContentBackground(.hidden)` and `.background(Color.ftSurfaceBg.ignoresSafeArea())`.
3. Add `.listRowBackground(Color.ftCardBg)` to all rows.

### `SocialView.swift`

Already partially aligned (uses `ftCardBg` for row backgrounds). Changes:
1. `Color.blue.opacity(0.08)` → `Color.ftBlue.opacity(0.08)` for current user highlight (Phase 0.1).
2. `Color.blue` → `Color.ftBlue` for car thumbnail placeholder and "You" badge (Phase 0.1).

### `DriveHistoryView.swift`

Already uses `ftSurfaceBg` for row backgrounds. Changes:
1. `Color.blue.opacity(0.1)` → `Color.ftBlue.opacity(0.1)` for car pill bg (Phase 0.1).
2. `Color.blue` → `Color.ftBlue` for car pill text color (Phase 0.1).

**Verification:**
- All social/notification views show dark-adaptive card backgrounds in dark mode
- All accent colors use `ftBlue` (no system `.blue`)
- `PublicProfileView` retains its native iOS list aesthetic with section headers, now using `ftCardBg` row backgrounds

---

## 0.7 — Align skeleton blocks and ensure StatCard corner radius consistency

**Commit:** `style(ios): align skeleton loading blocks with design system`

**File:** `ios/FastTrack/FastTrack/Views/SharedComponents.swift`

1. **Fix `SkeletonBlock`** (line ~340): Change the fill color from `Color(.systemGray5)` to `Color.ftSectionBg.opacity(0.5)`:
   ```swift
   // Before:
   .fill(Color(.systemGray5))

   // After:
   .fill(Color.ftSectionBg.opacity(0.5))
   ```

2. **Fix `StatCardSkeleton`** (line ~340): Change background from `Color(.secondarySystemBackground)` to `Color.ftCardBg`:
   ```swift
   // Before:
   .background(Color(.secondarySystemBackground))

   // After:
   .background(Color.ftCardBg)
   ```

3. **Verify colored `StatCard` cornerRadius** (line ~226): Ensure the colored variant uses `cornerRadius(12)` (same as default). Already correct.

**Verification:** Skeleton placeholders in DriveDetailView show the correct dark-adaptive `#1C1C1E` background instead of `systemGray5`.

---

## Scope decisions

### Views left as system-styled (intentionally)

These views use `List`/`Form` because they're standard iOS settings/editing flows. Applying garage styling here would fight UIKit conventions:

- **SettingsView** — system List is expected for settings
- **EditCarView** — system Form is expected for editing
- **ProfileSetupView** — system Form for onboarding
- **SignInView** — system styling for auth screen

These are kept as-is. The only change from 0.1 that touches them is the `.blue` → `.ftBlue` sweep, which changes button/tint colors without restructuring the view.

### CarDetailGauge / PublicCarDetailGauge

These use `color.opacity(0.08)` backgrounds which are intentionally tinted to match their gauge color. This is a deliberate design pattern (colored gauge cards) that is different from but complementary to `InstrumentCard`. No change needed.

### Spacing tokens

The audit found that only `ContentView` uses `Spacing` tokens. Every other view hardcodes numeric spacing. Converting all hardcoded spacing to `Spacing` tokens is a risk for subtle layout regressions and is **not included** in Phase 0. This can be done incrementally in future style passes.

---

## General verification for all Phase 0 changes

After completing all changes:

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

Then visually verify:
- Dark mode: all card backgrounds are consistently dark (`#121216`), no `systemGray6` showing through
- Light mode: all card backgrounds are consistently `secondarySystemGroupedBackground`
- Blue accents everywhere are now `ftBlue` (#0A84FF), not system blue (#007AFF)
- Achievements, public profile, social, notifications all show dark-adaptive backgrounds
- ContentView dashboard gauges show `ftCardBg` instead of `systemGray6`
- DriveDetailView stat cards show `ftCardBg` inside `InstrumentCard` (no double-card)

```bash
cd backend
CGO_ENABLED=1 go build ./... && CGO_ENABLED=1 go vet ./... && go test ./... -v -timeout 60s
```
(No backend changes, but verify no breakage.)