# Plan: Phase 0 — Design System Alignment

**Date:** 2026-06-08
**Status:** Ready for implementation
**Branch:** `feat/design-system-alignment`
**Worktree:** `.worktrees/design-alignment`
**Base:** Latest `main`
**Conventional commits:** Required (style, refactor)

Must land before Phase 1 and Phase 2 so we build on a consistent foundation.

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

## 0.1 — Replace `Color.blue` with `Color.ftBlue` everywhere

**Commit:** `style(ios): replace system blue with ftBlue across all views`

Global sweep. Replace every instance of `Color.blue` and `.blue` (when used as an accent/interactive color, not `.blue` in a gradient or unrelated context) with `Color.ftBlue` or `.ftBlue`.

**Files to change:**

| File | Pattern | Replacement |
|---|---|---|
| `DriveDetailView.swift` | `.blue` (pencil icon, play button, slider tint, map marker) | `.ftBlue` |
| `ProfileView.swift` | `Color.blue` (avatar placeholder bg, add-car button, toggle tint, "SELECTED" label) | `Color.ftBlue` |
| `AnalyticsView.swift` | `Color.blue` (car chips) | `Color.ftBlue` |
| `SocialView.swift` | `Color.blue.opacity(0.08)` (current user highlight), `Color.blue` (car thumbnail, "You" badge) | `Color.ftBlue` opacity variants |
| `DriveHistoryView.swift` | `Color.blue.opacity(0.1)` (car pill bg), `Color.blue` (car pill text) | `Color.ftBlue` opacity variants |
| `PublicProfileView.swift` | `Color.blue` (follow button, avatar gradient) | `Color.ftBlue` |
| `FindPeopleView.swift` | `Color.blue` (follow button, "You" badge), `LinearGradient(.blue, .purple)` | `Color.ftBlue`, `LinearGradient(.ftBlue, .purple)` |
| `FollowersListView.swift` | `LinearGradient(.blue, .purple)` (avatar) | `LinearGradient(.ftBlue, .purple)` |
| `NotificationsView.swift` | `Color.blue` (unread dot, avatar placeholder) | `Color.ftBlue` |
| `AchievementsView.swift` | `Color.blue` (nav tint) — check if system default | `.ftBlue` for custom tint |
| `CarPickerView.swift` | `Color.blue` (checkmark, car icon, confirm button) | `Color.ftBlue` |
| `CarSelectorView.swift` | `Color.blue` (checkmark, select car button, "Change Car" link) | `Color.ftBlue` |
| `RecentAchievementsStrip.swift` | `.blue` ("View All" nav link) | `.ftBlue` |
| `CarPhotoEditorSection.swift` | `Color.blue.opacity(0.15)`, `.blue` icon | `Color.ftBlue.opacity(0.15)`, `.ftBlue` |

**Verification:**
```bash
cd ios/FastTrack
grep -rn "\.blue" FastTrack/Views/ FastTrack/Views/Components/ FastTrack/DesignSystem.swift | grep -v "ftBlue" | grep -v "// " | grep -v "lightBlue"
```
Should return no accent color uses (only `.blue` in unrelated contexts like sky colors, if any).

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

## 0.4 — Unify `CarPhotoThumbnail` placeholder with `CarPhotoView`

**Commit:** `style(ios): unify car photo placeholder with ftBlue gradient`

**File:** `ios/FastTrack/FastTrack/Views/ProfileView.swift`

The `CarPhotoThumbnail` placeholder currently uses `Color.blue.opacity(0.15)` with a blue car icon. Change to match `CarPhotoView`'s gradient style:

```swift
// Before:
RoundedRectangle(cornerRadius: 8)
    .fill(Color.blue.opacity(0.15))

Image(systemName: "car.fill")
    .foregroundColor(.blue)

// After:
RoundedRectangle(cornerRadius: 8)
    .fill(
        LinearGradient(
            colors: [Color.ftBlue.opacity(0.6), Color.purple.opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    )

Image(systemName: "car.fill")
    .foregroundColor(.white)
```

This makes both car photo placeholders consistent.

**Verification:** `PublicGarageCard` (which uses `CarPhotoThumbnail`) shows the same ftBlue/purple gradient placeholder as `CarPhotoView` in `GarageCarCard`.

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
```

With:
```swift
// After:
.background(Color.ftCardBg)
.cornerRadius(12)
```

And for the locked variant, replace the grayscale overlay. The `AchievementCard` still keeps its colored icon and category tint, but the card background is now consistently `ftCardBg`.

Also add `.ftSurfaceBg` page background:
```swift
ScrollView {
    VStack(spacing: 16) { ... }
}
.background(Color.ftSurfaceBg.ignoresSafeArea())
```

Add `.accentColor(.ftBlue)` to the outer NavigationView if not already set.

**Verification:** AchievementsView shows dark-adaptive cards matching GarageView and CarDetailView in dark mode, and correct system background in light mode.

---

## 0.6 — Add `ftSurfaceBg` and `ftBlue` accents to social/notification views

**Commit:** `style(ios): apply design system to social and notification views`

These are List-based views. The changes are additive — we add `.listRowBackground(Color.ftCardBg)`, `.scrollContentBackground(.hidden)`, and change the page background, without restructuring the view.

### `PublicProfileView.swift`

1. Replace `List` outer container with `ScrollView + VStack`.
2. Set background `Color.ftSurfaceBg.ignoresSafeArea()`.
3. Wrap sections in `InstrumentCard` where appropriate (profile header, stats, garage).
4. Change `Color.blue` and `LinearGradient(.blue, .purple)` to `Color.ftBlue` and `LinearGradient(.ftBlue, .purple)`.

The structural change from `List` to `ScrollView` is needed because List's insetGrouped style doesn't support custom backgrounds well. The content sections should each become `InstrumentCard` blocks.

### `FindPeopleView.swift`

1. Change `Color.blue` to `Color.ftBlue` for follow button and "You" badge.
2. Change avatar gradient from `LinearGradient(.blue, .purple)` to `LinearGradient(.ftBlue, .purple)`.
3. Add `.scrollContentBackground(.hidden)` and `.background(Color.ftSurfaceBg.ignoresSafeArea())`.

### `FollowersListView.swift`

1. Change avatar gradient from `LinearGradient(.blue, .purple)` to `LinearGradient(.ftBlue, .purple)`.
2. Add `.scrollContentBackground(.hidden)` and `.background(Color.ftSurfaceBg.ignoresSafeArea())`.

### `NotificationsView.swift`

1. Change `Color.blue` to `Color.ftBlue` for unread dot and avatar placeholder.
2. Add `.scrollContentBackground(.hidden)` and `.background(Color.ftSurfaceBg.ignoresSafeArea())`.
3. Add `.listRowBackground(Color.ftCardBg)` to each row.

### `SocialView.swift`

Already partially aligned (uses `ftCardBg` for row backgrounds). Changes:
1. `Color.blue.opacity(0.08)` → `Color.ftBlue.opacity(0.08)` for current user highlight.
2. `Color.blue` → `Color.ftBlue` for car thumbnail placeholder and "You" badge.

### `DriveHistoryView.swift`

Already uses `ftSurfaceBg` for row backgrounds. Changes:
1. `Color.blue.opacity(0.1)` → `Color.ftBlue.opacity(0.1)` for car pill bg.
2. `Color.blue` → `Color.ftBlue` for car pill text color.

**Verification:**
- All social/notification views show dark-adaptive card backgrounds in dark mode
- All accent colors use `ftBlue` (no system `.blue`)
- `PublicProfileView` renders correctly with `InstrumentCard` sections and `ftSurfaceBg` background

---

## 0.7 — Fix `StatValue` and `StatCard` colored variant backgrounds

**Commit:** `style(ios): align StatCard colored variant with design system`

**File:** `ios/FastTrack/FastTrack/Views/SharedComponents.swift`

The colored `StatCard` variant uses `color.opacity(0.1)` background, which is fine visually. Audit to ensure the non-colored variant (already fixed in 0.2) and the colored variant both use consistent cornerRadius 12.

Also fix `SkeletonBlock`: change `Color(.systemGray5)` → `Color.ftSectionBg.opacity(0.5)` and `StatCardSkeleton`: change `Color(.secondarySystemBackground)` → `Color.ftCardBg`.

This makes skeleton states consistent with the dark-adaptive cards.

**Verification:** Skeleton placeholders in DriveDetailView show correct dark-mode backgrounds.

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