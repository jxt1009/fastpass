# 2026-06-15 — Revert floating pill tab bar to system tab bar

## Goal

User found the custom `FloatingTabBar` floating pill harder to use than the
standard iOS tab bar — it lacks the familiar gestures, accessibility behaviors,
and predictability of the system tab bar. Restore the system `TabView` tab
bar while keeping the rest of the new design language (gradient backgrounds,
glass cards, status dots, etc.) intact on the screens themselves.

## Scope

In scope (revert):
- Restore system tab bar by removing the `.tabViewStyle(.page(...))` /
  `.toolbar(.hidden, for: .tabBar)` / `FloatingTabBar` overlay combination in
  `FastTrackApp.swift`.
- Delete `FastTrack/Views/Components/FloatingTabBar.swift`.
- Revert the 80pt bottom padding on the Start Drive button (in
  `ContentView.swift:60`) to `Spacing.lg` (24pt).
- Revert the 80pt bottom padding on the toast (in
  `Views/Components/Toast.swift:106`) — remove it entirely (the toast was
  positioned just above the safe area before the floating pill existed).
- Inline the `AppTab` enum (the only remaining type from
  `FloatingTabBar.swift` still used by `RootView.selectedTab`) into
  `FastTrackApp.swift`. Drop the `icon` / `label` / `accentColor` helpers —
  they were only consumed by the deleted `FloatingTabBar` view.

Out of scope (keep):
- All other design language changes (gradients, glass cards, status dots,
  `ScreenWakeController`, gauge alignment, splash screen polish, cell sizes,
  light-mode fixes, etc.).
- `ScreenWakeController` and its wiring in `RootView`.

## Files changed

| File | Change |
|---|---|
| `ios/FastTrack/FastTrack/FastTrackApp.swift` | Remove `.tabViewStyle`/`.toolbar(.hidden)`/`FloatingTabBar` overlay; inline `AppTab` enum |
| `ios/FastTrack/FastTrack/Views/Components/FloatingTabBar.swift` | Deleted |
| `ios/FastTrack/FastTrack/Views/Components/Toast.swift` | Remove `.padding(.bottom, 80)` line |
| `ios/FastTrack/FastTrack/Views/ContentView.swift` | Revert `.padding(.bottom, 80)` → `.padding(.bottom, Spacing.lg)` |

## Verification

- `xcodebuild build-for-testing` — `** TEST BUILD SUCCEEDED **`
- `xcodebuild test` (ScreenWakeController, DesignSystem, GradientProgressBar,
  StatusDot) — all 20 tests pass, `** TEST SUCCEEDED **`

## Backward compatibility

No API / DB changes. iOS-only UI revert. App is fully backward compatible
with last week's release (the system tab bar is what the prior release
already had).
