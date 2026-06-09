# Plan: FastTrack Garage, Stats, and Competition UX

**Date:** 2026-06-08  
**Status:** Draft, ready for issue split  
**Branch:** `plan/fasttrack-garage-stats-competition`  
**Worktree:** `.worktrees/fasttrack-ux-plan`  
**Style:** additive-only backend contracts, additive-by-default migrations, one worktree per implementation track, conventional commits

## 0. North star

FastTrack should feel like a credible performance logbook and leaderboard for real cars.

Every drive should do at least one of these:

- Update a car's story.
- Improve or validate a stat.
- Change where the user ranks.
- Give the user a clear next action.

The app should emphasize garage pride, trustworthy personal bests, fair competition, and clear progress over novelty or generic gamification.

## 1. Product principles

| Principle | Meaning |
|---|---|
| Car-first | Stats usually belong to a car before they belong to a user. |
| Credible over flashy | Measured, explainable, confidence-aware stats beat gimmicks. |
| PBs are sacred | Personal bests must be current, accurate, and separate from achievements. |
| Garage pride | The garage is a core identity surface, not only a profile subsection. |
| Fair competition | Compare similar cars, friends, rivals, and verified-quality stats. |
| Profile is identity | Profile should not be a dumping ground for all telemetry and settings. |
| Additive compatibility | Backend changes must tolerate old iOS clients. |

## 2. Current diagnosis

| Area | Problem | Impact |
|---|---|---|
| Garage | Half-baked management and duplicated cards | Users can add/select cars, but not intuitively manage the garage. |
| Profile | Too many responsibilities | Identity, settings, garage, stats, achievements, and account actions compete. |
| Analytics | Repeats Profile data | Less insight, more stat dumping. |
| Achievements | Split local/server truth | Inconsistent progress, missing server achievements, placeholder logic. |
| PBs | Mixed with achievement source drives | "Personal best" can mean the unlock drive, not the current best. |
| Stats | Different formulas and labels | Smoothness, driving score, and 0-60 labeling reduce trust. |
| Public/social | Public garage stats contract incomplete | Public garage/car pages underdeliver. |
| Competition | Global leaderboard only does part of the job | Users need car-class, friends, rivals, and rank movement. |

## 3. Specific bugs and risks discovered

These should be tracked explicitly, not treated as incidental cleanup.

| Priority | Issue | Suggested owner track |
|---|---|---|
| High | Profile privacy can reset because `AuthManager.User` does not decode `is_public`, and profile setup can recreate a profile with `isPublic = true`. | Track A |
| High | Garage restore only trusts server data when server car count is higher, so same-count edits/deletes/photo changes can be ignored. | Track A |
| High | Public profile iOS model expects `car_stats_data`, but backend public profile response does not emit it. | Track B |
| High | Profile can show `Best 0-60 km/h time`, but current metric is 0-60 mph. | Track C |
| High | Recording with no garage can create stats for an `Unknown Vehicle` that is not actually in the garage. | Track A or D |
| High | Add-car photo upload failure can be hidden if the sheet dismisses before the user can retry. | Track E |
| High | Username path segments are inconsistently encoded in public profile/follow/achievement routes. | Track B |
| High | iOS achievements have placeholder progress for 0-60 and smoothness while the server catalog has additional entries. | Track H |
| High | True PBs are blurred with achievement source-drive ids. | Track C |
| High | Smoothness has different formulas in Analytics, CarStats, and glossary copy. | Track C |
| Medium | Car picker years are hard-coded through 2025. | Track D |
| Medium | `CarService` shared mutable `models/isLoading/error` can be stomped by concurrent/preload fetches. | Track D |
| Medium | `CarStatsManager.rebuildStats(from:)` uploads once per drive. | Track A |
| Medium | `CarDetailView` refreshes on counts only, so same-count content changes can be missed. | Track F |
| Medium | `CarDetailView` receives a snapshot `UserCar`, so edited nickname/photo may not update while open. | Track F |
| Medium | Settings are duplicated between Profile and `SettingsView`; Profile omits calibration and has unused `showingSettings`. | Track G |
| Medium | Analytics "Recent Best Performances" is sorted by max speed, not recency. | Track I |
| Medium | Public car detail comments mention public achievements, but public profile does not render them. | Track B or H |

## 4. Target information architecture

| Area | Responsibility |
|---|---|
| Track | Start/stop recording, active car, live instrumentation, safety gating. |
| Garage | Manage vehicles, assign drives, compare cars, view per-car PBs and history. |
| Analytics | Trends, insights, improvement opportunities, car/time filters. |
| Profile | Public identity, social proof, trophy preview, privacy/account entry points. |
| Achievements | Milestones and unlock history, not a parallel stats model. |
| Social | Fair leaderboards, rivals, public garages, rank movement. |

## 5. Parallel implementation tracks

All tracks should start from latest `main` in their own `.worktrees/<name>/` worktree. Tracks inside a phase can run in parallel unless a dependency is listed.

```
Phase 1: Trust foundation, parallel
  Track A: iOS profile/garage data trust
  Track B: public/social contract fixes
  Track C: stat vocabulary and true PB model
  Track D: picker and no-garage recording decisions

Phase 2: UX structure and component reuse, parallel after Phase 1 basics
  Track E: shared media/card/photo components
  Track F: Garage as vehicle hub
  Track G: Profile as identity and trophy case
  Track I: Analytics as insights

Phase 3: Competition and achievement depth
  Track H: achievements catalog and milestone cleanup
  Track J: fair leaderboards, rivals, rank movement, stat confidence
```

## 6. Track A - iOS profile and garage data trust

**Recommended issue title:** `fix(ios): preserve profile privacy and garage restore state`  
**Suggested branch:** `fix/ios-profile-garage-restore`  
**Suggested worktree:** `.worktrees/ios-profile-garage-restore`

### Scope

- Decode and persist `is_public` through `AuthManager.User` and `ProfileManager.restoreFromServer`.
- Ensure profile setup/edit preserves existing `isPublic`.
- Replace count-based garage restore with deterministic server/local rules.
- Centralize garage encode/decode helpers.
- Avoid repeated car-stats uploads during stats rebuild.
- Decide and enforce no-garage recording behavior.

### Likely files

- `ios/FastTrack/FastTrack/Services/AuthManager.swift`
- `ios/FastTrack/FastTrack/Models/UserProfile.swift`
- `ios/FastTrack/FastTrack/Views/ProfileSetupView.swift`
- `ios/FastTrack/FastTrack/Models/CarStats.swift`
- `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift`
- `ios/FastTrack/FastTrack/Views/ContentView.swift`
- Tests under `ios/FastTrack/FastTrackTests/`

### Acceptance

- Private profiles stay private after sign-in, token refresh, reinstall restore, and profile edit.
- Same-count garage edits, photo changes, and deletes restore predictably.
- Recording without a garage no longer silently creates phantom car stats.
- Car stats rebuild performs one save/upload at the end, not one per drive.

### Verification

- Add tests for privacy restore and profile setup preserving `isPublic`.
- Add tests for server garage same-count edit/delete restore behavior.
- Add tests or source guards for no-garage recording decision.

## 7. Track B - public/social contract fixes

**Recommended issue title:** `fix(api): expose public garage stats and encode user routes safely`  
**Suggested branch:** `fix/public-garage-stats-contract`  
**Suggested worktree:** `.worktrees/public-garage-stats-contract`

### Scope

- Add `car_stats_data` to public profile response as an additive field.
- Keep old clients safe by only adding JSON fields.
- Standardize username path-segment encoding in iOS API routes.
- Decide whether public profiles should show achievements now or in Track H.

### Likely files

- `backend/internal/app/social_handlers.go`
- Backend handler tests
- `ios/FastTrack/FastTrack/Models/SocialModels.swift`
- `ios/FastTrack/FastTrack/Services/APIService.swift`
- `ios/FastTrack/FastTrack/Views/PublicProfileView.swift`
- `ios/FastTrack/FastTrack/Views/PublicGarageCard.swift`
- `ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift`

### Acceptance

- Public profile responses include `car_stats_data` additively.
- Public garage cards and public car detail can render per-car stats.
- Usernames with path-significant characters are encoded consistently.
- Private users remain hidden.

### Verification

- Backend: `CGO_ENABLED=1 go build ./...`, `CGO_ENABLED=1 go vet ./...`, `go test ./... -v -timeout 60s`.
- iOS: add/update public profile decode tests.

## 8. Track C - stat vocabulary and true PB model

**Recommended issue title:** `refactor(ios): separate true personal bests from achievements`  
**Suggested branch:** `refactor/ios-stat-vocabulary-pbs`  
**Suggested worktree:** `.worktrees/ios-stat-vocabulary-pbs`

### Scope

- Define one shared stat vocabulary and formatter layer.
- Introduce a pure PB derivation model from current drives.
- Use PB derivation in drive history, car detail, and analytics.
- Standardize `0-60 mph` labeling everywhere unless a future true `0-100 km/h` metric is added.
- Pick one smoothness formula and align Analytics, CarStats, glossary, and achievement behavior.

### Likely files

- `ios/FastTrack/FastTrack/Models/Drive.swift`
- `ios/FastTrack/FastTrack/Views/AnalyticsModels.swift`
- `ios/FastTrack/FastTrack/Models/CarStats.swift`
- `ios/FastTrack/FastTrack/Views/SharedComponents.swift`
- `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift`
- `ios/FastTrack/FastTrack/Views/DriveHistoryView.swift`
- `ios/FastTrack/FastTrack/Views/CarDetailView.swift`
- `ios/FastTrack/FastTrackTests/PersonalBestsTests.swift`

### Acceptance

- "PB" always means current personal best.
- Achievement source drives are no longer used as a substitute for current PBs.
- Metric users do not see misleading `0-60 km/h` labels.
- Smoothness has one formula and one explanation.

## 9. Track D - picker correctness and recording prerequisites

**Recommended issue title:** `fix(ios): harden car selection and recording prerequisites`  
**Suggested branch:** `fix/ios-car-picker-recording-prereqs`  
**Suggested worktree:** `.worktrees/ios-car-picker-recording-prereqs`

### Scope

- Allow current and near-future model years instead of hard-coding through 2025.
- Refactor `CarService` so concurrent model fetches do not stomp visible picker state.
- Decide whether normal recording requires an active car.
- If unassigned drives remain supported, surface them as cleanup tasks in Garage.

### Likely files

- `ios/FastTrack/FastTrack/Services/CarService.swift`
- `ios/FastTrack/FastTrack/Views/CarPickerView.swift`
- `ios/FastTrack/FastTrack/Views/ContentView.swift`
- `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift`
- `ios/FastTrack/FastTrack/Views/GarageView.swift`

### Acceptance

- 2026 model years are selectable.
- Background/preload fetches cannot replace the user's selected make models.
- Start-drive flow clearly handles missing garage/active car.

## 10. Track E - shared garage/media components

**Recommended issue title:** `refactor(ios): share car media and garage card components`  
**Suggested branch:** `refactor/ios-shared-car-components`  
**Suggested worktree:** `.worktrees/ios-shared-car-components`

### Scope

- Extract shared car photo thumbnail, hero, placeholder, and initials logic.
- Extract shared photo picker/crop/upload/remove flow for add/edit car.
- Consolidate compact, grid, public, and selector car card rendering where practical.
- Consolidate private/public car gauge components.

### Likely files

- `ios/FastTrack/FastTrack/Views/ProfileView.swift`
- `ios/FastTrack/FastTrack/Views/GarageView.swift`
- `ios/FastTrack/FastTrack/Views/CarDetailView.swift`
- `ios/FastTrack/FastTrack/Views/PublicGarageCard.swift`
- `ios/FastTrack/FastTrack/Views/PublicCarDetailView.swift`
- `ios/FastTrack/FastTrack/Views/CarSelectorView.swift`
- `ios/FastTrack/FastTrack/Views/EditCarView.swift`
- `ios/FastTrack/FastTrack/Views/Components/CarDetailGauge.swift`
- `ios/FastTrack/FastTrack/Views/Components/PublicCarDetailGauge.swift`

### Acceptance

- No duplicated car photo rendering logic across major screens.
- Add/edit photo behavior is consistent and does not dismiss on recoverable upload failure.
- Public and private car surfaces share primitives while preserving read-only behavior.

## 11. Track F - Garage as the vehicle hub

**Recommended issue title:** `feat(ios): make garage the vehicle management hub`  
**Suggested branch:** `feat/ios-garage-management-hub`  
**Suggested worktree:** `.worktrees/ios-garage-management-hub`

### Scope

- Make `GarageView` the primary place to manage vehicles.
- Add first-class actions: set active, edit, photo, archive/delete, recent drives, compare.
- Prefer archive over hard delete unless explicitly decided otherwise.
- Surface unassigned drives if Track D supports them.
- Make `CarDetailView` the canonical vehicle dashboard.

### Likely files

- `ios/FastTrack/FastTrack/Views/GarageView.swift`
- `ios/FastTrack/FastTrack/Views/EditCarView.swift`
- `ios/FastTrack/FastTrack/Views/CarDetailView.swift`
- `ios/FastTrack/FastTrack/Models/CarDetailData.swift`
- `ios/FastTrack/FastTrack/Models/CarDetailData+Derive.swift`
- `ios/FastTrack/FastTrack/Views/DriveDetailView.swift`
- `ios/FastTrack/FastTrack/Models/UserProfile.swift`

### Acceptance

- User can instantly tell which car is active.
- User can manage every car lifecycle state.
- Per-car detail shows true PBs, recent drives, trends, and meaningful car stats.
- Old drives remain historically accurate after archive/delete.

## 12. Track G - Profile as identity and trophy case

**Recommended issue title:** `refactor(ios): simplify profile into identity and trophy case`  
**Suggested branch:** `refactor/ios-profile-identity-trophy-case`  
**Suggested worktree:** `.worktrees/ios-profile-identity-trophy-case`

### Scope

- Keep profile header, follower/following, public/private state, recent trophy preview, and compact garage preview.
- Move dense stats to Analytics and per-car stats to Garage.
- Move settings controls to `SettingsView`, linked from Profile toolbar.
- Group destructive actions away from the main profile content.

### Likely files

- `ios/FastTrack/FastTrack/Views/ProfileView.swift`
- `ios/FastTrack/FastTrack/Views/SettingsView.swift`
- `ios/FastTrack/FastTrack/Views/Components/RecentAchievementsStrip.swift`
- `ios/FastTrack/FastTrack/Views/GarageView.swift`

### Acceptance

- Profile is visibly shorter and clearer.
- Profile no longer duplicates settings or dense analytics.
- Garage and Analytics become the obvious places for vehicle/stats depth.

## 13. Track H - achievements catalog and milestone cleanup

**Recommended issue title:** `fix(ios): render server achievements without placeholder progress`  
**Suggested branch:** `fix/ios-server-achievements-catalog`  
**Suggested worktree:** `.worktrees/ios-server-achievements-catalog`

### Scope

- Treat backend catalog/unlocks as authoritative for achievement definitions and unlocked state.
- Render server-only achievements safely.
- Add unknown-safe category/type mapping.
- Remove fake local progress for unsupported types, or implement it fully.
- Separate milestone achievements from true PBs.
- Convert `AchievementsView` from `NavigationView` to `NavigationStack`.
- Reassess gimmicky achievements and prefer car/PB/rank milestones.

### Likely files

- `ios/FastTrack/FastTrack/Models/Achievement.swift`
- `ios/FastTrack/FastTrack/Models/UserAchievement.swift`
- `ios/FastTrack/FastTrack/Views/AchievementsView.swift`
- `ios/FastTrack/FastTrack/Views/Components/RecentAchievementsStrip.swift`
- `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift`
- `backend/internal/app/achievements.go`

### Acceptance

- Server-only achievements render.
- Unsupported progress is not shown as if it were real.
- Achievements do not compete with PBs for meaning.
- Recent achievements still deep-link where a source drive exists.

## 14. Track I - Analytics as insights

**Recommended issue title:** `feat(ios): add car-scoped analytics insights`  
**Suggested branch:** `feat/ios-car-scoped-analytics-insights`  
**Suggested worktree:** `.worktrees/ios-car-scoped-analytics-insights`

### Scope

- Add car filter: all cars, active car, selected car.
- Promote insight cards over repeated totals.
- Add period comparison and PB deltas.
- Rename or fix "Recent Best Performances" so the label matches sorting.
- Add garage comparison insights.

### Likely files

- `ios/FastTrack/FastTrack/Views/AnalyticsView.swift`
- `ios/FastTrack/FastTrack/Views/AnalyticsModels.swift`
- `ios/FastTrack/FastTrack/Views/DrivePerformanceDetailView.swift`
- `ios/FastTrack/FastTrack/Models/CarStats.swift`

### Acceptance

- Analytics answers "what changed?" and "what should I care about?"
- Users can analyze one car or the whole garage.
- Profile no longer needs a dense stat dump.

## 15. Track J - fair competition, rivals, and stat confidence

**Recommended issue title:** `feat: add fair car leaderboards and stat confidence`  
**Suggested branch:** `feat/fair-car-leaderboards-stat-confidence`  
**Suggested worktree:** `.worktrees/fair-car-leaderboards-stat-confidence`

### Scope

- Add car-scoped leaderboards by make/model/year/trim where data supports it.
- Add rivals/nearby-rank context so users outside top 50 still have competition.
- Add rank movement notifications for meaningful changes.
- Add stat confidence/quality flags based on GPS quality, plausibility, route length, and sample count.
- Keep competition tied to cars and stats, not generic social feed noise.

### Likely files

- `backend/internal/app/social_handlers.go`
- `backend/internal/app/handlers.go` or drive save handlers
- `backend/internal/app/notifications*`
- `ios/FastTrack/FastTrack/Views/SocialView.swift`
- `ios/FastTrack/FastTrack/Models/SocialModels.swift`
- `ios/FastTrack/FastTrack/Services/NotificationsManager.swift`
- `ios/FastTrack/FastTrack/Models/Drive.swift`

### Acceptance

- A normal user can see who they are chasing, not only the global top 50.
- Leaderboards can be filtered to fair car comparisons.
- Low-confidence stats are not silently treated as equally trustworthy.
- Notifications celebrate concrete car/stat/rank events.

## 16. Recommended first issue split

Start with these PR-sized issues, in this order. Items 1-4 can run in parallel after branches are created from latest `main`.

| Order | Issue title | Track | Blocks |
|---|---|---|---|
| 1 | `fix(ios): preserve profile privacy and garage restore state` | A | Garage management, profile cleanup |
| 2 | `fix(api): expose public garage stats and encode user routes safely` | B | Public garage polish |
| 3 | `refactor(ios): separate true personal bests from achievements` | C | Analytics, achievements, car detail |
| 4 | `fix(ios): harden car selection and recording prerequisites` | D | Garage management |
| 5 | `refactor(ios): share car media and garage card components` | E | Profile/Garage/Public UI cleanup |
| 6 | `feat(ios): make garage the vehicle management hub` | F | Depends on A/D/E decisions |
| 7 | `refactor(ios): simplify profile into identity and trophy case` | G | Benefits from E |
| 8 | `feat(ios): add car-scoped analytics insights` | I | Depends on C |
| 9 | `fix(ios): render server achievements without placeholder progress` | H | Depends on C |
| 10 | `feat: add fair car leaderboards and stat confidence` | J | Backend/product follow-up |

## 17. Gimmicks to reduce

| Current/future risk | Recommendation |
|---|---|
| Confetti everywhere | Reserve for real PBs or major milestones. |
| Vague driving score | Keep only if formula is defensible and explained. |
| "Supercar" style labels from one top-speed stat | Reframe as lightweight categories or remove from serious contexts. |
| Repeated stat dumps | Replace with scoped, actionable insight. |
| Generic social feed | Only add feed items tied to car/stat/rank events. |
| Placeholder achievement progress | Remove unless computation is real. |

## 18. Open product decisions

| Decision | Recommendation |
|---|---|
| Delete vs archive cars | Archive first. Preserve old drive identity and allow hiding inactive cars. |
| Recording without a car | Require an active car in normal flow; support unassigned only for legacy cleanup. |
| Metric 0-60 | Keep `0-60 mph` label everywhere; add true `0-100 km/h` later as a separate metric. |
| Achievement source of truth | Backend catalog/unlocks authoritative; local progress is only a preview when trustworthy. |
| Stat confidence | Start simple with low/normal/high confidence flags; refine later. |
| Public achievements | Show only if privacy model is clear and source-drive links respect private data. |

## 19. Verification commands

Backend:

```bash
cd backend
CGO_ENABLED=1 go build ./...
CGO_ENABLED=1 go vet ./...
go test ./... -v -timeout 60s
```

iOS:

```bash
cd ios/FastTrack
cp FastTrack/Secrets.swift.template FastTrack/Secrets.swift
xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

## 20. Plan maintenance

- Keep this file updated as tracks start, split, merge, or get superseded.
- Each implementation PR should link to this plan and mark its track status.
- If a backend change requires a client-aware cutover, document the cutover here and in the PR body.
- Rebase every worktree onto latest `origin/main` before push or PR update.
