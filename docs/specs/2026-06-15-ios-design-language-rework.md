# FastTrack iOS Design Language Rework

**Date:** 2026-06-15
**Status:** Approved for implementation planning
**Scope:** Full app — every screen, every shared component

---

## Summary

Rework FastTrack's iOS design language to match the visual quality and expressiveness of premium fitness/lifestyle apps (reference: Whoop). The direction is evolutionary, not a rebrand — the existing accent palette (blue/amber/green/gold/red) is preserved. What changes is the surface layer: backgrounds become rich radial gradients, cards gain a unified glass treatment, metrics gain qualitative context via status dots, sparklines add trend context inside stat cards, the speedometer becomes an open arc, and the tab bar adopts a floating pill. Achievements are redesigned and surfaced more prominently. Every screen and every shared component is covered.

No emojis anywhere in the UI. All icons use SF Symbols.

---

## 1. Design Tokens

### 1.1 New Background Tokens (DesignSystem.swift)

Two new `ShapeStyle` properties on `Color`/`LinearGradient`:

| Token | Description | Usage |
|---|---|---|
| `ftBgGradient` | `RadialGradient`: `#1a1a3a` at top-left (0%) → `#07070B` (60%) | Default screen background — every screen except active recording |
| `ftBgGradientWarm` | `RadialGradient`: `#1f0a00` at top-center (0%) → `#07070B` (55%) | Track screen during active recording only |

Applied via a `.background` modifier on each screen's outermost container. `ftBg` (`#07070B`) remains for system sheet interiors and `Color.clear` fallback contexts.

### 1.2 Card Token Migration

| Token | Old definition | New definition |
|---|---|---|
| `ftGlassCard` | White 6% fill (dark) / 72% (light) — modal overlays only | `Color.white.opacity(0.07)` fill + 1pt `Color.white.opacity(0.12)` stroke — universal card surface |
| `ftCardBg` | `#121216` solid | **Retired.** All callsites migrated to `ftGlassCard`. Token removed from `DesignSystem.swift`. |
| `ftSectionBg` | Adaptive dark `#1C1C1E` / light `systemBackground` | **Retired for screens.** Used only in Splash/SignIn sheet interiors where `ftBgGradient` is inappropriate. |

`InstrumentCard`'s `glass:` parameter defaults changed from `false` to `true`. The `false` path (solid `ftCardBg`) is removed entirely — `InstrumentCard` always renders as glass.

### 1.3 Accent Palette (Unchanged)

`ftBlue` (#0A84FF), `ftAmber` (#FF6B35), `ftGreen` (#30D158), `ftRed` (#FF453A), `ftGold` (#FFD60A). No changes.

`ftRankGold`, `ftRankSilver`, `ftRankBronze`, `ftPB060Tint`, `ftPBTopSpeedTint` — no changes.

### 1.4 Status Dot Semantic Enum

New `StatusLevel` enum in `DesignSystem.swift`:

```swift
enum StatusLevel {
    case best       // ftGold  — PB, #1 rank
    case improving  // ftGreen — improving, above average, GPS excellent
    case nearBest   // ftAmber — near best, active/recording, GPS good
    case typical    // ftBlue  — normal, info, GPS fair
    case inactive   // #555555 — idle, locked, GPS poor
}
```

Used by the new `StatusDot` component (section 2.1).

### 1.5 Updated Skeleton Token

`SkeletonBlock` and `LeaderboardSkeletonRow` currently use `Color.ftCardBg` / `Color.ftSectionBg`. Update to `Color.white.opacity(0.06)` fill with shimmer color `Color.white.opacity(0.12)` — both visible against the new gradient backgrounds.

---

## 2. New UI Patterns

### 2.1 StatusDot Component

New `StatusDot` SwiftUI view in `SharedComponents.swift`:

```
StatusDot(level: StatusLevel, label: String)
```

Renders a 6pt filled `Circle` (color from `StatusLevel`) + `Text(label)` in a horizontal stack. Used everywhere qualitative context is needed alongside a metric. Replaces bare `Text` status labels in all the callsites listed in section 3.

### 2.2 Mini Sparklines in Stat Cards

Each `FTGauge .compact` and `TrackMetricCard` gains a 14pt inline `Chart` (Swift Charts line mark) at the bottom, showing the last 10 drives' value for that metric.

- No axes, no labels — shape only
- Stroke color: card's accent color at 70% opacity
- Hidden when fewer than 3 data points exist
- Data comes from drives already fetched on the parent screen — no new API calls
- `CarDetailSparkline` (the existing full-size interactive chart) is **retained** alongside micro-sparklines; they serve different purposes (detail vs. glance)

### 2.3 GradientProgressBar Component

`GaugeProgressBar` in `SharedComponents.swift` is replaced by a new `GradientProgressBar` component:

```
GradientProgressBar(value: Double, range: ClosedRange<Double>, size: GradientProgressBarSize)
// size: .compact (5pt height) or .hero (8pt height)
```

- Fill: `LinearGradient` green → gold → amber → red mapped to `range`
- White dot marker at `value` position: 9pt diameter (compact) / 14pt (hero), 1.5pt dark border matching the nearest background color
- `GaugeProgressBar` struct is **deleted**; all callsites replaced with `GradientProgressBar`
- Used in: `FTGauge .compact` (replaces gradient underline), `TrackMetricCard`, `DriveDetailGauges`, `FTGauge .hero` bottom bar (new addition)

### 2.4 Open Arc Speedometer (SpeedHeroRing)

`SpeedHeroRing` (private struct in `ContentView.swift`) is redesigned in-place:

- 240° open arc (gap at the bottom — 60° opening centered on 6 o'clock)
- Track arc: `Color.white.opacity(0.06)`, 10pt stroke width, rounded linecaps
- Value arc: `LinearGradient` green → gold → red, same weight, animated with `.animation(.linear(duration: 0.1))`
- 5 tick marks evenly distributed along the arc track, `Color.white.opacity(0.15)`, 4pt length
- Center number stays white regardless of speed — speed color is expressed only through the arc
- `ActiveGlowModifier` (`.activeGlow()`) is **removed** from the ring — the gradient arc is the visual indicator; the glow conflicts with it
- Outer diameter unchanged (256pt) to preserve layout

### 2.5 Floating Pill Tab Bar

The system `TabView` tab bar is hidden via `.toolbar(.hidden, for: .tabBar)`. A custom `FloatingTabBar` view is overlaid at the bottom of the root `ZStack` in `RootView`/`FastTrackApp.swift`.

- Container: `Capsule()`, `ultraThinMaterial` fill, 1pt `Color.white.opacity(0.12)` stroke
- Positioned 16pt above safe area bottom, horizontally centered with 32pt side padding
- Active tab: icon + label inside a `Capsule` with accent color at 20% opacity fill
- Inactive tabs: SF Symbol icon only, `Color.white.opacity(0.5)`
- Active accent color per tab: `ftBlue` (Track), `ftAmber` (Garage), `ftGold` (Social), `ftGreen` (Profile)
- SF Symbol names: `speedometer` (Track), `car.2.fill` (Garage), `trophy.fill` (Social), `person.fill` (Profile)
- Hides (`.offset(y: 80).opacity(0)`, `.animation(.easeInOut(duration: 0.2))`) while `DriveManager.isRecording == true`

---

## 3. Shared Component Updates

### 3.1 InstrumentCard

- Remove `glass: Bool` parameter — always glass
- Background: `ftGlassCard` fill + 1pt `ftGlassCard` stroke (using the updated token values)
- Remove all `if glass { ... } else { Color.ftCardBg }` branching

### 3.2 FTGauge

**`.compact` variant:**
- Background: `ftGlassCard` (was `Color.ftCardBg`)
- Gradient underline (3pt blue→amber `LinearGradient`): replaced with `GradientProgressBar(.compact)` positioned at the bottom of the card
- Micro-sparkline added above the progress bar

**`.hero` variant (CarDetailHero):**
- Ring redesigned to 240° open arc (same spec as `SpeedHeroRing` in 2.4, scaled to the 96pt diameter)
- `GradientProgressBar(.hero)` added as a horizontal bar below the ring number

**`.statCell` variant:**
- Current `color.opacity(0.08)` tint background is **retained** — it gives each cell its per-metric identity and reads well against the new gradient backgrounds. No change needed.

### 3.3 GaugeProgressBar → GradientProgressBar

Struct deleted. All callsites (in `FTGauge .compact`, `StatCard`, `GarageCarCard`) replaced with `GradientProgressBar`.

### 3.4 StatCard

- Background: `ftGlassCard` (was `Color.ftCardBg`)
- Both the default and "colored" variants updated — the `colored` variant retains its accent tint overlay on top of the glass fill

### 3.5 TrackMetricCard (ContentView.swift — private)

- Currently uses `.ultraThinMaterial`. Replace with explicit `ftGlassCard` fill + 1pt stroke to match all other cards. (`.ultraThinMaterial` adapts to light mode differently than needed.)
- Add micro-sparkline (section 2.2)
- Add `GradientProgressBar(.compact)` below the value

### 3.6 ToastView

- Background: `ftGlassCard` fill + 1pt stroke (was `Color.ftCardBg` fill + `Color.ftSectionBg` border)
- No structural changes

### 3.7 SkeletonBlock / LeaderboardSkeletonRow / StatCardSkeleton

- All skeleton fills: `Color.white.opacity(0.06)` (was `Color.ftCardBg` or `Color.ftSectionBg.opacity(0.5)`)
- Shimmer highlight: `Color.white.opacity(0.12)` (no change to the shimmer animation itself)

### 3.8 BadgePill

- `.selected`, `.carChip`, `.you` styles: update background fill from `Color.ftCardBg`-adjacent solids to `accent.opacity(0.15)` fill + `accent.opacity(0.3)` border — consistent with glass language
- `.pb060` and `.pbTopSpeed` styles: **unchanged** per spec decision in 3.7

### 3.9 DrivingStyleBadge

- No changes required — existing `color.opacity(0.12)` fill reads correctly against the new gradient backgrounds

### 3.10 CarPhotoView

- No changes to the component itself
- The gradient placeholder (`ftBlue→purple`) remains — it contrasts adequately against dark gradient backgrounds

### 3.11 RecentAchievementsStrip + RecentAchievementCard

- Both **deleted** — replaced by the new Achievements section described in section 5

### 3.12 CarDetailSparkline

- Wrap in `InstrumentCard` (glass) if not already — the existing `InstrumentCard` wrapper stays, picks up glass treatment automatically through the `InstrumentCard` update in 3.1
- No changes to the chart content or interaction

---

## 4. Screen-by-Screen Changes

### 4.1 Track (ContentView)

- Background: `ftBgGradientWarm` (recording) / `ftBgGradient` (idle)
- `SpeedHeroRing`: redesigned open arc (section 2.4)
- GPS status capsule: `StatusDot(level:, label:)` replacing bare text
- Recording/Idle indicator: `StatusDot` replacing bare text
- `TrackMetricCard` (private): glass + sparkline + `GradientProgressBar` (section 3.5)
- `.activeGlow()` removed from the ring
- Tab bar hidden while recording

### 4.2 Drive Detail (DriveDetailView + sub-views)

- Background: `ftBgGradient`
- Header: adds `StatusDot` pill (gold = Top Speed PB, amber = 0-60 PB, blue = no PB)
- `DriveDetailGauges`: `ftGlassCard` cells + `GradientProgressBar` + micro-sparkline
- `DriveDetailAttemptsList` rows: `ftGlassCard`
- `DriveDetailTripCard`: inherits glass via `InstrumentCard` update (3.1) — no direct change needed
- `DriveDetailMap` — MapKit layer unchanged. Non-map overlays (scrubber panel, attempt-bubble panel, `SpeechBubble` fills): replace `Color.ftCardBg` fills with `ftGlassCard` — these are the HUD elements on top of the map, not the map itself
- "Earned This Drive" achievements section: new (see section 5.2)

### 4.3 Drive History (DriveHistoryView)

- Background: `ftBgGradient`
- PB rows: replace `rowTint()` function's solid `Color.ftPB060Tint.opacity(0.15)` / `Color.ftPBTopSpeedTint.opacity(0.10)` fills with `ftGlassCard` + a color-tint overlay (`Color.ftGold.opacity(0.06)` for top speed PB, `Color.ftAmber.opacity(0.06)` for 0-60 PB) + matching 1pt tinted border
- Normal rows: `ftGlassCard`
- Top speed value prefixed with `StatusDot`

### 4.4 Garage (GarageView)

- Background: `ftBgGradient`
- Cross-car summary `InstrumentStatCell` cells: inherit glass via 3.1
- `GarageCarCard`: `ftGlassCard` outer container; stat values use `StatusDot`
- Recent drives rows: `ftGlassCard` + `StatusDot` for top speed

### 4.5 Car Detail (CarDetailView + sub-views)

- Background: `ftBgGradient`
- `CarDetailHero`: hero photo area unchanged; `FTGauge .hero` rings redesigned to open arc + `GradientProgressBar(.hero)` (section 3.2)
- `CarDetailSparkline`: `InstrumentCard` wrapper picks up glass (section 3.12)
- `CarDetailStatsGrid` (`PerformanceBreakdownCard`, `AnalyticsCard`): inherit glass via `InstrumentCard` (3.1)
- `CarDetailDrivesList` rows: `ftGlassCard` + `StatusDot`
- Existing `perCarAchievementsSection` replaced by "With This Car" achievements strip (section 5.3)

### 4.6 Social / Leaderboard (SocialView)

- Background: `ftBgGradient`
- Filter chips: replace `Capsule().fill(Color.ftCardBg)` with `ftGlassCard` fill + 1pt stroke; active chip adds `accent.opacity(0.15)` overlay
- "Your position" card: replace `Color.ftBlue.opacity(0.12)` + `ftCardBg` fallback with `ftGlassCard` fill + `Color.ftBlue.opacity(0.08)` tint overlay + `Color.ftBlue.opacity(0.2)` border
- Leaderboard rows: `ftGlassCard`; metric value prefixed with `StatusDot`

### 4.7 Profile (ProfileView)

- Background: `ftBgGradient`
- Header card: `ftGlassCard`; active car line uses `StatusDot`
- `RecentAchievementsStrip` replaced by dedicated Achievements section (section 5.4)
- Main stats grid, privacy toggle row, garage link row, sign out / delete rows: all `ftGlassCard`

### 4.8 Public Profile (PublicProfileView)

**Goal:** Align the public garage layout with `GarageView` and strip all personal/location data. The public profile should feel like a performance card for the driver, not a social profile.

**Layout change:** Replace `List` / `.insetGrouped` structure with `ScrollView` + `VStack` — matching `GarageView`'s outer pattern.

**Header — strip personal/location data:**
- **Remove:** avatar image, full name, country, follower count, following count, Follow/Unfollow button
- **Keep:** `@username` as the screen title (navigation bar title)
- The header section is removed entirely; the screen opens directly into the stats + garage content

**Aggregate stats — align with GarageView:**
- Replace the 3-row `List` stats section (Top Speed, Best 0-60, Total Distance) with the same `InstrumentStatCell` grid used in `GarageView.allCarsSummary`
- Show 4 cells (performance stats only, no trip/time metadata):
  - Total Drives (`flag.fill`, green)
  - Total Distance (`map.fill`, blue)
  - Top Speed (`bolt.fill`, gold)
  - Best 0-60 (`timer`, amber)
- All cells: `ftGlassCard`

**Garage section — align with GarageView:**
- Replace `Section("Garage")` inside `List` with a `LazyVGrid(.adaptive(minimum: 160))` matching `GarageView`'s car grid
- Replace `PublicGarageCard` (thumbnail-left row) with a layout identical to `GarageCarCard`:
  - 160pt full-bleed hero photo (`CarPhotoView`), full-width, rounded top corners
  - `car.nickname` / `car.displayString` below the photo
  - 2×2 `StatsGrid` of `StatMini` cells: Drives, Distance, Top Speed, 0-60
  - `ftGlassCard` container
  - No context menu (read-only)
  - Tap → `PublicCarDetailView` (unchanged)
- `PublicGarageCard` component is **deleted**; callers use the new shared `PublicCarCard` (or reuse `GarageCarCard` with a `readOnly: Bool` parameter — implementation choice)

**Empty state:** If garage is empty, show `ContentUnavailableView` with "No cars added yet" — no empty state for the stats grid (hide it if all values are zero)

### 4.9 Public Car Detail (PublicCarDetailView)

- Background: `ftBgGradient`
- Hero section: unchanged (260pt full-bleed photo + gradient overlay + car identity)
- Navigation title: `@username` only — remove `"@{username}'s {car.make}"` format; just `@username` to avoid showing car make as part of identity
- `FTGauge .statCell` cells: **unchanged** (per section 3.2 — `.statCell` retains tint)
- Stats list rows: `ftGlassCard`

### 4.10 Drive Performance Detail (DrivePerformanceDetailView)

- Background: `ftBgGradient`
- `PerformanceStatCard` (local to this file): inherits glass via `InstrumentCard` (3.1)
- `StatsGrid` cells: inherit via `InstrumentCard`

### 4.11 Achievements (AchievementsView + AchievementDetailView)

Fully redesigned — see section 5.

### 4.12 Notifications (NotificationsView)

- Background: `ftBgGradient`
- `listRowBackground(Color.ftCardBg)` calls replaced with `ftGlassCard` row backgrounds
- Notification rows: unread dot styling unchanged

### 4.13 Find People (FindPeopleView)

- Background: `ftBgGradient`
- Search result `UserSearchRow` cells: `ftGlassCard` row backgrounds
- Search bar: standard `.searchable` — no changes

### 4.14 Followers / Following (FollowersListView)

- Background: `ftBgGradient`
- `FollowUserRow` cells: `ftGlassCard` row backgrounds

### 4.15 Settings (SettingsView)

- Background: `ftBgGradient`
- All `Form`/`List` section row backgrounds: `ftGlassCard`
- Picker and toggle rows: `ftGlassCard`; no structural changes

### 4.16 Profile Setup / Edit (ProfileSetupView)

- Background: `ftBgGradient`
- Input fields and save button container: `ftGlassCard`; no structural changes

### 4.17 Sign In (SignInView)

- Background: `ftBgGradient` (the dark gradient matches the moody launch feel)
- Wordmark and icon styling unchanged
- Sign in button containers: `ftGlassCard` overlay — the existing white pill button for Google sign-in is unchanged (it's a branded button)

### 4.18 Splash (SplashView in FastTrackApp.swift)

- Background: `ftBgGradient` (replaces flat `ftSectionBg`)
- Animated icon, tagline, loading dots: unchanged

### 4.19 Modal Sheets (CarPickerView, CarSelectorView, EditCarView, CarDetailStyleGuide, CarHeroPhotoEditorSheet, PhotoCropView, AvatarZoomView)

- Sheet presentation background: system `.presentationBackground(.ultraThinMaterial)` — retains iOS native sheet chrome
- All content card surfaces within sheets: `ftGlassCard`
- `CarDetailStyleGuide` list rows: `ftGlassCard`; `DrivingStyleBadge` unchanged
- `AvatarZoomView`: full-screen photo viewer — `.background(Color.black)` retained; no changes
- `PhotoCropView`: system-provided crop UI — not modified
- `CarHeroPhotoEditorSheet` content area: `ftGlassCard` for any card containers; photo picker interface system-provided

---

## 5. Achievements Redesign

### 5.1 Badge Card Style: Compact 3-Column Grid

Used in `AchievementsView` and all contextual surfaces:

**Unlocked badge:**
- Card: `accent.opacity(0.08)` fill + 1pt `accent.opacity(0.25)` border + `Radius.xl` corner
- 32pt icon container: `accent.opacity(0.20)` fill, `Radius.md` corner
- Badge name: accent color, 9pt semibold, centered below icon
- No description text in the grid (tap → detail sheet)

**Locked with known progress:**
- Card: `ftGlassCard`
- 32pt icon container: `Color.white.opacity(0.06)` fill with a mini circular progress ring (Swift Charts / CAShapeLayer arc at accent color, 70% opacity)
- Badge name: `Color(white: 0.27)` (muted)
- Progress percentage: 8pt, `Color(white: 0.2)`, below name

**Locked — not yet revealed:**
- Card: `ftGlassCard` at 60% opacity (visually dimmer than known-locked)
- No icon
- "???" label in `Color(white: 0.2)`
- Becomes a known-locked card (name visible) when user is within 20% of the unlock threshold

### 5.2 Drive Detail — "Earned This Drive" Section

- Inserted after the stats grid, visible only when `drive.unlockedAchievements.isEmpty == false`
- Full-width `ftGlassCard` row per achievement: 32pt icon + badge name + "Unlocked on this drive" subtitle
- Card tint: `achievement.accentColor.opacity(0.08)` fill overlay on `ftGlassCard`

### 5.3 Car Detail — "With This Car" Section

Replaces the existing `perCarAchievementsSection` (`CarDetailDrivesList`):

- Section header: "Achievements" with "See all" → `AchievementsView` filtered to this car
- Horizontally scrolling strip of `AchievementChip` views (new component): accent-tinted `Capsule` pill, badge name, 10pt semibold
- If 0 achievements: hidden entirely (no empty state)

### 5.4 Profile — Achievements Section

Replaces `RecentAchievementsStrip`:

- Progress header row: "X / Y unlocked" left, "See all" right (→ `AchievementsView`)
- Full-width `GradientProgressBar(.compact)` showing overall unlock percentage
- Horizontal scroll strip of `AchievementChip` views for 5 most recently unlocked badges
- If 0 unlocked: shows "Start driving to earn achievements" empty state in muted text; no strip

### 5.5 AchievementsView

- Background: `ftBgGradient`
- 3-column `LazyVGrid` of badge cards (section 5.1)
- Category filter chips: `ftGlassCard` style (consistent with `SocialView` filter chips)
- "Show unlocked only" toggle row: `ftGlassCard`
- `AchievementDetailView` sheet: `ftGlassCard` background, 64pt icon, full description, unlock date or `GradientProgressBar(.hero)` for locked progress

---

## 6. Explicit Exclusions

| Item | Reason |
|---|---|
| `DriveDetailMap` MapKit layer, route polylines, playback scrubber position | Map rendering is exempt; only non-map HUD overlays on top of it are updated |
| `FTGauge .statCell` per-metric tint | Intentionally retained — per-color backgrounds give each metric visual identity |
| `DrivingStyleBadge` | Already uses opacity-based fill; reads correctly on new backgrounds; no change |
| `ConfettiView` / `ConfettiOverlay` | Particle colors are hardcoded and context-independent; no design token dependency |
| `CarPhotoView` gradient placeholder | Contrasts adequately; no change |
| `FTFont` typography scale | No changes |
| `Spacing`, `Radius`, `Motion` enums | No changes |
| `SpeedColor` utility | Used for route polyline coloring only; no changes |
| Drive recording logic, GPS/IMU pipeline | Backend / sensor code; no changes |
| All backend API contracts | No changes |
| Navigation structure | 4-tab layout, sheet patterns, push navigation; no changes |
| Light mode | New gradient tokens are dark-only; adaptive light mode falls back to existing system colors |
| Natural-language summary copy | Excluded — insufficient varied content |
| `AppStoreScreenshotMode` | Debug-only; excluded |
| `PhotoCropView` | System-provided UI; not modified |
| `AvatarZoomView` background | Full-screen photo viewer stays black |
| Onboarding / first-run flow | Out of scope |
