# iOS Design Language Rework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Apply the "Dark Asphalt" design language across the entire FastTrack iOS app — gradient backgrounds, glass cards, status dots, micro-sparklines, gradient progress bars, open arc speedometer, floating pill tab bar, and a redesigned achievements system.

**Architecture:** All changes are purely iOS SwiftUI / UIKit surface layer. Work proceeds in strict dependency order: (1) design tokens + shared components, (2) new pattern components, (3) screen-by-screen application, (4) achievements redesign, (5) public profile realignment. No backend changes. No new screens except component additions.

**Tech Stack:** SwiftUI, Swift Charts, MapKit (read-only), SF Symbols, Xcode 16 (PBXFileSystemSynchronizedRootGroup — new `.swift` files are auto-discovered, no project.pbxproj edits needed)

**Reference spec:** `docs/superpowers/specs/2026-06-15-ios-design-language-rework.md`

**Build/test commands:**
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

---

## File Map

| File | Action | What changes |
|---|---|---|
| `FastTrack/DesignSystem.swift` | Modify | New gradient tokens, retire `ftCardBg`/`ftSectionBg`, update `ftGlassCard`, add `StatusLevel` enum |
| `FastTrack/Views/Components/SharedComponents.swift` | Modify | `InstrumentCard` (remove `glass:` param), delete `GaugeProgressBar`, add `GradientProgressBar`, add `StatusDot`, add `AchievementChip` |
| `FastTrack/Views/ContentView.swift` | Modify | `SpeedHeroRing` → open arc, `TrackMetricCard` → glass + sparkline + progress bar, remove `.activeGlow()`, gradient background, tab bar hidden during recording |
| `FastTrack/RootView.swift` or `FastTrack/FastTrackApp.swift` | Modify | Replace system tab bar with `FloatingTabBar` overlay |
| `FastTrack/Views/Components/FloatingTabBar.swift` | Create | New floating pill tab bar component |
| `FastTrack/Views/Components/FTGauge.swift` | Modify | `.compact` → glass + `GradientProgressBar` + sparkline; `.hero` → open arc + `GradientProgressBar(.hero)` |
| `FastTrack/Views/DriveDetailView/DriveDetailGauges.swift` | Modify | `ftGlassCard` + `GradientProgressBar` + sparkline per cell |
| `FastTrack/Views/DriveDetailView/DriveDetailMap.swift` | Modify | Scrubber panel + `SpeechBubble` fills → `ftGlassCard` |
| `FastTrack/Views/DriveDetailView/DriveDetailView.swift` | Modify | Gradient background, PB `StatusDot` header pill |
| `FastTrack/Views/DriveDetailView/DriveDetailAttemptsList.swift` | Modify | Rows → `ftGlassCard` |
| `FastTrack/Views/DriveHistoryView.swift` | Modify | Gradient background, `rowTint()` → glass+tint, `StatusDot` on top speed |
| `FastTrack/Views/GarageView.swift` | Modify | Gradient background, `GarageCarCard` → glass + `StatusDot` |
| `FastTrack/Views/CarDetailView/CarDetailView.swift` | Modify | Gradient background, achievements section |
| `FastTrack/Views/CarDetailView/CarDetailHero.swift` | Modify | `FTGauge .hero` → open arc (inherits via FTGauge update) |
| `FastTrack/Views/CarDetailView/CarDetailDrivesList.swift` | Modify | Rows → glass + `StatusDot`, achievements section → chip strip |
| `FastTrack/Views/SocialView.swift` | Modify | Gradient background, filter chips → glass, your-position card → blue-tinted glass, rows → glass + `StatusDot` |
| `FastTrack/Views/ProfileView.swift` | Modify | Gradient background, `RecentAchievementsStrip` → new achievements section, rows → glass |
| `FastTrack/Views/PublicProfileView.swift` | Modify | `List` → `ScrollView+VStack`, header strips location data, garage → `LazyVGrid` matching `GarageView` |
| `FastTrack/Views/PublicCarDetailView.swift` | Modify | Gradient background, nav title simplified, rows → glass |
| `FastTrack/Views/DrivePerformanceDetailView.swift` | Modify | Gradient background (inherits glass through `InstrumentCard`) |
| `FastTrack/Views/SettingsView.swift` | Modify | Gradient background, rows → glass |
| `FastTrack/Views/NotificationsView.swift` | Modify | Gradient background, `listRowBackground` → glass |
| `FastTrack/Views/FindPeopleView.swift` | Modify | Gradient background, rows → glass |
| `FastTrack/Views/FollowersListView.swift` | Modify | Gradient background, rows → glass |
| `FastTrack/Views/ProfileSetupView.swift` | Modify | Gradient background, fields → glass |
| `FastTrack/Views/SignInView.swift` | Modify | Gradient background |
| `FastTrack/FastTrackApp.swift` (SplashView) | Modify | Gradient background |
| `FastTrack/Views/AchievementsView.swift` | Modify | Gradient background, 3-col badge grid, filter chips → glass |
| `FastTrack/Views/Components/AchievementBadgeCard.swift` | Create | New compact badge card (unlocked/locked/unknown states) |
| `FastTrack/Views/Components/RecentAchievementsStrip.swift` | Delete | Replaced by inline section in `ProfileView` |
| `FastTrack/Views/Components/ToastView.swift` (or SharedComponents) | Modify | Background → glass |
| `FastTrack/Views/Components/SkeletonComponents.swift` (or SharedComponents) | Modify | Skeleton fills → `white.opacity(0.06)` |
| `FastTrackTests/DesignSystemTests.swift` | Create | Token existence + color value tests |
| `FastTrackTests/GradientProgressBarTests.swift` | Create | Value clamping, range mapping |
| `FastTrackTests/StatusDotTests.swift` | Create | Correct color per `StatusLevel` |

---

## Task 1: Update Design Tokens in DesignSystem.swift

**Files:**
- Modify: `FastTrack/DesignSystem.swift`
- Create: `FastTrackTests/DesignSystemTests.swift`

- [ ] **Step 1: Write failing tests for new tokens**

Create `FastTrackTests/DesignSystemTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import FastTrack

final class DesignSystemTests: XCTestCase {

    func testStatusLevelColors() {
        XCTAssertEqual(StatusLevel.best.color, Color.ftGold)
        XCTAssertEqual(StatusLevel.improving.color, Color.ftGreen)
        XCTAssertEqual(StatusLevel.nearBest.color, Color.ftAmber)
        XCTAssertEqual(StatusLevel.typical.color, Color.ftBlue)
    }

    func testFtBgGradientIsNotNil() {
        // Just verify the properties exist and don't crash on access
        let _ = Color.ftBgGradient
        let _ = Color.ftBgGradientWarm
    }

    func testFtGlassCardFillOpacity() {
        // ftGlassCard surface fill should be white at ~7% opacity
        // We test this by checking the token exists and is distinct from clear
        let fill = Color.ftGlassCardFill
        XCTAssertNotEqual(fill, Color.clear)
    }
}
```

- [ ] **Step 2: Run tests — expect compile failure**

```bash
cd ios/FastTrack
xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/DesignSystemTests CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|FAILED|PASSED"
```

Expected: compile error — `StatusLevel`, `ftBgGradient`, `ftBgGradientWarm`, `ftGlassCardFill` not defined.

- [ ] **Step 3: Add new tokens and enum to DesignSystem.swift**

Open `FastTrack/DesignSystem.swift`. Make the following changes:

**3a. Add `StatusLevel` enum** (add after the existing color extension block):

```swift
public enum StatusLevel {
    case best       // ftGold  — PB, #1 rank
    case improving  // ftGreen — improving, above average, GPS excellent
    case nearBest   // ftAmber — near best, active, GPS good
    case typical    // ftBlue  — normal, info, GPS fair
    case inactive   //          — idle, locked, GPS poor

    public var color: Color {
        switch self {
        case .best:      return .ftGold
        case .improving: return .ftGreen
        case .nearBest:  return .ftAmber
        case .typical:   return .ftBlue
        case .inactive:  return Color(white: 0.33)
        }
    }
}
```

**3b. Add gradient background tokens** (add inside the `Color` extension):

```swift
/// Default screen background — deep navy → near-black radial gradient.
static var ftBgGradient: some ShapeStyle {
    RadialGradient(
        colors: [Color(red: 0.10, green: 0.10, blue: 0.23), Color(red: 0.027, green: 0.027, blue: 0.043)],
        center: .topLeading,
        startRadius: 0,
        endRadius: 500
    )
}

/// Recording-active screen background — warm dark radial gradient.
static var ftBgGradientWarm: some ShapeStyle {
    RadialGradient(
        colors: [Color(red: 0.12, green: 0.04, blue: 0.0), Color(red: 0.027, green: 0.027, blue: 0.043)],
        center: .top,
        startRadius: 0,
        endRadius: 500
    )
}
```

**3c. Add glass card fill token** (add inside the `Color` extension):

```swift
/// Glass card fill — white at ~7% opacity. Use with `ftGlassCardStroke` border.
static let ftGlassCardFill = Color.white.opacity(0.07)
/// Glass card border stroke — white at ~12% opacity.
static let ftGlassCardStroke = Color.white.opacity(0.12)
```

**3d. Mark `ftCardBg` as deprecated** (do not delete yet — will be removed after all callsites are migrated in later tasks):

```swift
@available(*, deprecated, renamed: "ftGlassCardFill", message: "Migrate to ftGlassCardFill + ftGlassCardStroke")
static let ftCardBg = Color(red: 0.071, green: 0.071, blue: 0.086)
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd ios/FastTrack
xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/DesignSystemTests CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|FAILED|PASSED"
```

Expected: `DesignSystemTests` — all 3 tests PASSED.

- [ ] **Step 5: Commit**

```bash
cd ios/FastTrack
git add FastTrack/DesignSystem.swift FastTrackTests/DesignSystemTests.swift
git commit -m "feat(design): add gradient background tokens, StatusLevel enum, glass card tokens"
```

---

## Task 2: Update InstrumentCard — Always Glass

**Files:**
- Modify: `FastTrack/Views/Components/SharedComponents.swift`

- [ ] **Step 1: Find InstrumentCard in SharedComponents.swift**

Open `FastTrack/Views/Components/SharedComponents.swift`. Find `InstrumentCard`. It currently has a `glass: Bool = false` parameter and branches on it.

- [ ] **Step 2: Rewrite InstrumentCard**

Replace the entire `InstrumentCard` struct with:

```swift
public struct InstrumentCard<Content: View>: View {
    let content: Content
    var padding: CGFloat = Spacing.md

    public init(padding: CGFloat = Spacing.md, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(Color.ftGlassCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl)
                    .stroke(Color.ftGlassCardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }
}
```

Note: if your codebase has callers passing `glass: true` explicitly, those calls will now produce a compiler warning (unused argument). Remove the `glass:` label at those callsites — the behavior is identical.

- [ ] **Step 3: Build to find all broken callsites**

```bash
cd ios/FastTrack
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep "error:" | head -40
```

Fix any `glass:` argument errors by removing the `glass:` label from each callsite. The rendered appearance is the same — all cards are now glass.

- [ ] **Step 4: Build clean**

```bash
cd ios/FastTrack
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED` with 0 errors.

- [ ] **Step 5: Commit**

```bash
cd ios/FastTrack
git add FastTrack/Views/Components/SharedComponents.swift
git commit -m "refactor(design): InstrumentCard always glass, remove glass: parameter"
```

---

## Task 3: Add GradientProgressBar, Delete GaugeProgressBar

**Files:**
- Modify: `FastTrack/Views/Components/SharedComponents.swift`
- Create: `FastTrackTests/GradientProgressBarTests.swift`

- [ ] **Step 1: Write failing tests**

Create `FastTrackTests/GradientProgressBarTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import FastTrack

final class GradientProgressBarTests: XCTestCase {

    func testFractionClampedAtZero() {
        let bar = GradientProgressBar(value: -10, range: 0...100, size: .compact)
        XCTAssertEqual(bar.fraction, 0.0, accuracy: 0.001)
    }

    func testFractionClampedAtOne() {
        let bar = GradientProgressBar(value: 200, range: 0...100, size: .compact)
        XCTAssertEqual(bar.fraction, 1.0, accuracy: 0.001)
    }

    func testFractionMidpoint() {
        let bar = GradientProgressBar(value: 50, range: 0...100, size: .compact)
        XCTAssertEqual(bar.fraction, 0.5, accuracy: 0.001)
    }

    func testCompactHeight() {
        let bar = GradientProgressBar(value: 50, range: 0...100, size: .compact)
        XCTAssertEqual(bar.trackHeight, 5.0, accuracy: 0.001)
        XCTAssertEqual(bar.dotDiameter, 9.0, accuracy: 0.001)
    }

    func testHeroHeight() {
        let bar = GradientProgressBar(value: 50, range: 0...100, size: .hero)
        XCTAssertEqual(bar.trackHeight, 8.0, accuracy: 0.001)
        XCTAssertEqual(bar.dotDiameter, 14.0, accuracy: 0.001)
    }
}
```

- [ ] **Step 2: Run — expect compile failure**

```bash
cd ios/FastTrack
xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/GradientProgressBarTests CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|FAILED|PASSED"
```

Expected: compile error — `GradientProgressBar` not defined.

- [ ] **Step 3: Add GradientProgressBar to SharedComponents.swift**

Add after `InstrumentCard`:

```swift
public enum GradientProgressBarSize {
    case compact, hero
}

public struct GradientProgressBar: View {
    let value: Double
    let range: ClosedRange<Double>
    let size: GradientProgressBarSize

    public var fraction: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return max(0, min(1, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    public var trackHeight: CGFloat { size == .compact ? 5 : 8 }
    public var dotDiameter: CGFloat { size == .compact ? 9 : 14 }

    private let gradient = LinearGradient(
        colors: [.ftGreen, .ftGold, .ftAmber, .ftRed],
        startPoint: .leading,
        endPoint: .trailing
    )

    public var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(gradient)
                    .frame(height: trackHeight)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.ftBg, lineWidth: 1.5))
                    .frame(width: dotDiameter, height: dotDiameter)
                    .offset(x: geo.size.width * fraction - dotDiameter / 2)
            }
        }
        .frame(height: dotDiameter)
    }
}
```

- [ ] **Step 4: Delete GaugeProgressBar**

Find `GaugeProgressBar` in `SharedComponents.swift` and delete the entire struct. Then build to find all callsites:

```bash
cd ios/FastTrack
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep "error:" | head -30
```

For each callsite, replace `GaugeProgressBar(value: x, total: y)` with:
```swift
GradientProgressBar(value: x, range: 0...y, size: .compact)
```

- [ ] **Step 5: Run tests — expect pass**

```bash
cd ios/FastTrack
xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/GradientProgressBarTests CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|FAILED|PASSED"
```

Expected: all 5 tests PASSED.

- [ ] **Step 6: Commit**

```bash
cd ios/FastTrack
git add FastTrack/Views/Components/SharedComponents.swift FastTrackTests/GradientProgressBarTests.swift
git commit -m "feat(design): add GradientProgressBar, delete GaugeProgressBar"
```

---

## Task 4: Add StatusDot Component

**Files:**
- Modify: `FastTrack/Views/Components/SharedComponents.swift`
- Create: `FastTrackTests/StatusDotTests.swift`

- [ ] **Step 1: Write failing tests**

Create `FastTrackTests/StatusDotTests.swift`:

```swift
import XCTest
import SwiftUI
@testable import FastTrack

final class StatusDotTests: XCTestCase {

    func testBestLevelUsesGoldColor() {
        XCTAssertEqual(StatusLevel.best.color, Color.ftGold)
    }

    func testImprovingLevelUsesGreenColor() {
        XCTAssertEqual(StatusLevel.improving.color, Color.ftGreen)
    }

    func testNearBestLevelUsesAmberColor() {
        XCTAssertEqual(StatusLevel.nearBest.color, Color.ftAmber)
    }

    func testTypicalLevelUsesBlueColor() {
        XCTAssertEqual(StatusLevel.typical.color, Color.ftBlue)
    }

    func testStatusDotInstantiates() {
        // Verify StatusDot can be instantiated without crashing
        let dot = StatusDot(level: .best, label: "Personal Best")
        XCTAssertNotNil(dot)
    }
}
```

- [ ] **Step 2: Run — expect compile failure**

```bash
cd ios/FastTrack
xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/StatusDotTests CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|FAILED|PASSED"
```

Expected: compile error — `StatusDot` not defined.

- [ ] **Step 3: Add StatusDot to SharedComponents.swift**

```swift
/// A small filled circle with a label — used to add qualitative context to a metric or state.
public struct StatusDot: View {
    let level: StatusLevel
    let label: String
    var font: Font = .caption

    public var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(level.color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(font)
                .fontWeight(.semibold)
                .foregroundStyle(level.color)
        }
    }
}
```

- [ ] **Step 4: Run tests — expect pass**

```bash
cd ios/FastTrack
xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/StatusDotTests CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|FAILED|PASSED"
```

Expected: all 5 tests PASSED.

- [ ] **Step 5: Commit**

```bash
cd ios/FastTrack
git add FastTrack/Views/Components/SharedComponents.swift FastTrackTests/StatusDotTests.swift
git commit -m "feat(design): add StatusDot component"
```

---

## Task 5: Floating Pill Tab Bar

**Files:**
- Create: `FastTrack/Views/Components/FloatingTabBar.swift`
- Modify: `FastTrack/FastTrackApp.swift` (or `RootView.swift` — wherever the root `TabView` lives)

- [ ] **Step 1: Create FloatingTabBar.swift**

```swift
import SwiftUI

enum AppTab: Int, CaseIterable {
    case track, garage, social, profile

    var icon: String {
        switch self {
        case .track:   return "speedometer"
        case .garage:  return "car.2.fill"
        case .social:  return "trophy.fill"
        case .profile: return "person.fill"
        }
    }

    var label: String {
        switch self {
        case .track:   return "Track"
        case .garage:  return "Garage"
        case .social:  return "Social"
        case .profile: return "Profile"
        }
    }

    var accentColor: Color {
        switch self {
        case .track:   return .ftBlue
        case .garage:  return .ftAmber
        case .social:  return .ftGold
        case .profile: return .ftGreen
        }
    }
}

struct FloatingTabBar: View {
    @Binding var selectedTab: AppTab
    var isHidden: Bool = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(AppTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    if selectedTab == tab {
                        HStack(spacing: 5) {
                            Image(systemName: tab.icon)
                                .font(.system(size: 14, weight: .semibold))
                            Text(tab.label)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundStyle(tab.accentColor)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(tab.accentColor.opacity(0.20))
                        .clipShape(Capsule())
                    } else {
                        Image(systemName: tab.icon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.50))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.ultraThinMaterial)
        .overlay(
            Capsule()
                .stroke(Color.ftGlassCardStroke, lineWidth: 1)
        )
        .clipShape(Capsule())
        .offset(y: isHidden ? 100 : 0)
        .opacity(isHidden ? 0 : 1)
        .animation(.easeInOut(duration: 0.2), value: isHidden)
    }
}
```

- [ ] **Step 2: Wire FloatingTabBar into the root view**

Open the file containing the root `TabView` (likely `FastTrackApp.swift` or a `RootView.swift`). Find the `TabView` block. 

Add `@State private var selectedTab: AppTab = .track` at the top of the view struct.

Change the `TabView` selection binding to `$selectedTab.rawValue` (or switch `TabView` to use `AppTab` tags).

Hide the system tab bar with `.toolbar(.hidden, for: .tabBar)` on the `TabView`.

Add the `FloatingTabBar` as an overlay anchored to the bottom:

```swift
.overlay(alignment: .bottom) {
    FloatingTabBar(
        selectedTab: $selectedTab,
        isHidden: driveManager.isRecording
    )
    .padding(.bottom, 16)
}
```

Replace the `TabView` tag values with `AppTab` cases:
```swift
ContentView()
    .tag(AppTab.track)
GarageView()
    .tag(AppTab.garage)
SocialView()
    .tag(AppTab.social)
ProfileView()
    .tag(AppTab.profile)
```

- [ ] **Step 3: Build clean**

```bash
cd ios/FastTrack
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
cd ios/FastTrack
git add FastTrack/Views/Components/FloatingTabBar.swift FastTrack/FastTrackApp.swift
git commit -m "feat(design): add floating pill tab bar, hide system tab bar"
```

---

## Task 6: Open Arc Speedometer (SpeedHeroRing)

**Files:**
- Modify: `FastTrack/Views/ContentView.swift`

- [ ] **Step 1: Locate SpeedHeroRing in ContentView.swift**

Find the `SpeedHeroRing` private struct in `ContentView.swift`. It is a full circle (`Circle` stroke with `trim`). Note the current diameter (256pt) and how `speed` / `maxSpeed` are passed in.

- [ ] **Step 2: Replace SpeedHeroRing with open arc version**

Replace the entire `SpeedHeroRing` struct with:

```swift
private struct SpeedHeroRing: View {
    let speed: Double        // current speed in m/s
    let maxSpeed: Double     // upper bound of the speed range (m/s)
    let diameter: CGFloat

    private var fraction: Double {
        guard maxSpeed > 0 else { return 0 }
        return max(0, min(1, speed / maxSpeed))
    }

    // 240° arc: starts at 150° (bottom-left), sweeps clockwise to 30° (bottom-right)
    // In SwiftUI angles: start = 150°, end = 150° + 240° = 390° (= 30°)
    private let startAngle = Angle.degrees(150)
    private let endAngle   = Angle.degrees(390)

    private let trackGradient = AngularGradient(
        colors: [.ftGreen, .ftGold, .ftAmber, .ftRed],
        center: .center,
        startAngle: .degrees(150),
        endAngle: .degrees(390)
    )

    var body: some View {
        ZStack {
            // Track
            Circle()
                .trim(from: 0, to: 240.0/360.0)
                .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(150))
                .frame(width: diameter, height: diameter)

            // Value arc
            Circle()
                .trim(from: 0, to: (240.0/360.0) * fraction)
                .stroke(trackGradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(150))
                .frame(width: diameter, height: diameter)
                .animation(.linear(duration: 0.1), value: fraction)

            // Tick marks (5 evenly spaced along the 240° arc)
            ForEach(0..<5) { i in
                let angle = 150.0 + (240.0 / 4.0) * Double(i)
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1.5, height: 6)
                    .offset(y: -(diameter / 2) + 4)
                    .rotationEffect(.degrees(angle))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}
```

- [ ] **Step 3: Remove .activeGlow() from the ring callsite and delete the modifier**

Find where `SpeedHeroRing(...)` is used in `ContentView` body and remove `.activeGlow()` from it if present.

Then find the `ActiveGlowModifier` struct definition (search: `grep -rn "ActiveGlowModifier\|activeGlow" FastTrack/ --include="*.swift"`). If it is used only by `SpeedHeroRing`, delete the struct and the `View` extension method entirely. If it has other callsites, leave it but remove only the ring's usage.

- [ ] **Step 4: Build clean**

```bash
cd ios/FastTrack
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
cd ios/FastTrack
git add FastTrack/Views/ContentView.swift
git commit -m "feat(design): replace full-circle SpeedHeroRing with 240° open arc"
```

---

## Task 7: Apply Gradient Backgrounds to All Screens

**Files:**  
Modify all screen files listed in the file map. This task applies `ftBgGradient` to every screen.

- [ ] **Step 1: Apply background to Track screen (ContentView.swift)**

In `ContentView`, find the outermost `ZStack` or `VStack`. Apply:

```swift
.background(
    Group {
        if driveManager.isRecording {
            Color.ftBgGradientWarm.ignoresSafeArea()
        } else {
            Color.ftBgGradient.ignoresSafeArea()
        }
    }
)
```

Note: `Color.ftBgGradient` returns `some ShapeStyle` not `Color` — wrap in `AnyView` or use `.background { }` closure syntax if the compiler complains about the type:

```swift
.background(ignoresSafeAreaEdges: .all) {
    if driveManager.isRecording {
        Color.ftBgGradientWarm
    } else {
        Color.ftBgGradient
    }
}
```

- [ ] **Step 2: Apply background to remaining screens**

For each of these files, find the outermost container and add `.background(Color.ftBgGradient.ignoresSafeArea())` (or `.background { Color.ftBgGradient }` with `.ignoresSafeArea()`):

- `DriveDetailView.swift`
- `DriveHistoryView.swift`
- `GarageView.swift`
- `CarDetailView.swift` (all sub-views share the parent's background)
- `SocialView.swift`
- `ProfileView.swift`
- `PublicProfileView.swift`
- `PublicCarDetailView.swift`
- `DrivePerformanceDetailView.swift`
- `AchievementsView.swift`
- `NotificationsView.swift`
- `FindPeopleView.swift`
- `FollowersListView.swift`
- `SettingsView.swift`
- `ProfileSetupView.swift`
- `SignInView.swift`
- `FastTrackApp.swift` (SplashView inner container)

For `List`-based views, also add `.scrollContentBackground(.hidden)` on the `List` to let the gradient show through.

- [ ] **Step 3: Build clean**

```bash
cd ios/FastTrack
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
cd ios/FastTrack
git add -A
git commit -m "feat(design): apply gradient backgrounds to all screens"
```

---

## Task 8: Migrate ftCardBg/ftSectionBg Callsites to ftGlassCard

This task replaces every remaining hardcoded `Color.ftCardBg` and `Color.ftSectionBg` usage with the glass card tokens or removes them (for `listRowBackground` on `List`-based screens).

- [ ] **Step 1: Find all remaining ftCardBg usages**

```bash
cd ios/FastTrack
grep -rn "ftCardBg\|ftSectionBg" FastTrack/ --include="*.swift" | grep -v DesignSystem.swift
```

List all files and line numbers.

- [ ] **Step 2: Replace card background usages**

For each callsite:

- `Color.ftCardBg` as a card/cell background → replace with `.background(Color.ftGlassCardFill).overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.ftGlassCardStroke, lineWidth: 1))`
- `listRowBackground(Color.ftCardBg)` → replace with `listRowBackground(Color.ftGlassCardFill)`
- `Color.ftSectionBg` as a screen background → already handled in Task 7; if any remain, replace with `Color.ftBgGradient`
- `Color.ftSectionBg` as a card fill → replace with `Color.ftGlassCardFill`

**Special case — `DriveHistoryView.rowTint()` function:**

Find the `rowTint()` (or equivalent) function that applies solid background tints to PB rows. Replace the solid fill approach with an overlay on top of `ftGlassCardFill`:

```swift
// Replace the full rowBackground modifier:
.listRowBackground(
    ZStack {
        Color.ftGlassCardFill
        if drive.isPBTopSpeed {
            Color.ftGold.opacity(0.06)
        } else if drive.isPB060 {
            Color.ftAmber.opacity(0.06)
        }
    }
)
.overlay(
    RoundedRectangle(cornerRadius: Radius.xl)
        .stroke(
            drive.isPBTopSpeed ? Color.ftGold.opacity(0.18) :
            drive.isPB060      ? Color.ftAmber.opacity(0.18) :
                                 Color.ftGlassCardStroke,
            lineWidth: 1
        )
)
```

**Special case — `SocialView` filter chips:**

Find the filter chip `Capsule().fill(Color.ftCardBg)` and replace:

```swift
// inactive chip:
Capsule().fill(Color.ftGlassCardFill)
    .overlay(Capsule().stroke(Color.ftGlassCardStroke, lineWidth: 1))

// active chip (add accent tint overlay):
Capsule().fill(Color.ftGlassCardFill)
    .overlay(Capsule().fill(accentColor.opacity(0.15)))
    .overlay(Capsule().stroke(accentColor.opacity(0.3), lineWidth: 1))
```

**Special case — `SocialView` "your position" card:**

Replace `Color.ftBlue.opacity(0.12)` + `ftCardBg` fallback with:

```swift
.background(Color.ftGlassCardFill)
.overlay(Color.ftBlue.opacity(0.08))
.overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.ftBlue.opacity(0.20), lineWidth: 1))
```

**Special case — `DriveDetailMap` HUD overlays (scrubber panel, SpeechBubble fills):**

These are non-map UI elements on top of the map. Replace their `Color.ftCardBg` fills with `Color.ftGlassCardFill` + stroke.

- [ ] **Step 3: Update ToastView**

Find `ToastView` (in `SharedComponents.swift` or its own file). Replace:

```swift
// Old:
.background(Color.ftCardBg)
.overlay(RoundedRectangle(...).stroke(Color.ftSectionBg, ...))

// New:
.background(Color.ftGlassCardFill)
.overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.ftGlassCardStroke, lineWidth: 1))
```

- [ ] **Step 4: Update skeleton components**

Find `SkeletonBlock`, `LeaderboardSkeletonRow`, `StatCardSkeleton`. Replace:

```swift
// Old fill:
Color.ftCardBg   // or Color.ftSectionBg.opacity(0.5)

// New fill:
Color.white.opacity(0.06)
```

Shimmer highlight color (the animated overlay):
```swift
// Old:
Color(white: 1, opacity: 0.35)
// New:
Color.white.opacity(0.12)
```

- [ ] **Step 5: Update BadgePill non-PB styles**

Find `BadgePill` in `SharedComponents.swift`. For `.selected`, `.carChip`, `.you` styles, replace the solid fill with:

```swift
// background:
accentColor.opacity(0.15)
// border:
.overlay(Capsule().stroke(accentColor.opacity(0.30), lineWidth: 1))
```

Leave `.pb060` and `.pbTopSpeed` styles unchanged.

- [ ] **Step 6: Verify no remaining deprecated token usages (except DesignSystem.swift itself)**

```bash
cd ios/FastTrack
grep -rn "ftCardBg\|ftSectionBg" FastTrack/ --include="*.swift" | grep -v DesignSystem.swift
```

Expected: 0 results.

- [ ] **Step 7: Remove deprecated token declarations from DesignSystem.swift**

Delete the `@available(*, deprecated, ...)` `ftCardBg` and `ftSectionBg` declarations added in Task 1.

- [ ] **Step 8: Build clean**

```bash
cd ios/FastTrack
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED` with 0 errors, 0 warnings about deprecated tokens.

- [ ] **Step 9: Commit**

```bash
cd ios/FastTrack
git add -A
git commit -m "feat(design): migrate all ftCardBg/ftSectionBg callsites to glass card tokens"
```

---

## Task 9: Update FTGauge — Compact + Hero Variants

**Files:**
- Modify: `FastTrack/Views/Components/FTGauge.swift` (or wherever `FTGauge` is defined)

- [ ] **Step 1: Find FTGauge in the codebase**

```bash
cd ios/FastTrack
grep -rn "struct FTGauge\|enum.*FTGauge\|FTGaugeStyle" FastTrack/ --include="*.swift"
```

Open the file(s) returned.

- [ ] **Step 2: Update .compact variant**

Find the `.compact` rendering path. Make these changes:

1. Remove any explicit `Color.ftCardBg` background — `InstrumentCard` now handles it
2. Replace the hardcoded `LinearGradient` underline (the 3pt blue→amber bar) with:

```swift
GradientProgressBar(value: value, range: 0...maxValue, size: .compact)
    .padding(.top, 4)
```

3. Add micro-sparkline below the value number (above the progress bar), using Swift Charts:

```swift
if sparklineData.count >= 3 {
    Chart {
        ForEach(Array(sparklineData.enumerated()), id: \.offset) { index, val in
            LineMark(
                x: .value("Index", index),
                y: .value("Value", val)
            )
        }
    }
    .chartXAxis(.hidden)
    .chartYAxis(.hidden)
    .foregroundStyle(accentColor.opacity(0.70))
    .frame(height: 14)
}
```

`sparklineData` is a `[Double]` parameter passed into the gauge (last 10 drives' values). Add this parameter to `FTGauge` with a default of `[]`.

- [ ] **Step 3: Update .hero variant**

Find the `.hero` rendering path. The ring in `.hero` is currently a full circle. Apply the same 240° open arc pattern as `SpeedHeroRing`:

```swift
// Replace full-circle ring with:
ZStack {
    Circle()
        .trim(from: 0, to: 240.0/360.0)
        .stroke(Color.white.opacity(0.06),
                style: StrokeStyle(lineWidth: 8, lineCap: .round))
        .rotationEffect(.degrees(150))

    Circle()
        .trim(from: 0, to: (240.0/360.0) * fraction)
        .stroke(
            AngularGradient(
                colors: [.ftGreen, .ftGold, .ftAmber, .ftRed],
                center: .center,
                startAngle: .degrees(150),
                endAngle: .degrees(390)
            ),
            style: StrokeStyle(lineWidth: 8, lineCap: .round)
        )
        .rotationEffect(.degrees(150))
        .animation(.linear(duration: 0.15), value: fraction)
}
.frame(width: 96, height: 96)
```

Add a `GradientProgressBar(value: value, range: 0...maxValue, size: .hero)` below the ring number.

- [ ] **Step 4: Build clean**

```bash
cd ios/FastTrack
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 5: Commit**

```bash
cd ios/FastTrack
git add -A
git commit -m "feat(design): FTGauge compact→glass+sparkline+progress, hero→open arc"
```

---

## Task 10: Add StatusDot to Key Screens

Apply `StatusDot` to all callsites listed in the spec. This task covers the Track, Drive Detail, Drive History, Garage, Profile, and Social screens.

**Files:**
- Modify: `ContentView.swift`, `DriveDetailView.swift`, `DriveHistoryView.swift`, `GarageView.swift`, `ProfileView.swift`, `SocialView.swift`

- [ ] **Step 1: Track screen — GPS + recording state**

In `ContentView.swift`, find the GPS status capsule (currently a `Text` or `HStack` showing GPS quality). Replace with:

```swift
StatusDot(
    level: gpsStatusLevel(locationManager.authorizationStatus, accuracy: locationManager.accuracy),
    label: locationManager.gpsQualityLabel
)
.padding(.horizontal, 12)
.padding(.vertical, 6)
.background(Color.ftGlassCardFill)
.overlay(Capsule().stroke(Color.ftGlassCardStroke, lineWidth: 1))
.clipShape(Capsule())
```

Where `gpsStatusLevel` is a helper mapping GPS accuracy/status → `StatusLevel` (excellent → `.improving`, good → `.nearBest`, fair → `.typical`, poor/error → `.inactive`).

Find the recording state indicator and replace with:

```swift
StatusDot(
    level: driveManager.isRecording ? .nearBest : .typical,
    label: driveManager.isRecording ? "Recording" : "Idle"
)
```

- [ ] **Step 2: Drive Detail — PB header pill**

In `DriveDetailView.swift`, find the drive header area (date, drive name). Add below the drive name:

```swift
if drive.isTopSpeedPB {
    StatusDot(level: .best, label: "Top Speed PB")
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.ftGold.opacity(0.08))
        .overlay(Capsule().stroke(Color.ftGold.opacity(0.20), lineWidth: 1))
        .clipShape(Capsule())
} else if drive.is060PB {
    StatusDot(level: .nearBest, label: "0-60 PB")
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.ftAmber.opacity(0.08))
        .overlay(Capsule().stroke(Color.ftAmber.opacity(0.20), lineWidth: 1))
        .clipShape(Capsule())
}
```

- [ ] **Step 3: Drive History — top speed per row**

In `DriveHistoryView.swift`, find where top speed is displayed per row. Replace the bare `Text("\(speed) mph")` with:

```swift
StatusDot(
    level: drive.isTopSpeedPB ? .best : .typical,
    label: settings.formatSpeed(drive.maxSpeed)
)
```

- [ ] **Step 4: Garage — car card stats**

In `GarageView.swift`, find `GarageCarCard`'s stat display for Top Speed and Best 0-60. Replace the bare value text with `StatusDot`:

```swift
// Top Speed:
StatusDot(level: .best, label: settings.formatSpeed(stats.bestTopSpeed))

// Best 0-60:
StatusDot(level: .nearBest, label: stats.formatted060)
```

- [ ] **Step 5: Profile — active car indicator**

In `ProfileView.swift`, find the active car display in the header. Replace with:

```swift
StatusDot(level: .typical, label: activeCarName)
```

- [ ] **Step 6: Social — leaderboard metric values**

In `SocialView.swift`, find each leaderboard row's metric value. Replace the bare `Text` with:

```swift
StatusDot(
    level: row.rank == 1 ? .best : row.rank <= 3 ? .improving : .typical,
    label: formattedMetric
)
```

- [ ] **Step 7: Build clean**

```bash
cd ios/FastTrack
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 8: Commit**

```bash
cd ios/FastTrack
git add -A
git commit -m "feat(design): add StatusDot to Track, Drive Detail, Drive History, Garage, Profile, Social"
```

---

## Task 11: Add Micro-Sparklines to Track Gauge Strip

**Files:**
- Modify: `FastTrack/Views/ContentView.swift`

The `TrackMetricCard` private struct needs sparkline data. The Track screen has access to recent drives via `driveManager` or a `@FetchRequest`.

- [ ] **Step 1: Pass sparkline data to TrackMetricCard**

In `ContentView.swift`, add a `@FetchRequest` for the last 10 drives if not already present:

```swift
@FetchRequest(
    sortDescriptors: [NSSortDescriptor(keyPath: \Drive.startTime, ascending: false)],
    predicate: NSPredicate(format: "userID == %@", authManager.currentUser?.id ?? ""),
    animation: .none
)
private var recentDrives: FetchedResults<Drive>
```

Update `TrackMetricCard` to accept `sparklineData: [Double]`:

```swift
private struct TrackMetricCard: View {
    let label: String
    let value: String
    let unit: String
    let accentColor: Color
    let progressValue: Double
    let progressMax: Double
    let sparklineData: [Double]   // ← new

    var body: some View {
        InstrumentCard(padding: Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(Color.secondary)
                    .textCase(.uppercase)
                    .tracking(0.8)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.system(size: 20, weight: .bold).monospacedDigit())
                        .foregroundStyle(accentColor)
                    Text(unit)
                        .font(.system(size: 8))
                        .foregroundStyle(Color.secondary)
                }
                if sparklineData.count >= 3 {
                    Chart {
                        ForEach(Array(sparklineData.enumerated()), id: \.offset) { i, v in
                            LineMark(x: .value("i", i), y: .value("v", v))
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .foregroundStyle(accentColor.opacity(0.70))
                    .frame(height: 14)
                }
                GradientProgressBar(value: progressValue, range: 0...progressMax, size: .compact)
            }
        }
    }
}
```

Pass the appropriate sparkline arrays at the callsite, e.g. for max speed card:

```swift
TrackMetricCard(
    label: "Max",
    value: ...,
    unit: "mph",
    accentColor: .ftGold,
    progressValue: currentMaxSpeed,
    progressMax: 160,
    sparklineData: recentDrives.prefix(10).map(\.maxSpeed)
)
```

- [ ] **Step 2: Build clean**

```bash
cd ios/FastTrack
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 3: Commit**

```bash
cd ios/FastTrack
git add FastTrack/Views/ContentView.swift
git commit -m "feat(design): add micro-sparklines and GradientProgressBar to Track gauge strip"
```

---

## Task 12: Public Profile — Realign with GarageView

**Files:**
- Modify: `FastTrack/Views/PublicProfileView.swift`
- Delete: `FastTrack/Views/PublicGarageCard.swift` (or wherever `PublicGarageCard` is defined)

- [ ] **Step 1: Rewrite PublicProfileView layout**

Replace the `List`-based layout with `ScrollView + VStack` matching `GarageView`'s pattern. The new structure:

```swift
NavigationStack {
    ScrollView {
        VStack(alignment: .leading, spacing: Spacing.lg) {

            // Header: @username + identity (keep name, country, avatar, followers)
            narrowHeader  // keep existing narrowHeader — no data stripped here

            // Aggregate stats grid (4 cells)
            aggregateStatsSection

            // Garage grid
            if !publicCars.isEmpty {
                garageGridSection
            }
        }
        .padding(.horizontal, Spacing.md)
        .padding(.vertical, Spacing.md)
    }
    .background { Color.ftBgGradient.ignoresSafeArea() }
    .navigationTitle("@\(profile.username)")
    .navigationBarTitleDisplayMode(.inline)
}
```

- [ ] **Step 2: Build aggregate stats section**

Replace the 3-row `Section("Stats")` list with a `LazyVGrid` of 4 `InstrumentStatCell` cells:

```swift
private var aggregateStatsSection: some View {
    LazyVGrid(columns: [
        GridItem(.flexible()), GridItem(.flexible()),
        GridItem(.flexible()), GridItem(.flexible())
    ], spacing: Spacing.sm) {
        InstrumentStatCell(
            icon: "flag.fill", color: .ftGreen,
            label: "Drives",
            value: "\(profile.driveCount ?? 0)"
        )
        InstrumentStatCell(
            icon: "map.fill", color: .ftBlue,
            label: "Distance",
            value: settings.formatDistance(profile.totalDistance ?? 0)
        )
        InstrumentStatCell(
            icon: "bolt.fill", color: .ftGold,
            label: "Top Speed",
            value: settings.formatSpeed(profile.topSpeed ?? 0)
        )
        InstrumentStatCell(
            icon: "timer", color: .ftAmber,
            label: "Best 0-60",
            value: profile.best060Time.map { String(format: "%.2fs", $0) } ?? "N/A"
        )
    }
}
```

- [ ] **Step 3: Build garage grid section matching GarageView**

Replace `Section("Garage")` + `PublicGarageCard` with:

```swift
private var garageGridSection: some View {
    LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: Spacing.md) {
        ForEach(publicCars) { car in
            NavigationLink(destination: PublicCarDetailView(car: car, username: profile.username)) {
                publicCarCard(car: car)
            }
            .buttonStyle(.plain)
        }
    }
}

private func publicCarCard(car: UserCar) -> some View {
    let stats = carStats(for: car)
    return InstrumentCard(padding: 0) {
        VStack(alignment: .leading, spacing: 0) {
            CarPhotoView(url: car.photoURL)
                .frame(height: 160)
                .clipped()

            VStack(alignment: .leading, spacing: Spacing.xs) {
                Text(car.nickname ?? car.shortDisplay)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Text(car.displayString)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                StatsGrid(columns: 2) {
                    StatMini(label: "Drives",     value: "\(stats?.totalDrives ?? 0)")
                    StatMini(label: settings.distanceUnit, value: settings.formatDistance(stats?.totalDistance ?? 0))
                    StatMini(label: "Top Speed",  value: settings.formatSpeed(stats?.bestTopSpeed ?? 0))
                    StatMini(label: "0-60",       value: stats.map { String(format: "%.2fs", $0.bestZeroToSixty ?? 0) } ?? "—")
                }
            }
            .padding(Spacing.sm)
        }
    }
}
```

- [ ] **Step 4: Delete PublicGarageCard**

Find and delete the `PublicGarageCard` struct (it may be in `PublicProfileView.swift` itself or a separate file). If in a separate file, delete that file.

- [ ] **Step 5: Build clean**

```bash
cd ios/FastTrack
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
cd ios/FastTrack
git add -A
git commit -m "feat(design): realign PublicProfileView with GarageView layout, delete PublicGarageCard"
```

---

## Task 13: Achievements Redesign — AchievementBadgeCard Component

**Files:**
- Create: `FastTrack/Views/Components/AchievementBadgeCard.swift`
- Create: `FastTrack/Views/Components/AchievementChip.swift`

- [ ] **Step 1: Create AchievementBadgeCard.swift**

```swift
import SwiftUI

/// Compact 3-column badge card with three visual states: unlocked, locked-with-progress, unknown.
struct AchievementBadgeCard: View {
    let achievement: Achievement

    var body: some View {
        switch badgeState {
        case .unlocked:   unlockedCard
        case .locked:     lockedCard
        case .unknown:    unknownCard
        }
    }

    private enum BadgeState { case unlocked, locked, unknown }

    private var badgeState: BadgeState {
        if achievement.isUnlocked { return .unlocked }
        if achievement.progressFraction >= 0.8 || achievement.progressFraction > 0 {
            return .locked
        }
        return .unknown
    }

    private var accentColor: Color { achievement.accentColor }

    private var unlockedCard: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(accentColor.opacity(0.20))
                .frame(width: 32, height: 32)
                .overlay(
                    Image(systemName: achievement.iconName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(accentColor)
                )
            Text(achievement.title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(accentColor)
                .multilineTextAlignment(.center)
                .lineLimit(2)
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(accentColor.opacity(0.08))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(accentColor.opacity(0.25), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }

    private var lockedCard: some View {
        VStack(spacing: 6) {
            ZStack {
                RoundedRectangle(cornerRadius: Radius.md)
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 32, height: 32)
                // Mini ring progress
                Circle()
                    .trim(from: 0, to: achievement.progressFraction)
                    .stroke(accentColor.opacity(0.70), style: StrokeStyle(lineWidth: 2, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 32, height: 32)
                Image(systemName: "lock.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(Color(white: 0.35))
            }
            Text(achievement.title)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(white: 0.27))
                .multilineTextAlignment(.center)
                .lineLimit(2)
            Text("\(Int(achievement.progressFraction * 100))%")
                .font(.system(size: 8))
                .foregroundStyle(Color(white: 0.20))
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(Color.ftGlassCardFill)
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.ftGlassCardStroke, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }

    private var unknownCard: some View {
        VStack(spacing: 6) {
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.white.opacity(0.04))
                .frame(width: 32, height: 32)
            Text("???")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(Color(white: 0.20))
        }
        .padding(Spacing.sm)
        .frame(maxWidth: .infinity)
        .background(Color.ftGlassCardFill.opacity(0.6))
        .overlay(RoundedRectangle(cornerRadius: Radius.xl).stroke(Color.ftGlassCardStroke.opacity(0.5), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }
}
```

- [ ] **Step 2: Create AchievementChip.swift**

```swift
import SwiftUI

/// Small pill chip for achievement surfaces in Profile and Car Detail.
struct AchievementChip: View {
    let achievement: Achievement

    var body: some View {
        Text(achievement.title)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(achievement.accentColor)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(achievement.accentColor.opacity(0.10))
            .overlay(Capsule().stroke(achievement.accentColor.opacity(0.25), lineWidth: 1))
            .clipShape(Capsule())
    }
}
```

- [ ] **Step 3: Build clean**

```bash
cd ios/FastTrack
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
cd ios/FastTrack
git add FastTrack/Views/Components/AchievementBadgeCard.swift FastTrack/Views/Components/AchievementChip.swift
git commit -m "feat(achievements): add AchievementBadgeCard and AchievementChip components"
```

---

## Task 14: Achievements Redesign — AchievementsView Grid

**Files:**
- Modify: `FastTrack/Views/AchievementsView.swift`

- [ ] **Step 1: Replace the 2-column grid with 3-column AchievementBadgeCard grid**

In `AchievementsView.swift`, find the `LazyVGrid` rendering achievement cards. Replace:

```swift
// Old: 2-column grid of old AchievementCard
LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], ...)

// New: 3-column grid of AchievementBadgeCard
LazyVGrid(
    columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
    spacing: Spacing.sm
) {
    ForEach(filteredAchievements) { achievement in
        AchievementBadgeCard(achievement: achievement)
            .onTapGesture { selectedAchievement = achievement }
    }
}
```

- [ ] **Step 2: Update filter chips to glass style**

Find the category filter chip row. Replace each chip's background:

```swift
// Active chip:
.background(accentColor.opacity(0.15))
.overlay(Capsule().stroke(accentColor.opacity(0.30), lineWidth: 1))

// Inactive chip:
.background(Color.ftGlassCardFill)
.overlay(Capsule().stroke(Color.ftGlassCardStroke, lineWidth: 1))
```

- [ ] **Step 3: Update "Show unlocked only" toggle row**

Wrap the toggle in `InstrumentCard`:

```swift
InstrumentCard {
    Toggle("Show unlocked only", isOn: $showUnlockedOnly)
        .tint(.ftBlue)
}
```

- [ ] **Step 4: Update AchievementDetailView sheet**

In the detail sheet (`.sheet(item: $selectedAchievement)`), update the background:

```swift
.presentationBackground(Color.ftBg)
```

Replace the large icon container with `AchievementBadgeCard`-consistent styling (64pt icon container in accent color at 20% opacity background). Add `GradientProgressBar` for locked achievements:

```swift
if !achievement.isUnlocked {
    GradientProgressBar(value: achievement.progressFraction, range: 0...1, size: .hero)
        .padding(.horizontal, Spacing.lg)
}
```

- [ ] **Step 5: Build clean**

```bash
cd ios/FastTrack
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
cd ios/FastTrack
git add FastTrack/Views/AchievementsView.swift
git commit -m "feat(achievements): redesign AchievementsView to 3-col badge grid"
```

---

## Task 15: Achievements — Contextual Surfaces

**Files:**
- Modify: `FastTrack/Views/ProfileView.swift`
- Modify: `FastTrack/Views/CarDetailView/CarDetailDrivesList.swift`
- Modify: `FastTrack/Views/DriveDetailView/DriveDetailView.swift`
- Delete: `FastTrack/Views/Components/RecentAchievementsStrip.swift`

- [ ] **Step 1: Replace RecentAchievementsStrip in ProfileView**

In `ProfileView.swift`, find `RecentAchievementsStrip(...)` and replace with:

```swift
// Achievements section
VStack(alignment: .leading, spacing: Spacing.sm) {
    HStack {
        Text("Achievements")
            .font(.headline)
        Spacer()
        NavigationLink("See all", destination: AchievementsView())
            .font(.subheadline)
            .foregroundStyle(.ftBlue)
    }

    let unlocked = achievements.filter(\.isUnlocked)
    let total = achievements.count

    if total > 0 {
        HStack {
            Text("\(unlocked.count) / \(total) unlocked")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        GradientProgressBar(
            value: Double(unlocked.count),
            range: 0...Double(total),
            size: .compact
        )
    }

    if unlocked.isEmpty {
        Text("Start driving to earn achievements")
            .font(.caption)
            .foregroundStyle(.secondary)
    } else {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Spacing.sm) {
                ForEach(unlocked.prefix(5)) { achievement in
                    AchievementChip(achievement: achievement)
                }
            }
            .padding(.horizontal, 1)
        }
    }
}
```

- [ ] **Step 2: Delete RecentAchievementsStrip.swift**

Delete the file `FastTrack/Views/Components/RecentAchievementsStrip.swift` (or remove the struct from `SharedComponents.swift` if inline). Also delete `RecentAchievementCard` if it's defined alongside it.

- [ ] **Step 3: Add "With This Car" achievements section in CarDetailDrivesList**

In `CarDetailDrivesList.swift`, find the existing `perCarAchievementsSection` and replace with:

```swift
private var perCarAchievementsSection: some View {
    let carAchievements = achievements.filter { $0.carID == car.id && $0.isUnlocked }
    guard !carAchievements.isEmpty else { return AnyView(EmptyView()) }

    return AnyView(
        VStack(alignment: .leading, spacing: Spacing.sm) {
            HStack {
                Text("Achievements")
                    .font(.headline)
                Spacer()
                NavigationLink("See all", destination: AchievementsView(filterCarID: car.id))
                    .font(.subheadline)
                    .foregroundStyle(.ftBlue)
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Spacing.sm) {
                    ForEach(carAchievements) { achievement in
                        AchievementChip(achievement: achievement)
                    }
                }
                .padding(.horizontal, 1)
            }
        }
    )
}
```

- [ ] **Step 4: Add "Earned This Drive" section in DriveDetailView**

In `DriveDetailView.swift`, after the stats grid section, add:

```swift
if !drive.unlockedAchievements.isEmpty {
    VStack(alignment: .leading, spacing: Spacing.sm) {
        Text("Earned This Drive")
            .font(.headline)
        ForEach(drive.unlockedAchievements) { achievement in
            InstrumentCard {
                HStack(spacing: Spacing.md) {
                    RoundedRectangle(cornerRadius: Radius.md)
                        .fill(achievement.accentColor.opacity(0.15))
                        .frame(width: 32, height: 32)
                        .overlay(
                            Image(systemName: achievement.iconName)
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(achievement.accentColor)
                        )
                    VStack(alignment: .leading, spacing: 2) {
                        Text(achievement.title)
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundStyle(achievement.accentColor)
                        Text("Unlocked on this drive")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }
            .background(achievement.accentColor.opacity(0.08))
        }
    }
}
```

Note: `drive.unlockedAchievements` needs to be a computed property or fetched relationship. If `Drive` doesn't have this relationship, add a `@FetchRequest` filtered by `sourcedriveID == drive.id` in `DriveDetailView`.

- [ ] **Step 5: Build clean**

```bash
cd ios/FastTrack
xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" -configuration Debug \
  CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
cd ios/FastTrack
git add -A
git commit -m "feat(achievements): contextual surfaces in Profile, Car Detail, Drive Detail"
```

---

## Task 16: Final Build + Full Test Suite

- [ ] **Step 1: Run the full iOS test suite**

```bash
cd ios/FastTrack
cp FastTrack/Secrets.swift.template FastTrack/Secrets.swift
xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO 2>&1 | tail -30
```

Known pre-existing flaky test classes (do NOT treat as regressions — verify on main before filing):
`DriveDeleteTests`, `DriveManagerErrorSurfaceTests`, `CarHeroPhotoEditorSheetTests`, `ProfileRedesignTests`, `CarDetailGaugeProgressWiringTests`, `CurrentDriveDedupeTests`, `DriveManagerHeadingTests`, `ForceUnwrapAuditTests`

- [ ] **Step 2: Verify no new failures introduced**

Compare the failing test list against the known flaky list above. Any failure NOT in that list is a regression — fix it before proceeding.

- [ ] **Step 3: Remove ftCardBg and ftSectionBg tokens entirely from DesignSystem.swift**

Confirm no remaining non-deprecated usages:

```bash
cd ios/FastTrack
grep -rn "ftCardBg\|ftSectionBg" FastTrack/ --include="*.swift" | grep -v "deprecated\|DesignSystem"
```

Expected: 0 results. Then delete the deprecated declarations from `DesignSystem.swift`.

- [ ] **Step 4: Final commit**

```bash
cd ios/FastTrack
git add -A
git commit -m "chore(design): remove retired ftCardBg/ftSectionBg tokens, full suite passes"
```
