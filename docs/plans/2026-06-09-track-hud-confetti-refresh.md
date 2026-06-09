# 2026-06-09 Track HUD + Confetti Refresh

## Goal

Implement Task 3+4 polish in iOS by refreshing the track HUD presentation and fixing per-car confetti replay so celebrations are one-shot per newly eligible PB moment.

## Scope

1. Update `ContentView` tracking HUD visuals while preserving recording controls, semantics, safety disclaimer, map route, and location behavior.
2. Fix `CarDetailView` confetti replay to trigger once per new eligible unlock state, and replace repeated revisit celebration with a subtle ongoing indicator in the PB area.
3. Add/extend unit coverage for one-shot confetti trigger logic.

## Planned file changes

- Modify `ios/FastTrack/FastTrack/Views/ContentView.swift`
  - Refine idle vs recording presentation.
  - Add speed hero arc/ring behind numeric speed.
  - Replace rainbow-heavy accents with restrained palette treatment.
  - Redesign metric strip cards with compact frosted style and animated progress bars.
- Modify `ios/FastTrack/FastTrack/Views/CarDetailView.swift`
  - Make confetti trigger one-shot per newly eligible token.
  - Keep celebration behavior for new moments and suppress replay on revisit.
  - Add subtle “recent PB” indicator in personal bests area.
- Modify `ios/FastTrack/FastTrack/Models/CarDetailData.swift`
  - Extend derived model with confetti trigger token and recent PB indicator support.
- Modify `ios/FastTrack/FastTrack/Models/CarDetailData+Derive.swift`
  - Derive stable confetti token from eligible per-car achievement unlocks.
- Modify `ios/FastTrack/FastTrackTests/CarDetailDataTests.swift`
  - Add test coverage for token stability/change behavior across old/new unlock combinations.

## Verification plan

- Run iOS build-for-testing:
  - `xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`
- Run targeted unit tests for confetti/derive logic:
  - `xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack -destination "platform=iOS Simulator,name=iPhone 17 Pro" -only-testing:FastTrackTests/CarDetailDataTests CODE_SIGNING_ALLOWED=NO`
