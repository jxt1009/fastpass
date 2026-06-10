# Worktree C — Issue #82: Car hero gauge formatting Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix the Top Speed and Best 0-60 gauges on the car hero in `CarDetailView` so the arc opens upward (half-donut), the numeric value sits **below** the arc, and the arc animates from 0 to its final value the first time the page is shown.

**Architecture:** Two targeted edits — change `GaugeArc`'s default angles in `DesignSystem.swift` and re-layout `CarDetailGauge` in `Views/Components/CarDetailGauge.swift` to put the value under the arc and add an `onAppear`-driven `withAnimation` that drives the displayed progress from 0 to the final value. The progress math in `Models/CarDetailGaugeProgress.swift` is unchanged. The public-profile variant `PublicCarDetailGauge` is intentionally left alone (separate scope).

**Tech Stack:** SwiftUI, XCTest. No backend, no model changes.

---

## File Structure

### Modify

- `ios/FastTrack/FastTrack/DesignSystem.swift` — `GaugeArc` angle defaults (135/45 → 180/360)
- `ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift` — re-layout value-below-arc + add `displayedProgress` state + onAppear animation

No new files. No new tests required (the existing `CarDetailGaugeProgressTests.swift` and `CarDetailGaugeProgressWiringTests.swift` lock the math, which is unchanged; the new view behavior is verified manually on the `iPhone 17 Pro` simulator).

---

## Task 1: Change `GaugeArc` defaults to open upward

**Files:**
- Modify: `ios/FastTrack/FastTrack/DesignSystem.swift:228-247`

- [ ] **Step 1: Read the current `GaugeArc` shape**

Open `ios/FastTrack/FastTrack/DesignSystem.swift:226-247`. The struct has `var startAngle: Angle = .degrees(135)` and `var endAngle: Angle = .degrees(45)`, which produces a 270° arc that opens downward. The fix is to make it a half-donut opening upward.

- [ ] **Step 2: Update the defaults**

Change the two lines in the `GaugeArc` struct:

Replace:
```swift
struct GaugeArc: Shape {
    var startAngle: Angle = .degrees(135)
    var endAngle: Angle = .degrees(45)
```

With:
```swift
struct GaugeArc: Shape {
    var startAngle: Angle = .degrees(180)
    var endAngle: Angle = .degrees(360)
```

The math inside `path(in:)` (the `- 90` rotation to SwiftUI's coordinate system) is unchanged and still produces a half-circle from 9 o'clock through 12 o'clock to 3 o'clock — i.e., opening upward.

- [ ] **Step 3: Build the project to confirm nothing else relies on the old defaults**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-82-gauges
xcodebuild build-for-testing \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Expected: build succeeds. (Other call sites that pass explicit `startAngle` / `endAngle` are unaffected; any site that uses the default is now an upward half-donut, which is what we want everywhere.)

- [ ] **Step 4: Commit**

```bash
git add ios/FastTrack/FastTrack/DesignSystem.swift
git commit -m "fix(ios): default GaugeArc opens upward (half-donut) for hero gauges"
```

---

## Task 2: Re-layout `CarDetailGauge` with value below arc and add the onAppear animation

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift`

- [ ] **Step 1: Read the current layout**

Open `ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift:40-91`. The current `body` lays out: icon+title header → value+unit HStack → arc (16pt tall strip, top-padded 2) → setOn caption. The fix moves the value+unit HStack to *after* the arc, gives the arc a proper height, and adds the onAppear animation.

- [ ] **Step 2: Replace `body` with the new layout**

Replace the entire `body` and `arc` builder with the version below. The new layout:
- Header (icon + title) on top
- Arc in the middle with explicit 100pt height
- Value + unit HStack below the arc
- Set-on caption at the bottom
- `@State private var displayedProgress: Double = 0` to drive the animation
- `.onAppear { withAnimation { displayedProgress = progress ?? 0 } }` to start the trim from 0

```swift
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon(for: title))
                    .font(.caption)
                    .foregroundColor(color)
                Text(title.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .tracking(0.5)
                    .foregroundColor(.secondary)
            }

            arc
                .frame(height: 100)
                .padding(.top, 2)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(color.opacity(0.75))
                }
            }

            if let setOn {
                Text("Set on \(setOn.formatted(dateFormat))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("No record yet")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
        .onAppear {
            // Drive the trim from 0 to the final value with a 0.6s
            // ease-in-out. The implicit .animation on `progress` only
            // fires when the value changes after the view is on
            // screen; this is the entry-point animation.
            let target = progress ?? 0
            if displayedProgress == 0 && target > 0 {
                withAnimation(.easeInOut(duration: 0.6)) {
                    displayedProgress = target
                }
            } else {
                displayedProgress = target
            }
        }
        .onChange(of: progress) { _, newValue in
            // Subsequent PB updates (e.g. user records a faster time
            // and comes back to the page) animate to the new value
            // via the existing 0.35s ease-in-out on the trim.
            withAnimation(.easeInOut(duration: 0.35)) {
                displayedProgress = newValue ?? 0
            }
        }
    }

    @State private var displayedProgress: Double = 0

    @ViewBuilder
    private var arc: some View {
        if let _ = progress {
            ZStack(alignment: .leading) {
                GaugeArc()
                    .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                GaugeArc()
                    .trim(from: 0, to: max(0.001, displayedProgress))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .animation(.easeInOut(duration: 0.6), value: displayedProgress)
            }
        } else {
            ZStack(alignment: .leading) {
                GaugeArc()
                    .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                GaugeArc()
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .opacity(0.85)
            }
        }
    }
```

Notes on what changed:

- `spacing: 6 → 8` and `padding(.top, 2)` on the arc frame so the half-donut has room above the value.
- Arc `frame(height: 16 → 100)` so the half-circle has actual room to draw (16pt would clip a 180° arc).
- Stroke `lineWidth: 4 → 6` so the arc reads as a chunky gauge rather than a thin underline.
- Trim value uses `displayedProgress` (the animated state) rather than `progress` (the input).
- `displayedProgress` is clamped to `max(0.001, …)` so a zero trim is not skipped by SwiftUI's `trim` modifier (which treats `from == to` as fully hidden).
- `onChange(of: progress)` keeps the existing "subsequent PB" animation behavior so opening the page twice in a row still animates from the previous value to the new one.

- [ ] **Step 3: Build the project**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-82-gauges
xcodebuild build-for-testing \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Expected: build succeeds.

- [ ] **Step 4: Run the full iOS test suite**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-82-gauges
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass (the existing `CarDetailGaugeProgressTests.swift` and `CarDetailGaugeProgressWiringTests.swift` lock the progress math, which is unchanged).

- [ ] **Step 5: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift
git commit -m "fix(ios): half-donut hero gauges with value below arc and entry animation

Two changes to CarDetailGauge:

- Re-layout: header on top, 100pt-tall arc in the middle, value+unit
  below the arc, set-on caption at the bottom. Stroke bumped from
  4pt to 6pt to read as a chunky gauge.
- Entry animation: @State displayedProgress starts at 0 and is
  driven to the final value inside withAnimation(.easeInOut,
  duration: 0.6) from onAppear. The previous implicit animation
  only fired on progress changes after the view was on screen, so
  the first paint of the page never animated. Subsequent PB
  changes still animate via onChange.

Combined with the GaugeArc default-angle change, the car hero
gauges now open upward (half-donut) and animate in on first appear."
```

---

## Task 3: Manual visual check on simulator

**Files:** none (verification only)

- [ ] **Step 1: Boot the iPhone 17 Pro simulator and run the app**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-82-gauges
xcrun simctl boot "iPhone 17 Pro" 2>/dev/null || true
open -a Simulator
xcodebuild test \
  -project ios/FastTrack/FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackUITests/CarDetailViewSmokeTest \
  CODE_SIGNING_ALLOWED=NO 2>/dev/null || true
# Manual path: launch the app on the simulator and navigate to
# a CarDetailView. The previews and examples in the codebase
# cover this — see `CarDetailView.swift`'s debug preview helpers.
```

- [ ] **Step 2: Verify the visual**

On the CarDetailView hero, confirm:

1. The Top Speed and Best 0-60 gauges each show a half-donut arc that **opens upward** (gap at the bottom, curve at the top).
2. The numeric value sits **below** the arc, not above.
3. When the page is first opened, the arc trim animates from 0 to its final value over ~0.6 s.
4. The "Set on …" caption is still visible at the bottom.
5. The "—" placeholder value when no record exists still renders cleanly (no animation, arc shows the decorative 0% state).

- [ ] **Step 3: Verify the public profile gauge is unchanged**

Navigate to a public profile (`PublicCarDetailView` via a search for another user). Confirm the public variant still renders its text-only tile (no arc, no animation) — this is the intentional split per the spec.

---

## Verification

- [ ] `xcodebuild build-for-testing` clean
- [ ] `xcodebuild test` (full suite, iPhone 17 Pro) clean
- [ ] Manual visual check matches all five items in Step 2 above
- [ ] Public variant unchanged

## Definition of done

- Arc opens upward (half-donut)
- Value sits below the arc
- Animation runs from 0 to final on first appear
- Subsequent visits / PB changes still animate
- All iOS tests pass
