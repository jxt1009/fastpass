# FastTrack iOS UI Overhaul Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship a refined, fluid UI overhaul for Track and Leaderboard with minimal-friction filters and one-shot achievement celebration behavior.

**Architecture:** Keep existing data/API flows and recording logic intact while upgrading presentation primitives, interaction patterns, and motion consistency. Implement independent tracks in parallel branches/worktrees, then merge back into `feat/integration` after targeted verification.

**Tech Stack:** SwiftUI, MapKit, Charts, PhotosUI, XCTest, Xcodebuild

---

## File map

- Modify: `ios/FastTrack/FastTrack/DesignSystem.swift`
- Modify: `ios/FastTrack/FastTrack/Views/SharedComponents.swift`
- Modify: `ios/FastTrack/FastTrack/Views/SocialView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/ContentView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/CarDetailView.swift`
- Modify: `ios/FastTrack/FastTrack/Models/CarDetailData+Derive.swift`
- Test: `ios/FastTrack/FastTrackTests/CarDetailDataTests.swift`
- Test: `ios/FastTrack/FastTrackTests/ProfileRedesignTests.swift` (extend for leaderboard/filter presentation helpers if needed)

## Task 1: Foundation primitives (design tokens + reusable components)

**Files:**
- Modify: `ios/FastTrack/FastTrack/DesignSystem.swift`
- Modify: `ios/FastTrack/FastTrack/Views/SharedComponents.swift`

- [ ] Add restrained surface tokens for glass/highlight usage and keep existing semantic colors untouched.
- [ ] Add shared motion tokens (quick/standard/entrance/hero) used by Track + Leaderboard.
- [ ] Add reusable `FTGlassCard`/`FTProgressBar`/`FTActiveGlow` helpers in existing component style.
- [ ] Ensure no emoji placeholders are introduced in any reusable components.
- [ ] Verify compile by building iOS target.

Verify:
- `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

## Task 2: Leaderboard UX rewrite (no podium, one-tap quick filters)

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/SocialView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/SharedComponents.swift` (if helper chips/cards extracted)
- Modify: `ios/FastTrack/FastTrack/Models/SocialModels.swift` (only if formatter helpers needed)

- [ ] Remove podium layout and use a unified ranked list from #1 onward.
- [ ] Add optional compact "Your Position" card above list when current user appears in results.
- [ ] Implement one-tap quick filters inline:
  - scope chip toggles `Global/Following`
  - period chip cycles `24h/7d/All Time`
- [ ] Keep category as primary segmented switcher.
- [ ] Move car make/model filter into lightweight sheet/search action only.
- [ ] Auto-apply scope/period changes immediately (no Apply step).
- [ ] Keep loading/error/empty states functional and visually consistent.

Verify:
- `cd ios/FastTrack && xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack -destination "platform=iOS Simulator,name=iPhone 17 Pro" -only-testing:FastTrackTests/ProfileRedesignTests CODE_SIGNING_ALLOWED=NO`

## Task 3: Track HUD redesign (state-aware + restrained palette)

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/ContentView.swift`
- Modify: `ios/FastTrack/FastTrack/DesignSystem.swift`
- Modify: `ios/FastTrack/FastTrack/Views/SharedComponents.swift`

- [ ] Split idle vs recording visual states more clearly without changing recording semantics.
- [ ] Add speed hero arc/ring and numeric transitions tied to current speed.
- [ ] Use restrained accent palette (blue + warm threshold accents only).
- [ ] Refine live metric strip with compact frosted cards and animated value bars.
- [ ] Preserve map route/user marker behavior and existing controls/safety prompt.

Verify:
- `cd ios/FastTrack && xcodebuild build-for-testing -project FastTrack.xcodeproj -scheme FastTrack -destination "generic/platform=iOS Simulator" -configuration Debug CODE_SIGNING_ALLOWED=NO`

## Task 4: Confetti behavior fix (one-shot + subtle follow-up indicator)

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/CarDetailView.swift`
- Modify: `ios/FastTrack/FastTrack/Models/CarDetailData+Derive.swift` (only if needed for stable keying)
- Modify: `ios/FastTrack/FastTrackTests/CarDetailDataTests.swift`

- [ ] Fix repeated confetti replay on repeated car-detail opens.
- [ ] Gate celebration as one-shot for newly eligible achievement events.
- [ ] Replace repeat celebration with subtle persistent indicator in achievements strip.
- [ ] Add/extend tests for replay prevention behavior and regressions.

Verify:
- `cd ios/FastTrack && xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack -destination "platform=iOS Simulator,name=iPhone 17 Pro" -only-testing:FastTrackTests/CarDetailDataTests CODE_SIGNING_ALLOWED=NO`

## Task 5: Integration + regression verification

**Files:**
- Modify only as needed for merge conflict resolution and consistency pass.

- [ ] Merge implementation branches into `feat/integration` in low-risk order:
  1) foundation
  2) leaderboard
  3) track HUD
  4) confetti
- [ ] Resolve conflicts by preserving approved UX decisions (no podium, quick filters, restrained palette, no emojis).
- [ ] Run focused tests then full iOS test suite if feasible.
- [ ] Smoke-check key flows manually in simulator.

Verify:
- `cd ios/FastTrack && xcodebuild test -project FastTrack.xcodeproj -scheme FastTrack -destination "platform=iOS Simulator,name=iPhone 17 Pro" CODE_SIGNING_ALLOWED=NO`

## Success checks

- Leaderboard has no podium and uses low-friction quick filters.
- Scope/period changes require a single interaction and update immediately.
- Track feels more immersive while preserving legibility and existing logic.
- Confetti does not replay on every revisit.
- No emoji UI elements introduced.
