# Design System Tokens + Accessibility Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `Radius` enum, `FTFont` style enum, and missing `Color.ft*` tokens to `DesignSystem.swift`, swap all ad-hoc literal call sites, and fix 10 accessibility issues (reduce-motion gates, VoiceOver labels, touch targets, contrast, haptics, pulse-animation gate).

**Architecture:** Pure additive token layer in `DesignSystem.swift` — no new files, no behavior changes. Each token maps 1:1 from an ad-hoc literal. Workstream 4 (Design System) and Workstream 9 (Accessibility) are bundled into a single PR per the spec's R3 phasing: "Both are visual; do together to avoid two visual diff passes."

**Tech Stack:** SwiftUI, iOS 17+

**Spec:** `docs/superpowers/specs/2026-06-10-ios-app-review-design.md` — Workstreams 4 and 9

---

## Part 1: DesignSystem.swift Token Additions

### Task 1: Add Radius enum to DesignSystem.swift

**Files:**
- Modify: `ios/FastTrack/FastTrack/DesignSystem.swift`

- [ ] **Step 1: Add Radius enum after the Spacing enum (after line 61)**

After the `Spacing` enum closing brace, add:

```swift
enum Radius {
    static let xxxs: CGFloat = 1.5
    static let xxs: CGFloat = 3
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 10
    static let lg: CGFloat = 12
    static let xl: CGFloat = 14
    static let xxl: CGFloat = 18
    static let xxxl: CGFloat = 20
    static let giant: CGFloat = 24
}
```

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && cp FastTrack/Secrets.swift.template FastTrack/Secrets.swift && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/DesignSystem.swift
git commit -m "feat(ios): add Radius enum to design system"
```

---

### Task 2: Add FTFont style enum to DesignSystem.swift

**Files:**
- Modify: `ios/FastTrack/FastTrack/DesignSystem.swift`

- [ ] **Step 1: Add FTFont enum after the Motion enum (after line 68)**

After `enum Motion { ... }` closing brace, add:

```swift
enum FTFont {
    static let speedHero = Font.system(size: 96, weight: .heavy, design: .monospaced)
    static let gaugeNumber = Font.system(size: 32, weight: .bold, design: .monospaced)
    static let gaugeValue = Font.system(size: 28, weight: .bold, design: .monospaced)
    static let gaugeLabelCompact = Font.system(size: 8, weight: .semibold)
    static let pill = Font.system(size: 9, weight: .bold)
    static let scoreboard = Font.system(size: 36)
    static let trophy = Font.system(size: 40)
    static let wordmark = Font.system(size: 36, weight: .bold, design: .rounded)
    static let appIcon = Font.system(size: 52, weight: .medium)
    static let iconLarge = Font.system(size: 80)
    static let iconXLarge = Font.system(size: 48, weight: .bold, design: .rounded)
    static let subtitleBold = Font.system(size: 18, weight: .bold)
    static let sectionCaption = Font.system(size: 24)
}
```

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/DesignSystem.swift
git commit -m "feat(ios): add FTFont style enum to design system"
```

---

### Task 3: Add missing Color.ft* tokens to DesignSystem.swift

**Files:**
- Modify: `ios/FastTrack/FastTrack/DesignSystem.swift`

- [ ] **Step 1: Add color tokens after the existing `ftHighlight` definition (after line 50)**

After `static let ftHighlight = ...` closing brace, insert:

```swift
    static let ftShimmer = Color(white: 1, opacity: 0.35)
    static let ftScrim = Color.black.opacity(0.45)
    static let ftRankGold = Color(red: 255/255, green: 214/255, blue: 10/255)
    static let ftRankSilver = Color(red: 192/255, green: 192/255, blue: 192/255)
    static let ftRankBronze = Color(red: 205/255, green: 127/255, blue: 50/255)
    static let ftOnDarkDivider = Color.white.opacity(0.14)
    static let ftHairline = Color.white.opacity(0.1)
    static let ftSkeleton = Color(.systemGray5)
    static let ftPB060Tint = Color.yellow
    static let ftPBTopSpeedTint = Color.red
    static let ftErrorBackground = Color.red.opacity(0.6)
```

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/DesignSystem.swift
git commit -m "feat(ios): add Color.ft tokens for shimmer, ranks, dividers, PB tints"
```

---

## Part 2: Swap cornerRadius Call Sites with Radius Enum

### Task 4: Swap cornerRadius in DesignSystem.swift + SharedComponents.swift

**Files:**
- Modify: `ios/FastTrack/FastTrack/DesignSystem.swift`
- Modify: `ios/FastTrack/FastTrack/Views/SharedComponents.swift`

DesignSystem.swift replacements:

| Line | Old | New |
|------|-----|-----|
| 143, 147 | `cornerRadius: 8` | `cornerRadius: Radius.sm` |
| 165 | `.cornerRadius(1.5)` | `.cornerRadius(Radius.xxxs)` |
| 176, 180 | `cornerRadius: 12` | `cornerRadius: Radius.lg` |
| 216, 220 | `cornerRadius: 12` | `cornerRadius: Radius.lg` |

SharedComponents.swift replacements:

| Line | Old | New |
|------|-----|-----|
| 280 | `.cornerRadius(10)` | `.cornerRadius(Radius.md)` |
| 299 | `.cornerRadius(12)` | `.cornerRadius(Radius.lg)` |
| 406 | `var cornerRadius: CGFloat = 6` | `var cornerRadius: CGFloat = Radius.xs + 2` |
| 409 | `RoundedRectangle(cornerRadius: cornerRadius)` | (unchanged — uses stored property) |
| 441 | `cornerRadius: 4` | `cornerRadius: Radius.xs` |
| 448 | `.cornerRadius(12)` | `.cornerRadius(Radius.lg)` |
| 503 | `.cornerRadius(8)` | `.cornerRadius(Radius.sm)` |
| 517 | `.cornerRadius(12)` | `.cornerRadius(Radius.lg)` |
| 569 | `.cornerRadius(4)` | `.cornerRadius(Radius.xs)` |
| 580 | `var cornerRadius: CGFloat = 10` | `var cornerRadius: CGFloat = Radius.md` |

- [ ] **Step 1: Apply all replacements in both files**

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/DesignSystem.swift ios/FastTrack/FastTrack/Views/SharedComponents.swift
git commit -m "refactor(ios): swap ad-hoc cornerRadius with Radius tokens in DesignSystem and SharedComponents"
```

---

### Task 5: Swap cornerRadius in ContentView.swift + DriveDetailView.swift + AchievementsView.swift

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/ContentView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/DriveDetailView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/AchievementsView.swift`

ContentView.swift replacements:

| Line | Old | New |
|------|-----|-----|
| 195 | `.cornerRadius(12)` | `.cornerRadius(Radius.lg)` |
| 232 | `RoundedRectangle(cornerRadius: 12)` | `RoundedRectangle(cornerRadius: Radius.lg)` |
| 343 | `RoundedRectangle(cornerRadius: 3, style: .continuous)` | `RoundedRectangle(cornerRadius: Radius.xxs, style: .continuous)` |
| 346 | `RoundedRectangle(cornerRadius: 3, style: .continuous)` | `RoundedRectangle(cornerRadius: Radius.xxs, style: .continuous)` |
| 357 | `RoundedRectangle(cornerRadius: 10, style: .continuous)` | `RoundedRectangle(cornerRadius: Radius.md, style: .continuous)` |
| 359 | `RoundedRectangle(cornerRadius: 10, style: .continuous)` | `RoundedRectangle(cornerRadius: Radius.md, style: .continuous)` |

DriveDetailView.swift replacements:

| Line | Old | New |
|------|-----|-----|
| 260 | `.cornerRadius(12)` | `.cornerRadius(Radius.lg)` |
| 269 | `RoundedRectangle(cornerRadius: 8)` | `RoundedRectangle(cornerRadius: Radius.sm)` |
| 295 | `RoundedRectangle(cornerRadius: 12)` | `RoundedRectangle(cornerRadius: Radius.lg)` |
| 425 | `.cornerRadius(12)` | `.cornerRadius(Radius.lg)` |
| 891 | `SpeechBubble(cornerRadius: 6, ...)` | `SpeechBubble(cornerRadius: Radius.xs + 2, ...)` |
| 895 | `SpeechBubble(cornerRadius: 6, ...)` | `SpeechBubble(cornerRadius: Radius.xs + 2, ...)` |

AchievementsView.swift replacements:

| Line | Old | New |
|------|-----|-----|
| 151 | `.cornerRadius(20)` | `.cornerRadius(Radius.xxxl)` |
| 223 | `.cornerRadius(12)` | `.cornerRadius(Radius.lg)` |
| 302 | `.cornerRadius(12)` | `.cornerRadius(Radius.lg)` |

- [ ] **Step 1: Apply all replacements in all three files**

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/ContentView.swift ios/FastTrack/FastTrack/Views/DriveDetailView.swift ios/FastTrack/FastTrack/Views/AchievementsView.swift
git commit -m "refactor(ios): swap ad-hoc cornerRadius with Radius tokens in ContentView, DriveDetailView, AchievementsView"
```

---

### Task 6: Swap cornerRadius in ProfileView.swift + GarageView.swift + SocialView.swift + SignInView.swift

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/ProfileView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/GarageView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/SocialView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/SignInView.swift`

ProfileView.swift replacements:

| Line | Old | New |
|------|-----|-----|
| 229 | `RoundedRectangle(cornerRadius: 12)` | `RoundedRectangle(cornerRadius: Radius.lg)` |
| 237 | `RoundedRectangle(cornerRadius: 12)` | `RoundedRectangle(cornerRadius: Radius.lg)` |
| 343 | `.cornerRadius(12)` | `.cornerRadius(Radius.lg)` |
| 359 | `.cornerRadius(12)` | `.cornerRadius(Radius.lg)` |
| 487 | `.cornerRadius(8)` | `.cornerRadius(Radius.sm)` |
| 572 | `RoundedRectangle(cornerRadius: 10)` | `RoundedRectangle(cornerRadius: Radius.md)` |
| 574 | `RoundedRectangle(cornerRadius: 10)` | `RoundedRectangle(cornerRadius: Radius.md)` |
| 581 | `RoundedRectangle(cornerRadius: 10)` | `RoundedRectangle(cornerRadius: Radius.md)` |

GarageView.swift replacements:

| Line | Old | New |
|------|-----|-----|
| 295 | `RoundedRectangle(cornerRadius: 14, style: .continuous)` | `RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)` |
| 333 | `RoundedRectangle(cornerRadius: 14, style: .continuous)` | `RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)` |
| 337 | `RoundedRectangle(cornerRadius: 14, style: .continuous)` | `RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)` |
| 346 (CarPhotoView) | `cornerRadius: 0` | (unchanged — intentional full-bleed) |

SocialView.swift replacements:

| Line | Old | New |
|------|-----|-----|
| 166 | `RoundedRectangle(cornerRadius: 10)` | `RoundedRectangle(cornerRadius: Radius.md)` |
| 255 | `RoundedRectangle(cornerRadius: 10)` | `RoundedRectangle(cornerRadius: Radius.md)` |
| 390 | `RoundedRectangle(cornerRadius: 6)` | `RoundedRectangle(cornerRadius: Radius.xs + 2)` |
| 395 | `RoundedRectangle(cornerRadius: 6)` | `RoundedRectangle(cornerRadius: Radius.xs + 2)` |

SignInView.swift replacements:

| Line | Old | New |
|------|-----|-----|
| 37 | `.cornerRadius(10)` | `.cornerRadius(Radius.md)` |
| 38 | `RoundedRectangle(cornerRadius: 10)` | `RoundedRectangle(cornerRadius: Radius.md)` |
| 50 | `.cornerRadius(10)` | `.cornerRadius(Radius.md)` |

- [ ] **Step 1: Apply all replacements in all four files**

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/ProfileView.swift ios/FastTrack/FastTrack/Views/GarageView.swift ios/FastTrack/FastTrack/Views/SocialView.swift ios/FastTrack/FastTrack/Views/SignInView.swift
git commit -m "refactor(ios): swap ad-hoc cornerRadius with Radius tokens in ProfileView, GarageView, SocialView, SignInView"
```

---

### Task 7: Swap cornerRadius in remaining components + CarDetailView + PublicCarDetailView

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/CarDetailView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/Components/RecentAchievementsStrip.swift`
- Modify: `ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift`
- Modify: `ios/FastTrack/FastTrack/Views/Components/PublicCarDetailGauge.swift`
- Modify: `ios/FastTrack/FastTrack/Views/Components/CarPhotoEditorSection.swift`
- Modify: `ios/FastTrack/FastTrack/Views/Components/CarHeroPhotoEditorSheet.swift`
- Modify: `ios/FastTrack/FastTrack/Views/DriveHistoryView.swift`

CarDetailView.swift:

| Line | Old | New |
|------|-----|-----|
| 194 | `RoundedRectangle(cornerRadius: 18, style: .continuous)` | `RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)` |
| 201 | `RoundedRectangle(cornerRadius: 18, style: .continuous)` | `RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous)` |
| 262 (CarPhotoView) | `cornerRadius: 0` | (unchanged — intentional full-bleed) |

PublicCarDetailView.swift:

| Line | Old | New |
|------|-----|-----|
| 107 | `RoundedRectangle(cornerRadius: 14)` | `RoundedRectangle(cornerRadius: Radius.xl)` |
| 114 (CarPhotoView) | `cornerRadius: 0` | (unchanged) |

RecentAchievementsStrip.swift:

| Line | Old | New |
|------|-----|-----|
| 116 | `RoundedRectangle(cornerRadius: 10)` | `RoundedRectangle(cornerRadius: Radius.md)` |
| 119 | `.cornerRadius(10)` | `.cornerRadius(Radius.md)` |

CarDetailGauge.swift:

| Line | Old | New |
|------|-----|-----|
| 86 | `RoundedRectangle(cornerRadius: 14, style: .continuous)` | `RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)` |
| 90 | `RoundedRectangle(cornerRadius: 14, style: .continuous)` | `RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)` |

PublicCarDetailGauge.swift:

| Line | Old | New |
|------|-----|-----|
| 48 | `RoundedRectangle(cornerRadius: 10)` | `RoundedRectangle(cornerRadius: Radius.md)` |
| 52 | `RoundedRectangle(cornerRadius: 10)` | `RoundedRectangle(cornerRadius: Radius.md)` |

CarPhotoEditorSection.swift:

| Line | Old | New |
|------|-----|-----|
| 34 | `RoundedRectangle(cornerRadius: 8)` | `RoundedRectangle(cornerRadius: Radius.sm)` |
| 100 | `RoundedRectangle(cornerRadius: 8)` | `RoundedRectangle(cornerRadius: Radius.sm)` |

CarHeroPhotoEditorSheet.swift:

| Line | Old | New |
|------|-----|-----|
| 44 | `RoundedRectangle(cornerRadius: 12, style: .continuous)` | `RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)` |
| 130 | `RoundedRectangle(cornerRadius: 12, style: .continuous)` | `RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)` |
| 136 | `RoundedRectangle(cornerRadius: 12, style: .continuous)` | `RoundedRectangle(cornerRadius: Radius.lg, style: .continuous)` |

DriveHistoryView.swift:

| Line | Old | New |
|------|-----|-----|
| 156 | `.cornerRadius(4)` | `.cornerRadius(Radius.xs)` |

- [ ] **Step 1: Apply all replacements in all eight files**

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/CarDetailView.swift ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift ios/FastTrack/FastTrack/Views/Components/RecentAchievementsStrip.swift ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift ios/FastTrack/FastTrack/Views/Components/PublicCarDetailGauge.swift ios/FastTrack/FastTrack/Views/Components/CarPhotoEditorSection.swift ios/FastTrack/FastTrack/Views/Components/CarHeroPhotoEditorSheet.swift ios/FastTrack/FastTrack/Views/DriveHistoryView.swift
git commit -m "refactor(ios): swap ad-hoc cornerRadius with Radius tokens in components and detail views"
```

---

## Part 3: Swap Font Call Sites with FTFont + Relative Styles

### Task 8: Swap font in DesignSystem.swift + SharedComponents.swift + FastTrackApp.swift

**Files:**
- Modify: `ios/FastTrack/FastTrack/DesignSystem.swift`
- Modify: `ios/FastTrack/FastTrack/Views/SharedComponents.swift`
- Modify: `ios/FastTrack/FastTrack/FastTrackApp.swift`

DesignSystem.swift (DashboardGauge):

| Line | Old | New |
|------|-----|-----|
| 136 | `.font(.system(size: 8, weight: .semibold))` | `.font(FTFont.gaugeLabelCompact)` |
| 153 | `.font(.system(size: 28, weight: .bold, design: .monospaced))` | `.font(FTFont.gaugeValue).minimumScaleFactor(0.6)` |
| 168 | `.font(.system(size: 9, weight: .semibold))` | `.font(.caption2.weight(.semibold)).minimumScaleFactor(0.75)` |

SharedComponents.swift (TrackMetricCard):

| Line | Old | New |
|------|-----|-----|
| 495 | `.font(.system(size: 9, weight: .semibold))` | `.font(.caption2.weight(.semibold)).minimumScaleFactor(0.75)` |
| 496 | `.font(.system(size: 8))` | `.font(.caption2).minimumScaleFactor(0.7)` |

FastTrackApp.swift (splash screen):

| Line | Old | New |
|------|-----|-----|
| 206 | `.font(.system(size: 52, weight: .medium))` | `.font(FTFont.appIcon).minimumScaleFactor(0.6)` |
| 215 | `.font(.system(size: 36, weight: .bold, design: .rounded))` | `.font(FTFont.wordmark).minimumScaleFactor(0.6)` |

- [ ] **Step 1: Apply all replacements in all three files**

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/DesignSystem.swift ios/FastTrack/FastTrack/Views/SharedComponents.swift ios/FastTrack/FastTrack/FastTrackApp.swift
git commit -m "refactor(ios): swap ad-hoc fonts with FTFont tokens in DesignSystem, SharedComponents, splash"
```

---

### Task 9: Swap font in ContentView.swift + GarageView.swift + CarDetailView.swift

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/ContentView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/GarageView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/CarDetailView.swift`

ContentView.swift:

| Line | Old | New |
|------|-----|-----|
| 89 | `.font(.system(size: 96, weight: .heavy, design: .monospaced))` | `.font(FTFont.speedHero).minimumScaleFactor(0.5)` |
| 333 | `.font(.system(size: 8, weight: .semibold))` | `.font(FTFont.gaugeLabelCompact).minimumScaleFactor(0.7)` |
| 339 | `.font(.system(size: 9, weight: .bold))` | `.font(FTFont.pill).minimumScaleFactor(0.7)` |
| 432 | `.font(.system(size: 18, weight: .bold))` | `.font(FTFont.subtitleBold).minimumScaleFactor(0.6)` |

GarageView.swift:

| Line | Old | New |
|------|-----|-----|
| 183 | `.font(.system(size: 36))` | `.font(FTFont.scoreboard).minimumScaleFactor(0.6)` |
| 430 | `.font(.system(size: 9, weight: .bold))` | `.font(FTFont.pill).minimumScaleFactor(0.7)` |

CarDetailView.swift:

| Line | Old | New |
|------|-----|-----|
| 236 | `.font(.system(size: 24))` | `.font(FTFont.sectionCaption).minimumScaleFactor(0.6)` |

- [ ] **Step 1: Apply all replacements in all three files**

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/ContentView.swift ios/FastTrack/FastTrack/Views/GarageView.swift ios/FastTrack/FastTrack/Views/CarDetailView.swift
git commit -m "refactor(ios): swap ad-hoc fonts with FTFont tokens in ContentView, GarageView, CarDetailView"
```

---

### Task 10: Swap font in DriveDetailView.swift + Component views

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/DriveDetailView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift`
- Modify: `ios/FastTrack/FastTrack/Views/Components/PublicCarDetailGauge.swift`
- Modify: `ios/FastTrack/FastTrack/Views/Components/RecentAchievementsStrip.swift`
- Modify: `ios/FastTrack/FastTrack/Views/Components/CarHeroPhotoEditorSheet.swift`
- Modify: `ios/FastTrack/FastTrack/Views/Components/CarPhotoView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/AvatarZoomView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/SignInView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/AchievementsView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/DriveHistoryView.swift`

DriveDetailView.swift:

| Line | Old | New |
|------|-----|-----|
| 267 | `.font(.system(size: 13, weight: .semibold))` | `.font(.footnote.weight(.semibold)).minimumScaleFactor(0.8)` |
| 325 | `.font(.system(size: 10))` | `.font(.caption).minimumScaleFactor(0.8)` |
| 331 | `.font(.system(size: 10))` | `.font(.caption).minimumScaleFactor(0.8)` |
| 340 | `.font(.system(size: 10))` | `.font(.caption).minimumScaleFactor(0.8)` |
| 882 | `.font(.system(size: 9, weight: .bold))` | `.font(FTFont.pill).minimumScaleFactor(0.7)` |
| 885 | `.font(.system(size: 11, weight: .bold, design: .rounded))` | `.font(.caption.weight(.bold)).minimumScaleFactor(0.8)` |

CarDetailGauge.swift:

| Line | Old | New |
|------|-----|-----|
| 61 | `.font(.system(size: 32, weight: .bold, design: .monospaced))` | `.font(FTFont.gaugeNumber).minimumScaleFactor(0.6)` |

PublicCarDetailGauge.swift:

| Line | Old | New |
|------|-----|-----|
| 35 | `.font(.system(size: 10, weight: .semibold))` | `.font(.caption.weight(.semibold)).minimumScaleFactor(0.8)` |
| 39 | `.font(.system(size: 9))` | `.font(.caption2).minimumScaleFactor(0.75)` |

RecentAchievementsStrip.swift:

| Line | Old | New |
|------|-----|-----|
| 99 | `.font(.system(size: 40))` | `.font(FTFont.trophy).minimumScaleFactor(0.6)` |

CarHeroPhotoEditorSheet.swift:

| Line | Old | New |
|------|-----|-----|
| 139 | `.font(.system(size: 48))` | `.font(FTFont.iconXLarge).minimumScaleFactor(0.6)` |

CarPhotoView.swift:

| Line | Old | New |
|------|-----|-----|
| 57 | `.font(.system(size: 48, weight: .bold, design: .rounded))` | `.font(FTFont.iconXLarge).minimumScaleFactor(0.6)` |

AvatarZoomView.swift:

| Line | Old | New |
|------|-----|-----|
| 20 | `.font(.system(size: 30))` | `.font(.title).minimumScaleFactor(0.6)` |
| 29 | `.font(.system(size: 30))` | `.font(.title).minimumScaleFactor(0.6)` |

SignInView.swift:

| Line | Old | New |
|------|-----|-----|
| 16 | `.font(.system(size: 80))` | `.font(FTFont.iconLarge).minimumScaleFactor(0.6)` |

AchievementsView.swift:

| Line | Old | New |
|------|-----|-----|
| 241 | `.font(.system(size: 80))` | `.font(FTFont.iconLarge).minimumScaleFactor(0.6)` |

DriveHistoryView.swift:

| Line | Old | New |
|------|-----|-----|
| 176 | `.font(.system(size: 9, weight: .bold))` | `.font(FTFont.pill).minimumScaleFactor(0.7)` |

- [ ] **Step 1: Apply all replacements in all files**

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/DriveDetailView.swift ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift ios/FastTrack/FastTrack/Views/Components/PublicCarDetailGauge.swift ios/FastTrack/FastTrack/Views/Components/RecentAchievementsStrip.swift ios/FastTrack/FastTrack/Views/Components/CarHeroPhotoEditorSheet.swift ios/FastTrack/FastTrack/Views/Components/CarPhotoView.swift ios/FastTrack/FastTrack/Views/AvatarZoomView.swift ios/FastTrack/FastTrack/Views/SignInView.swift ios/FastTrack/FastTrack/Views/AchievementsView.swift ios/FastTrack/FastTrack/Views/DriveHistoryView.swift
git commit -m "refactor(ios): swap ad-hoc fonts with FTFont/relative styles in detail views and components"
```

---

## Part 4: Swap Color Call Sites with ft* Tokens

### Task 11: Swap color tokens in view files (part 1)

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/ContentView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/DriveDetailView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/SignInView.swift`

ContentView.swift:

| Line | Old | New |
|------|-----|-----|
| 233 | `Color.red.opacity(0.6)` | `Color.ftErrorBackground` |
| 295 | `Color.white.opacity(0.1)` | `Color.ftHairline` |
| 360 | `Color.white.opacity(0.14)` | `Color.ftOnDarkDivider` |
| 417 | `Color.blue` | `Color.ftBlue` |

DriveDetailView.swift:

| Line | Old | New |
|------|-----|-----|
| 324 | `Color.green` | `Color.ftGreen` |
| 330 | `Color.red` | `Color.ftRed` |
| 350 | `Color.orange` | `Color.ftAmber` (closest semantic match for route event span) |
| 367 | `Color.white` | keep as is (decorative map annotation stroke) |
| 621 | `Color.orange` | `Color.ftAmber` |
| 628 | `Color.yellow` | `Color.ftGold` |
| 892 | `Color.yellow` / `Color.orange` | `Color.ftPB060Tint` / `Color.ftAmber` |
| 896 | `Color.white` | keep (stroke) |

SignInView.swift:

| Line | Old | New |
|------|-----|-----|
| 35 | `Color.white` | keep (Google button background) |
| 39 | `Color.gray.opacity(0.4)` | `Color.ftOnDarkDivider` |
| 90 | `Color(.systemGroupedBackground)` | `Color.ftSurfaceBg` (already an adaptive bg token) |

- [ ] **Step 1: Apply all replacements in all three files**

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/ContentView.swift ios/FastTrack/FastTrack/Views/DriveDetailView.swift ios/FastTrack/FastTrack/Views/SignInView.swift
git commit -m "refactor(ios): swap ad-hoc colors with ft tokens in ContentView, DriveDetailView, SignInView"
```

---

### Task 12: Swap color tokens in view files (part 2)

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/DriveHistoryView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/ProfileView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/CarDetailView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/SharedComponents.swift`
- Modify: `ios/FastTrack/FastTrack/Views/FindPeopleView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/PublicProfileView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/NotificationsBell.swift`
- Modify: `ios/FastTrack/FastTrack/Views/Components/CarPhotoEditorSection.swift`

DriveHistoryView.swift:

| Line | Old | New |
|------|-----|-----|
| 11 | `Color.yellow.opacity(0.15)` | `Color.ftPB060Tint.opacity(0.15)` |
| 12 | `Color.red.opacity(0.10)` | `Color.ftPBTopSpeedTint.opacity(0.10)` |
| 141 | `bg: Color.yellow, fg: Color.black` | `bg: Color.ftPB060Tint, fg: Color.black` |
| 145 | `bg: Color.red, fg: Color.white` | `bg: Color.ftPBTopSpeedTint, fg: Color.white` |

ProfileView.swift:

| Line | Old | New |
|------|-----|-----|
| 230 | `Color(.systemGray6).opacity(0.2)` | `Color.ftCardBg.opacity(0.2)` |
| 238 | `Color(.systemGray6).opacity(0.2)` | `Color.ftCardBg.opacity(0.2)` |
| 342 | `Color(.systemGray6)` | `Color.ftCardBg` |
| 358 | `Color(.systemGray6)` | `Color.ftCardBg` |

CarDetailView.swift:

| Line | Old | New |
|------|-----|-----|
| 239 | `Color.black.opacity(0.45)` | `Color.ftScrim` |
| 378 | `Color.red` | `Color.ftRed` |

SharedComponents.swift:

| Line | Old | New |
|------|-----|-----|
| 377 | `Color.white.opacity(0.35)` | `Color.ftShimmer` |
| 422 | `Color(.systemGray5)` | `Color.ftSkeleton` |

FindPeopleView.swift:

| Line | Old | New |
|------|-----|-----|
| 22 | `Color.clear` | keep (clear is semantic) |
| 25 | `Color.clear` | keep |
| 32 | `Color.clear` | keep |
| 39 | `Color.clear` | keep |
| 178 | `Color(.systemFill)` | keep (system-provided semantic color, appropriate for inactive state) |
| 186 | `Color.ftBlue` | already uses ft token — no change |

PublicProfileView.swift:

| Line | Old | New |
|------|-----|-----|
| 220 | `Color(.systemFill)` | keep (system-provided semantic color) |

NotificationsBell.swift:

| Line | Old | New |
|------|-----|-----|
| 18 | `Color.red` | `Color.ftRed` |

CarPhotoEditorSection.swift:

| Line | Old | New |
|------|-----|-----|
| 101 | `Color.blue.opacity(0.15)` | `Color.ftBlue.opacity(0.15)` |

- [ ] **Step 1: Apply all replacements in all eight files**

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/DriveHistoryView.swift ios/FastTrack/FastTrack/Views/ProfileView.swift ios/FastTrack/FastTrack/Views/CarDetailView.swift ios/FastTrack/FastTrack/Views/SharedComponents.swift ios/FastTrack/FastTrack/Views/FindPeopleView.swift ios/FastTrack/FastTrack/Views/PublicProfileView.swift ios/FastTrack/FastTrack/Views/NotificationsBell.swift ios/FastTrack/FastTrack/Views/Components/CarPhotoEditorSection.swift
git commit -m "refactor(ios): swap ad-hoc colors with ft tokens in remaining view files"
```

---

## Part 5: Accessibility Fixes (Workstream 9)

### Task 13: G-1 — Add reduce-motion gates on infinite-loop animations

**Files:**
- Modify: `ios/FastTrack/FastTrack/FastTrackApp.swift` (splash dot bounce)
- Modify: `ios/FastTrack/FastTrack/Views/ContentView.swift` (recording pulse)
- Modify: `ios/FastTrack/FastTrack/Views/SharedComponents.swift` (shimmer)
- Modify: `ios/FastTrack/FastTrack/Views/Components/ConfettiView.swift` (confetti TimelineView)

In FastTrackApp.swift, the splash dots at line 232-234 need a reduce-motion gate. The three dots have `repeatForever`. In the `SplashView` struct (which contains the dot animation), add:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

Then wrap the dot animation:

At line 232, change:
```swift
.animation(
    .easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15),
    value: dotOffset
)
```
to:
```swift
.animation(
    reduceMotion ? nil : .easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15),
    value: dotOffset
)
```

In ContentView.swift, the recording pulse at line 236-241 needs a gate. In the struct containing the Start/Stop button body (the `driveControlSection` area), add:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

At line 236-241, change:
```swift
.animation(
    driveManager.isRecording
        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        : .default,
    value: driveManager.isRecording
)
```
to:
```swift
.animation(
    driveManager.isRecording && !reduceMotion
        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        : .default,
    value: driveManager.isRecording
)
```

In SharedComponents.swift, the shimmer modifier at line 389 uses `repeatForever`. In `ShimmerModifier`, add:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion
```

At line 389, change:
```swift
withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
    phase = 1
}
```
to:
```swift
if !reduceMotion {
    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
        phase = 1
    }
}
```

In `ConfettiView`, the `TimelineView(.animation(...))` at line 63 is the 60fps driver. Wrap the body content:

At line 62-71, change the `body` to gate on reduce-motion:

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

var body: some View {
    if reduceMotion {
        Color.clear
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    } else {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: false)) { context in
            Canvas { gc, size in
                let elapsed = context.date.timeIntervalSince(startTime)
                draw(in: gc, size: size, time: elapsed)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
```

- [ ] **Step 1: Add reduceMotion environment and gate animations in all four files**

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/FastTrackApp.swift ios/FastTrack/FastTrack/Views/ContentView.swift ios/FastTrack/FastTrack/Views/SharedComponents.swift ios/FastTrack/FastTrack/Views/Components/ConfettiView.swift
git commit -m "a11y(ios): gate infinite-loop animations on accessibilityReduceMotion"
```

---

### Task 14: G-2 — Add VoiceOver labels

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/ContentView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/AvatarZoomView.swift`

**Map annotations in LiveMapView** (ContentView.swift line 410-420):

Add `accessibilityLabel` to the GPS dot annotation (line 411):

Change:
```swift
Annotation("", coordinate: userLocation) {
```
To:
```swift
Annotation("Current location", coordinate: userLocation) {
```

Add `accessibilityLabel` to the route start flag (line 428-433):

```swift
Annotation("", coordinate: first) {
    Image(systemName: "flag.checkered")
        .foregroundColor(.ftGreen)
        .font(FTFont.subtitleBold)
}
.accessibilityLabel("Route start")
```

**GPS status dot** (ContentView.swift line 108-110):

Add to the Circle:
```swift
Circle()
    .fill(gpsStatusColor)
    .frame(width: 7, height: 7)
    .accessibilityLabel("GPS: \(gpsStatusText)")
```

**Speed hero ring** (ContentView.swift line 80-85):

The `SpeedHeroRing` is already a visual element. Add:
```swift
SpeedHeroRing(...)
    .frame(width: 256, height: 256)
    .accessibilityLabel("Current speed \(Int(settings.calibratedSpeedValue(locationManager.currentSpeed))) \(settings.speedUnit)")
```

**Avatar tap-zoom** (AvatarZoomView.swift):

At the avatar image in the zoom view (around line 20), add after the existing `.accessibilityLabel("Edit avatar")` also for the image itself:

Read the file and add accessibility to the tabbed avatar image. The avatar should have:
```swift
.accessibilityLabel("Avatar photo")
.accessibilityHint("Double tap to edit or dismiss")
```

- [ ] **Step 1: Read both files, apply accessibilityLabel additions at the identified locations**

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/ContentView.swift ios/FastTrack/FastTrack/Views/AvatarZoomView.swift
git commit -m "a11y(ios): add VoiceOver labels to map, GPS dot, speed ring, avatar"
```

---

### Task 15: G-3 + G-4 + G-5 — Touch targets + Dynamic Type + Contrast

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/NotificationsBell.swift`
- Modify: `ios/FastTrack/FastTrack/Views/PublicProfileView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/FindPeopleView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/GarageView.swift`

**G-3: NotificationsBell minimum 44pt touch target** (NotificationsBell.swift line 10):

Change:
```swift
.frame(width: 32, height: 32)
```
To:
```swift
.frame(minWidth: 44, minHeight: 44)
```

**G-3: Follow buttons minimum 44pt** — PublicProfileView.swift line 211 and FindPeopleView.swift:

PublicProfileView.swift: Change both `frame(width: 80, height: 28)` at lines 211 and 217 to:
```swift
.frame(minWidth: 80, minHeight: 44)
```

For the `.frame(width: 80)` at line 170 in FindPeopleView.swift, change to:
```swift
.frame(minWidth: 80, minHeight: 44)
```

**G-4: Dynamic Type scaling** — Covered by the FTFont enum + minimumScaleFactor additions in Tasks 8-10. The remaining fixed-point fonts (8pt gauge labels, 9pt pills, etc.) now have minimumScaleFactor. No additional changes needed for G-4.

**G-5: GarageView follow button contrast** (GarageView.swift line 442):

The `Color.secondary.opacity(0.5)` on a chevron inside a button is below WCAG AA contrast. At line 442, change:
```swift
.foregroundColor(Color.secondary.opacity(0.5))
```
To:
```swift
.foregroundColor(Color.secondary.opacity(0.7))
```

- [ ] **Step 1: Apply all touch target, contrast, and frame changes in the four files**

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/NotificationsBell.swift ios/FastTrack/FastTrack/Views/PublicProfileView.swift ios/FastTrack/FastTrack/Views/FindPeopleView.swift ios/FastTrack/FastTrack/Views/GarageView.swift
git commit -m "a11y(ios): fix touch targets to 44pt minimum and improve contrast"
```

---

### Task 16: P2-9 + P2-10 — Haptics on Start Drive + gate pulse animation

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/ContentView.swift`

**P2-9: Add `.sensoryFeedback` to Start Drive button:**

In the Start Drive button action (line 218), add haptic feedback:

After `driveManager.startRecording()`, add `.sensoryFeedback(.impact(weight: .medium), trigger: driveManager.isRecording)` — but this needs to be on the button view, not inside an action closure. Better approach: add to the Button view modifier chain.

Find the Start Drive Button at line 210. The Button already has `.buttonStyle(InstrumentButtonStyle(color: ...))` followed by `.overlay(...)`. Add after the overlay:

```swift
.sensoryFeedback(.impact(weight: .medium), trigger: driveManager.isRecording) { oldValue, newValue in
    newValue  // fire when recording starts
}
```

This fires when `isRecording` transitions from false to true.

**P2-10: Gate pulse animation on visibility:**

The recording pulse animation (the red border at line 231-242) runs forever even when the ContentView is backgrounded or on other tabs. Per the spec: "Gate on reduce-motion and pause when not visible."

The reduce-motion gate was already added in Task 13. For the "pause when not visible" part, use `@Environment(\.scenePhase)` to gate.

In the struct that contains the driveControlSection, add:

```swift
@Environment(\.scenePhase) private var scenePhase
```

Then at line 236-241 change the animation to also check scene phase:

```swift
.animation(
    driveManager.isRecording && !reduceMotion && scenePhase == .active
        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        : .default,
    value: driveManager.isRecording
)
```

Wait — `scenePhase` changing won't trigger this `value:` key, so the animation won't react. Instead, make scene phase a dependent value:

```swift
.animation(
    driveManager.isRecording && !reduceMotion && scenePhase == .active
        ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
        : .default,
    value: driveManager.isRecording
)
.id("pulse-\(scenePhase)")  // force re-evaluation on scene phase change
```

Using `.id()` is safer here.

- [ ] **Step 1: Read ContentView.swift, identify the exact struct containing the Start button, add the environment and modifiers**

- [ ] **Step 2: Build to verify no errors**

Run: `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

- [ ] **Step 3: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/ContentView.swift
git commit -m "a11y(ios): add haptic feedback to Start Drive and gate pulse on scene visibility"
```

---

## Verification

Before the final PR:

```bash
cd ios/FastTrack && cp FastTrack/Secrets.swift.template FastTrack/Secrets.swift
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO
xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack -destination "platform=iOS Simulator,name=iPhone 17 Pro" CODE_SIGNING_ALLOWED=NO
```

Visual verification (manual):
- Dynamic Type: Set to largest and smallest sizes, verify all views still readable
- Reduce Motion: Enable, verify splash dots don't bounce, recording pulse doesn't animate, shimmer doesn't shimmer, confetti doesn't render
- VoiceOver: Walk through recording screen, verify GPS dot announces status, speed ring announces speed, avatar announces edit hint
- Touch targets: Verify bell and follow buttons are at least 44pt tall (tappable without precision)
- Contrast: Verify the chevron in garage follow button is readable
- Haptics: Tap Start Drive, feel medium impact
- Pulse: Background the app while recording, pulse stops; foreground again, pulse resumes
