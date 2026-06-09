# Plan: Phase 2 — Merge Analytics into Garage

**Date:** 2026-06-08
**Status:** Ready for implementation
**Branch:** `feat/garage-hub-analytics-merge`
**Worktree:** `.worktrees/garage-hub`
**Base:** Latest `main` (after Phase 1 has landed)
**Conventional commits:** Required (feat, fix, refactor)

This is the structural change: the Analytics tab becomes the Garage tab, per-car analytics move into CarDetailView, cross-car aggregates move to GarageView, and the full Analytics chart is deprecated.

**Key decisions already made:**
- Driving Score is dropped from all-cars summary (driving style is per-car in CarDetailView)
- Period comparison is fixed "vs last month" — no time-frame picker
- 3 mini sparklines per car: max speed, distance, smoothness
- The full performance chart (AnalyticsView with metric picker) is deleted, not preserved anywhere

---

## 2.1 Replace Analytics tab with Garage tab

**Goal:** The tab bar changes from Track/Social/History/Analytics/Profile to Track/Social/History/Garage/Profile. The `GarageView` replaces `AnalyticsView` as tab 3.

**Commit:** `refactor(ios): replace Analytics tab with Garage tab`

### What to change

**File:** `ios/FastTrack/FastTrack/FastTrackApp.swift`

1. In the `TabView`, replace:
   ```swift
   AnalyticsView()
       .id(tabResetIDs[3])
       .tabItem { Label("Analytics", systemImage: "chart.line.uptrend.xyaxis") }.tag(3)
   ```
   with:
   ```swift
   GarageView()
       .id(tabResetIDs[3])
       .tabItem { Label("Garage", systemImage: "car.2.fill") }.tag(3)
   ```

2. Import is not needed because both `AnalyticsView` and `GarageView` are in the same module.

**File:** `ios/FastTrack/FastTrack/AppStoreScreenshotMode.swift`

1. Replace the `.analytics` case:
   ```swift
   case .analytics:
       GarageView()  // was AnalyticsView()
   ```
   (The enum case name `.analytics` can be renamed to `.garage` for clarity, but this is optional — the `Screen` enum is only used for screenshot mode and doesn't affect production.)

2. If renaming the enum case, also update the `Screen.allScreens` array and the `Screen.current` parser.

### Verification

- Build succeeds
- Tab bar shows Track, Social, History, Garage, Profile
- Tapping the Garage tab shows GarageView with the car grid
- Tab switching still resets navigation state on non-Track, non-Social tabs

---

## 2.2 Add all-cars summary and recent drives to GarageView

**Goal:** GarageView currently shows only a car grid. Add a summary strip above it showing totals across all cars (total drives, total distance, top speed across garage, best 0-60 across garage), and a "Recent Drives" section below the grid showing the last 5 drives across all cars.

**Commit:** `feat(ios): add all-cars summary and recent drives to GarageView`

### What to change

**File:** `ios/FastTrack/FastTrack/Views/GarageView.swift`

1. Add `@EnvironmentObject var driveManager: DriveManager` (it already has `@ObservedObject private var settings = AppSettings.shared`).

2. Add `@StateObject private var carStatsManager = CarStatsManager.shared` (already present).

3. Create a computed property for the all-cars summary data:
   ```swift
   private var allCarsStats: (totalDrives: Int, totalDistance: Double, topSpeed: Double, best060: Double?) {
       let allStats = carStatsManager.getAllStats()
       let totalDrives = allStats.reduce(0) { $0 + $1.totalDrives }
       let totalDistance = allStats.reduce(0.0) { $0 + $1.totalDistance }
       let topSpeed = allStats.map(\.bestTopSpeed).max() ?? 0
       let best060 = allStats.compactMap(\.bestZeroToSixty).min()
       return (totalDrives, totalDistance, topSpeed, best060)
   }
   ```

4. Add a summary section above the car grid (between the `VStack(alignment: .leading)` opening and the `if cars.isEmpty` check):
   ```swift
   allCarsSummary
   ```

5. The `allCarsSummary` view should be a `LazyVGrid` with 2 columns using `InstrumentStatCell`:
   ```swift
   private var allCarsSummary: some View {
       LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
           InstrumentStatCell(
               icon: "flag.fill", iconColor: .green,
               label: "Total Drives",
               value: "\(allCarsStats.totalDrives)",
               unit: ""
           )
           InstrumentStatCell(
               icon: "map.fill", iconColor: .blue,
               label: "Total Distance",
               value: String(format: "%.1f", settings.distanceValue(allCarsStats.totalDistance)),
               unit: settings.distanceUnit
           )
           InstrumentStatCell(
               icon: "bolt.fill", iconColor: .yellow,
               label: "Top Speed",
               value: String(format: "%.0f", settings.speedValue(allCarsStats.topSpeed)),
               unit: settings.speedUnit
           )
           InstrumentStatCell(
               icon: "timer", iconColor: .orange,
               label: "Best 0-60",
               value: allCarsStats.best060.map { String(format: "%.2f", $0) } ?? "—",
               unit: allCarsStats.best060 != nil ? "sec" : ""
           )
       }
   }
   ```
   Note: `InstrumentStatCell` is defined in `SharedComponents.swift` and is already used in ProfileView and other views.

6. Add a "Recent Drives" section below the car grid (before the end of the `VStack`). Show last 5 drives sorted by `startTime` descending. Each drive row shows: date, car name badge (if car is in garage), max speed, distance, duration. Reuse the existing `DriveRowView` from `DriveHistoryView.swift`.

   ```swift
   private var recentDrivesSection: some View {
       VStack(alignment: .leading, spacing: 12) {
           let recent = driveManager.drives
               .sorted { $0.startTime > $1.startTime }
               .prefix(5)

           if !recent.isEmpty {
               SectionHeader(title: "Recent Drives")
               ForEach(Array(recent)) { drive in
                   NavigationLink {
                       DriveDetailView(drive: drive)
                   } label: {
                       DriveRowView(drive: drive)
                   }
                   .buttonStyle(.plain)
               }
           }
       }
   }
   ```

   `SectionHeader` is already used in `CarDetailView`. If it's `private`, check — it may need to be made `internal` or a similar simple header can be inlined.

7. Wire `driveManager` through the environment. Check that `GarageView` is presented in contexts where `DriveManager` is available as an EnvironmentObject. In `FastTrackApp.swift`, `driveManager` is already injected as an EnvironmentObject on `RootView`, so any view in the tab hierarchy can use `@EnvironmentObject var driveManager: DriveManager`.

8. Add the recent drives section to the body after the car grid:
   ```swift
   } else {
       LazyVGrid(columns: columns, spacing: 12) {
           ForEach(cars) { car in ... }
       }
   }
   recentDrivesSection  // ADD THIS
   ```

### What NOT to change

- Don't modify `DriveHistoryView` or `DriveRowView`
- Don't add the driving score to the summary (explicitly excluded)
- Don't add a time-frame picker — the summary is always all-time
- Don't change the `GarageCarCard` layout or the NavigationLink to CarDetailView

### Verification

- Build succeeds
- GarageView shows 4 stat cells above the car grid (Total Drives, Total Distance, Top Speed, Best 0-60)
- Stats reflect data across all cars in the garage
- "Recent Drives" section appears below the car grid when drives exist
- Tapping a recent drive pushes DriveDetailView
- Empty garage state still works correctly

---

## 2.3 Add per-car breakdown, trends, and drive history to CarDetailView

**Goal:** CarDetailView currently shows hero, PB gauges, sparkline, driving style, stats grid, and achievements. Add: performance breakdown cards (0-60, cornering, smoothness, consistency) with StatInfo, a "vs Last Month" comparison, 3 mini trend sparklines, and last 5 drives for this car.

**Commit:** `feat(ios): add per-car breakdown, trends, and drive history to CarDetailView`

### What to change

**File:** `ios/FastTrack/FastTrack/Models/CarDetailData.swift`

Add these fields to `CarDetailData`:
```swift
/// Smoothness score for this car (0-100).
let smoothnessScore: Double
/// Consistency score for this car (0-100).
let consistencyScore: Double
/// Cornering (peak lateral G) for this car.
let peakLateralG: Double
/// Best 0-60 time in seconds for this car (nil if never reached 60).
let bestZeroToSixtyTime: Double?
/// Drives for this car, sorted by startTime descending, capped at 5.
let recentDrives: [Drive]
/// Distance per drive trend points (last N drives, oldest first).
let distanceTrendPoints: [Double]
/// Smoothness per drive trend points (last N drives, oldest first).
let smoothnessTrendPoints: [Double]
/// Avg max speed for the previous period, nil if no prior data.
let prevPeriodAvgMaxSpeed: Double?
```

**File:** `ios/FastTrack/FastTrack/Models/CarDetailData+Derive.swift`

Extend `derive()` to compute the new fields:

1. `smoothnessScore`: `CarStatsManager.calculateSmoothnessScore(for:)` using this car's drives, or fall back to `stats.smoothnessScore`

2. `consistencyScore`: Same formula as `AnalyticsData.consistency` but scoped to this car's drives:
   ```swift
   let speeds = carDrives.map(\.maxSpeed)
   let mean = speeds.reduce(0, +) / Double(max(1, speeds.count))
   let variance = speeds.map { pow($0 - mean, 2) }.reduce(0, +) / Double(max(1, speeds.count))
   let cv = mean > 0 ? sqrt(variance) / mean : 0
   let consistency = max(0, min(100, 100 - cv * 150))
   ```

3. `peakLateralG`: `stats.bestLateralG` or `carDrives.map(\.peakGForce).max() ?? 0`

4. `bestZeroToSixtyTime`: Already derived as `bestZeroToSixty` — exposing the raw time separately for the breakdown card

5. `recentDrives`: `carDrives.sorted { $0.startTime > $1.startTime }.prefix(5).map { $0 }`

6. `distanceTrendPoints`: `recent.map { settings.distanceValue($0.distance) }` — but `settings` isn't available in `derive()`. Instead, store raw `m/s` values and let the view convert. Actually, store raw distance in meters and convert in the view.

7. `smoothnessTrendPoints`: `recent.map { AnalyticsData.smoothnessScore(for: $0) }`

8. `prevPeriodAvgMaxSpeed`: Filter drives from the previous equivalent period (e.g., if showing last month, the month before that). Compute avg max speed for those drives. Nil if no prior drives.

The view layer will do unit conversion.

**File:** `ios/FastTrack/FastTrack/Views/CarDetailView.swift`

Add these sections between existing sections. The new body order:

```swift
ScrollView {
    VStack(alignment: .leading, spacing: 16) {
        hero
        pbGauges
        performanceBreakdown     // NEW
        periodComparison         // NEW
        trendSparklines          // NEW
        sparklineSection         // EXISTING (max speed chart)
        drivingStyleRow          // EXISTING
        statsGrid                // EXISTING
        perCarAchievementsSection // EXISTING
        recentDrivesSection      // NEW
        Spacer(minLength: 16)
    }
}
```

**1. performanceBreakdown** — Reuse `PerformanceBreakdownCard` from AnalyticsView (it now has the `info:` parameter from Phase 1). Render 4 cards:

```swift
private var performanceBreakdown: some View {
    VStack(alignment: .leading, spacing: 15) {
        Text("Performance")
            .font(.headline)
        
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            PerformanceBreakdownCard(
                title: "Best 0-60",
                value: data?.bestZeroToSixty.map { String(format: "%.1fs", $0) } ?? "N/A",
                category: zeroToSixtyCategory,
                icon: "bolt.fill",
                color: .red,
                info: StatInfo.zeroToSixty
            )
            PerformanceBreakdownCard(
                title: "Cornering",
                value: String(format: "%.2fG", data?.peakLateralG ?? 0),
                category: corneringCategory,
                icon: "arrow.triangle.turn.up.right.circle.fill",
                color: .purple,
                info: StatInfo.cornering
            )
            PerformanceBreakdownCard(
                title: "Driving Style",
                value: String(format: "%.0f%%", data?.smoothnessScore ?? 0),
                category: data?.drivingStyle.title ?? "Unknown",
                icon: "waveform.path",
                color: .cyan,
                info: StatInfo.smoothness
            )
            PerformanceBreakdownCard(
                title: "Consistency",
                value: String(format: "%.0f%%", data?.consistencyScore ?? 0),
                category: consistencyCategory,
                icon: "target",
                color: .mint,
                info: StatInfo.consistency
            )
        }
    }
}
```

Category helpers (derived from the raw values):
```swift
private var zeroToSixtyCategory: String {
    guard let time = data?.bestZeroToSixty else { return "N/A" }
    switch time {
    case 0..<3.0: return "Hypercar"
    case 3.0..<4.0: return "Supercar"
    case 4.0..<6.0: return "Sports Car"
    default: return "Quick"
    }
}

private var corneringCategory: String {
    switch data?.peakLateralG ?? 0 {
    case 0.8...: return "Race Driver"
    case 0.6..<0.8: return "Enthusiast"
    default: return "Spirited"
    }
}

private var consistencyCategory: String {
    switch data?.consistencyScore ?? 0 {
    case 90...: return "Exceptional"
    case 80..<90: return "Excellent"
    case 70..<80: return "Good"
    default: return "Average"
    }
}
```

**2. periodComparison** — "vs Last Month" card scoped to this car:

```swift
private var periodComparison: some View {
    let currentAvg = data.map { AnalyticsData.avgMaxSpeed(for: drives(of: $0.carId, in: .lastMonth)) }
    let prevAvg = data.map { AnalyticsData.avgMaxSpeed(for: drives(of: $0.carId, in: .previousMonth)) }
    
    let (valueText, trend): (String, TrendDirection?) = {
        guard let cur = currentAvg, let prev = prevAvg, prev > 0 else {
            return ("—", nil)
        }
        let delta = (cur - prev) * settings.speedFactor
        let sign = delta >= 0 ? "+" : ""
        let t: TrendDirection = delta > 0.5 ? .up : (delta < -0.5 ? .down : .neutral)
        return (String(format: "%@%.1f %@", sign, delta, settings.speedUnit), t)
    }()
    
    return AnalyticsCard(
        title: "vs Last Month",
        value: valueText,
        icon: "arrow.up.arrow.down",
        iconColor: .purple,
        trend: trend,
        info: StatInfo.periodComparison
    )
}
```

Helper to filter drives by time period for this car:
```swift
private func drives(of carId: String, in period: TimePeriod) -> [Drive] {
    let now = Date()
    let start: Date
    switch period {
    case .lastMonth:
        start = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
    case .previousMonth:
        let lastMonthStart = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        start = Calendar.current.date(byAdding: .month, value: -1, to: lastMonthStart) ?? lastMonthStart
        return driveManager.drives.filter { $0.carId == carId && $0.startTime >= start && $0.startTime < lastMonthStart }
    }
    return driveManager.drives.filter { $0.carId == carId && $0.startTime >= start }
}

private enum TimePeriod {
    case lastMonth
    case previousMonth
}
```

Note: `TrendDirection` and `AnalyticsCard` must still be available. Since this commit comes before Phase 2.4 (which deletes AnalyticsView), they're still in `AnalyticsModels.swift` and `AnalyticsView.swift` at this point.

**3. trendSparklines** — 3 small horizontal sparkline cards:

Each card is an `InstrumentCard` containing:
- A header row with icon + title + current value
- A small sparkline (using Charts framework, `if #available(iOS 16.0, *)`)

```swift
private var trendSparklines: some View {
    VStack(alignment: .leading, spacing: 12) {
        Text("Trends")
            .font(.headline)
        
        if #available(iOS 16.0, *) {
            LazyVGrid(columns: [GridItem(.flexible())], spacing: 10) {
                sparklineCard(
                    title: "Max Speed",
                    values: data?.sparklinePoints ?? [],
                    unit: settings.speedUnit,
                    formatValue: { String(format: "%.0f", settings.speedValue($0)) }
                )
                sparklineCard(
                    title: "Distance",
                    values: data?.distanceTrendPoints ?? [],
                    unit: settings.distanceUnit,
                    formatValue: { String(format: "%.1f", settings.distanceValue($0)) }
                )
                sparklineCard(
                    title: "Smoothness",
                    values: data?.smoothnessTrendPoints ?? [],
                    unit: "%",
                    formatValue: { String(format: "%.0f", $0) }
                )
            }
        } else {
            Text("iOS 16+ required for trend charts")
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

@available(iOS 16.0, *)
private func sparklineCard(title: String, values: [Double], unit: String, formatValue: @escaping (Double) -> String) -> some View {
    InstrumentCard {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                Spacer()
                if let last = values.last, last > 0 {
                    Text(formatValue(last))
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
            }
            if values.count > 1 {
                Chart {
                    ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                        LineMark(
                            x: .value("Drive", index),
                            y: .value(title, value)
                        )
                        .foregroundStyle(Color.ftBlue)
                        .interpolationMethod(.monotone)
                    }
                }
                .chartYAxis(.hidden)
                .chartXAxis(.hidden)
                .frame(height: 60)
            } else {
                Text("Need more drives")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
    }
}
```

**4. recentDrivesSection** — list of last 5 drives for this car:

```swift
private var recentDrivesSection: some View {
    VStack(alignment: .leading, spacing: 12) {
        let drives = data.map { driveManager.drives.filter { $0.carId == $0.car.id }
            .sorted { $0.startTime > $1.startTime }
            .prefix(5) } ?? []
        
        if !drives.isEmpty {
            SectionHeader(title: "Recent Drives")
            
            ForEach(Array(drives)) { drive in
                NavigationLink {
                    DriveDetailView(drive: drive)
                } label: {
                    DriveRowView(drive: drive)
                }
                .buttonStyle(.plain)
            }
        }
    }
}
```

Note: `DriveRowView` and `DriveDetailView` are in `DriveHistoryView.swift`. `SectionHeader` might be private to `CarDetailView` already or might need to be made accessible — check and copy if needed.

### Verification

- Build succeeds
- CarDetailView shows: hero → PB gauges → performance breakdown (4 cards) → vs Last Month → Trend sparklines (3 cards) → sparkline chart → driving style → stats grid → achievements → recent drives
- Each performance breakdown card has an ℹ️ button that shows the StatInfo popover
- "vs Last Month" shows the speed delta for this car's drives
- Sparkline trend cards render correctly for cars with 2+ drives
- Recent drives section shows up to 5 drives for the current car
- All sections handle the empty/nil state gracefully (show "—" or "Need more drives")
- CarDetailView toolbar shows Edit (pencil) button from Phase 1.1

---

## 2.4 Remove AnalyticsView, hoist shared types

**Goal:** Delete `AnalyticsView.swift` and `AnalyticsModels.swift`. Move still-needed types to their new homes. Remove the Analytics tab from `FastTrackApp.swift` (already done in 2.1, but this commit removes the dead code).

**Commit:** `refactor(ios): remove AnalyticsView and hoist shared types`

### What to move before deleting

| Type | Current file | New home | Notes |
|---|---|---|---|
| `AnalyticsData.smoothnessScore(for:)` | `AnalyticsModels.swift` | `CarStats.swift` | Already used by `CarStatsManager.calculateSmoothnessScore`; move the static method |
| `TrendDirection` | `AnalyticsModels.swift` | `SharedComponents.swift` | Used by `AnalyticsCard` and the new GarageView summary |
| `TimeFrame` | `AnalyticsModels.swift` | Delete | No longer needed (fixed "last month") |
| `AnalyticsMetric` | `AnalyticsModels.swift` | Delete | Chart picker gone |
| `AnalyticsCard` | `AnalyticsView.swift` | `SharedComponents.swift` or keep in `GarageView.swift` | Used by GarageView summary |
| `TrendIndicator` | `AnalyticsView.swift` | `SharedComponents.swift` | Used by `AnalyticsCard` |
| `PerformanceBreakdownCard` | `AnalyticsView.swift` | `CarDetailView.swift` or a shared components file | Used by CarDetailView breakdown section |
| `AnalyticsCarChip` | `AnalyticsView.swift` | Delete | Car filter no longer needed |
| `RecentBestCard` | `AnalyticsView.swift` | Delete | Replaced by per-car recent drives |
| `SkeletonBlock`, `StatCardSkeleton` | Check where defined | Keep if used elsewhere | Might be in SharedComponents |
| `SectionHeader` | Check where defined | Make internal or copy to CarDetailView | Used by CarDetailView |

### What to delete

1. **`ios/FastTrack/FastTrack/Views/AnalyticsView.swift`** — entire file
2. **`ios/FastTrack/FastTrack/Views/AnalyticsModels.swift`** — entire file (after hoisting)

### Steps

1. **Move `AnalyticsData.smoothnessScore(for:)` to `CarStats.swift`**:
   - The method is already called by `CarStatsManager.calculateSmoothnessScore` and by the new CarDetailView trend section
   - Add it as a static method on `AnalyticsData` in `AnalyticsModels.swift` first, then move the whole `AnalyticsData` struct... actually, since we're deleting `AnalyticsModels.swift`, just move the `smoothnessScore` method directly into `CarStats.swift` as a free function or on `CarStatsManager`:
     ```swift
     // In CarStats.swift, near CarStatsManager
     static func smoothnessScore(for drive: Drive) -> Double {
         // copy the exact implementation from AnalyticsData.smoothnessScore
     }
     ```
   - Then update `CarStatsManager.calculateSmoothnessScore` and `CarDetailView` trend section to use the new location.

2. **Move `TrendDirection` to `SharedComponents.swift`**:
   - Copy the `TrendDirection` enum (with its `icon`, `color`, `label` properties) to `SharedComponents.swift`
   - Remove from `AnalyticsModels.swift`

3. **Move `AnalyticsCard` and `TrendIndicator` to `SharedComponents.swift`**:
   - Copy both structs exactly as-is
   - Remove from `AnalyticsView.swift`

4. **Move `PerformanceBreakdownCard` to a shared location**:
   - It's now used by both (the old) `AnalyticsView` and (the new) `CarDetailView`
   - Since AnalyticsView is being deleted, just move it to `CarDetailView.swift` or create `Views/Components/PerformanceBreakdownCard.swift`
   - Recommendation: keep it inline in `CarDetailView.swift` since it's the only consumer after the delete

5. **Search for all references to deleted types** and update:
   - `AnalyticsView` (the view itself) — removed from tab bar in 2.1, delete any remaining references
   - `AnalyticsMetric` — delete
   - `TimeFrame` — delete
   - `AnalyticsCarChip` — delete
   - `RecentBestCard` — delete
   - `AnalyticsData` (struct) — delete after moving `smoothnessScore`
   - Any `#Preview` blocks referencing `AnalyticsView`

6. **Delete the files**:
   - `rm ios/FastTrack/FastTrack/Views/AnalyticsView.swift`
   - `rm ios/FastTrack/FastTrack/Views/AnalyticsModels.swift`

7. **Remove AnalyticsView from AppStoreScreenshotMode.swift** — if not already done in 2.1, update the `.analytics` case and remove `AnalyticsView` import.

### Verification

- Build succeeds with NO remaining references to `AnalyticsView`, `AnalyticsModels`, `AnalyticsCarChip`, `RecentBestCard`, `AnalyticsMetric`, `TimeFrame`, or `AnalyticsData`
- GarageView tab still works and shows all-cars summary + car grid + recent drives
- CarDetailView shows all new sections (breakdown, comparison, trends, recent drives)
- ProfileView shows "Your Garage" link
- No regressions in DriveHistoryView, SocialView, or PublicProfileView

---

## General verification for all Phase 2 changes

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

```bash
cd backend
CGO_ENABLED=1 go build ./... && CGO_ENABLED=1 go vet ./... && go test ./... -v -timeout 60s
```

### Tab structure after Phase 2

```
Track (0)     → ContentView (unchanged)
Social (1)    → SocialView (unchanged)
History (2)   → DriveHistoryView (unchanged)
Garage (3)    → GarageView (expanded with summary + recent drives)
Profile (4)   → ProfileView (slimmed, "Your Garage" link)
```

No Analytics tab. Per-car depth is in CarDetailView.