# Color Contrast Audit & Fix — Light Mode

## Background

The iOS design language rework introduced a new "Dark Asphalt" palette
(`ftGold`, `ftAmber`, `ftBlue`, `ftGreen`, `ftRed`) but the brand colors are
hard-coded RGB literals that do not adapt to light mode. The card surface
(`ftGlassCardFill`) does adapt, becoming near-white at 55% alpha in light
mode — so any text or transparent element in the brand palette is
unreadable against the light card.

The user first reported the **Top Speed** value in `GarageCarCard` (yellow
text on near-white) and the **achievements chips** in the Profile hero
(yellow `.special` category) — and asked for a comprehensive audit.

## Audit summary

Read in full: all 19 view files, 10 component files, and `DesignSystem.swift`,
`AchievementModel.swift`, `CarDetailData.swift`, `PublicCarDetailData.swift`.

**~50 non-adaptive color callsites.** Severity distribution:

| Severity | Count | Examples |
|---|---|---|
| **HIGH** | ~12 | Small text in `ftGold`/`ftAmber`, raw `Color.yellow` on text, `Color.green` text, white-on-orange bubbles |
| **MEDIUM** | ~20 | `StatusLevel` chip backgrounds, sparkline accents, gauge border fills, raw `.red` PB marker |
| **LOW** | ~20 | Map polylines, gradient stops, decorative badges |

**Chokepoints identified (the leverage points):**

1. `StatusLevel.color` in `DesignSystem.swift:121-129` — drives Top Speed,
   0-60, and the PB chips across `GarageView`, `PublicProfileView`,
   `DriveHistoryView`, `DriveDetailView`. One file change.
2. `AchievementCategory.color` in `Models/AchievementModel.swift:55-64` —
   drives `AchievementChip` and `AchievementBadgeCard` across Profile
   hero, CarDetail per-car strip, AchievementsView grid, AchievementDetail
   sheet. One file change.
3. The five `Color.ft*` brand tokens at `DesignSystem.swift:25-30` — fix
   the `FTGauge` value text, gradient stops on `FTGauge`/`SpeedHeroRing`/
   `GradientProgressBar`, and the `recordingAccent`/`idleAccent` on
   `ContentView` gauge strip. One file change.
4. Raw `Color.yellow/.red/.green/.orange` calls in:
   `AchievementsView.swift`, `SocialView.swift`, `DriveHistoryView.swift`
   (the 0-06% row tint), `CarDetailSparkline.swift` (PB marker). These
   require per-call-site changes.

## Strategy

**Token swap + StatusLevel/category adaptations + raw-call fixes.** Three
files for the chokepoints, ~25 callsites total.

The fix philosophy: light mode should darken the brand colors enough to
maintain WCAG AA contrast against the near-white card surface. Specifically:

- `ftGold` #FFD60A → light mode `#B88500` (deeper amber-gold)
- `ftAmber` #FF6B35 → light mode `#C2410C` (burnt orange)
- `ftBlue` #0A84FF → keep (passes AA against white)
- `ftGreen` #30D158 → light mode `#15803D` (forest green)
- `ftRed` #FF453A → keep (passes AA for non-text)

The `StatusLevel` enum and `AchievementCategory` enum already return `Color`,
so adding a `Color(UIColor { trait in ... })` resolver at the chokepoint
covers every consumer automatically.

## Tasks

### Task 1: Add adaptive brand tokens in `DesignSystem.swift`

Replace the 5 hard-coded `Color.ft*` definitions with adaptive versions:

```swift
static var ftGold: Color {
    Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.84, blue: 0.04, alpha: 1.0)   // #FFD60A
            : UIColor(red: 0.72, green: 0.52, blue: 0.0, alpha: 1.0)   // #B88500
    })
}
```

Same pattern for `ftAmber`, `ftGreen`. `ftBlue` and `ftRed` stay as
fixed colors (pass AA against white).

Also update the 2 PB tints (`ftPB060Tint`, `ftPBTopSpeedTint`) at lines
68-69 if they need light-mode variants. `ftPBTopSpeedTint` is `Color.red`
which is fine; `ftPB060Tint` is `Color.yellow` which is used as a SOLID
background with black text (the PB 0-60 pill in DriveHistoryView) — that
combination is high contrast, but row tints at 0.06 opacity are not. Swap
to a darker yellow tint in light mode:

```swift
static var ftPB060Tint: Color {
    Color(uiColor: UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 1.0, green: 0.84, blue: 0.04, alpha: 1.0)   // #FFD60A
            : UIColor(red: 0.72, green: 0.52, blue: 0.0, alpha: 1.0)   // #B88500
    })
}
```

### Task 2: Update `StatusLevel.color` in `DesignSystem.swift:121-129`

Wrap the `switch self` in a `Color(uiColor: UIColor { trait in ... })` so
the dot color adapts. The `best` case currently returns `Color.ftGold`;
change to a darker value in light mode. Same for `nearBest` (ftAmber) and
`improving` (ftGreen).

### Task 3: Update `AchievementCategory.color` in `Models/AchievementModel.swift:55-64`

Same pattern: wrap each category's color in a `Color(UIColor) { trait in
... }` resolver so the `.special` (yellow), `.consistency` (green), and
`.performance` (orange) cases darken in light mode. The `.milestone` (purple)
and `.speed` (red) cases don't need changes.

### Task 4: Fix raw `Color.yellow/.green/.red` calls in
`AchievementsView.swift`

- Line 83: `Label("N unlocked", systemImage: "trophy.fill").foregroundStyle(.yellow)`
  → `.foregroundStyle(Color.ftGold)` (which is now adaptive via Task 1).
- Line 86: `.foregroundStyle(.green)` → `.foregroundStyle(Color.ftGreen)`.
- Line 189-190: `Image(systemName: "checkmark.seal.fill").foregroundStyle(.green)`
  → `.foregroundStyle(Color.ftGreen)`.
- Line 205, 210, 213: any other `.green` foregroundStyle → `.foregroundStyle(Color.ftGreen)`.

### Task 5: Fix raw `Color.yellow` in `SocialView.swift:381`

```swift
LeaderboardRow(...).rankColor  // returns Color.yellow
```

Change to `Color.ftGold` (now adaptive). Same for the silver (`#2`) and
bronze (`#3`) rank colors — these are also near-white-on-white. Update the
colors to dark enough values in both modes:
- Silver: keep `Color(white: 0.5)` instead of `0.7`.
- Bronze: keep `Color(red: 0.8, green: 0.5, blue: 0.2)`.

### Task 6: Fix white-on-orange in `DriveDetailView/DriveDetailMap.swift:333`

The non-PB 0-60 attempt speech bubble uses `ftAmber` fill with WHITE text,
which is ~2.4:1 (fails AA). The PB case uses `Color.yellow` (now ftPB060Tint
after Task 1) with BLACK text, which is fine. Change the non-PB case to
use BLACK text:

```swift
Text(time).foregroundStyle(.black)
```

Or switch the fill to a lighter color so white text passes. Black is the
right answer for legibility.

### Task 7: Update `Color.red` PB marker in `CarDetailSparkline.swift:126, 132`

The "PB" annotation text is `Color.red` raw on a light card. Passes at
3.8:1 but is non-adaptive. Change to `Color.ftRed` (already 3.8:1 in
both modes since the token is unchanged for red).

### Task 8: Update `Color.red` "Top Speed" gauge in `PublicCarDetailView.swift:126`

`FTGauge(color: .ftRed, ...)` — the token is already passing 3.8:1 against
white in both modes. No change needed beyond Task 1's token update.

### Task 9: Update `Color.green` system green in `PublicCarDetailView.swift:154`

`flag.fill`.foregroundStyle(.green) — 2.0:1 against white. Change to
`Color.ftGreen` (now adaptive in light mode via Task 1).

### Task 10: Add test coverage

Add `ColorContrastTests.swift` in `FastTrackTests/` that:
- Verifies `ftGold`, `ftAmber`, `ftGreen` adapt between trait collections
- Verifies `StatusLevel.best.color` in a light trait returns a darker value
  than the dark-trait value
- Verifies `AchievementCategory.special.color` adapts the same way

### Task 11: Build & test

```bash
cd .worktrees/polish-batch-5/ios/FastTrack
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Run the new tests:
```bash
xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/ColorContrastTests \
  CODE_SIGNING_ALLOWED=NO
```

## Verification criteria

- All 19 view files render the same in dark mode (no visual regression).
- All 19 view files render with WCAG AA contrast for text/icon in light
  mode against `ftGlassCardFill` near-white background.
- New `ColorContrastTests` pass.
- No call to `Color.yellow` / `Color.green` / `Color.red` (raw system
  colors) remains in the views that render against `ftGlassCardFill`.

## Files touched (estimate)

- `DesignSystem.swift` — Task 1, 2 (token updates)
- `Models/AchievementModel.swift` — Task 3
- `Views/AchievementsView.swift` — Task 4
- `Views/SocialView.swift` — Task 5
- `Views/DriveDetailView/DriveDetailMap.swift` — Task 6
- `Views/CarDetailView/CarDetailSparkline.swift` — Task 7
- `Views/PublicCarDetailView.swift` — Task 9
- `FastTrackTests/ColorContrastTests.swift` — Task 10 (new)
