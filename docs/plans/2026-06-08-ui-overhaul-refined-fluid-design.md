# FastTrack iOS Refined + Fluid UI Overhaul Design

Date: 2026-06-08
Branch: `feat/integration`
Status: Draft for review

## Context and goals

This design defines a full visual/interaction overhaul for iOS with these priorities:

1. App-wide design language with more life (refined and fluid, not gimmicky)
2. Leaderboard redesign (less clutter, better hierarchy)
3. Track view redesign (more engaging dashboard/HUD feel)
4. Confetti behavior fix (no repeat spam)

User direction incorporated:

- Keep the app feeling premium and intentional, not noisy
- Reduce rainbow-like gauge colors in favor of a restrained palette
- No emoji UI elements in product surfaces
- Improve leaderboard filter interaction model

## Product principles

1. Motion communicates state, not decoration
2. Depth and hierarchy should improve scanability
3. Visual language should stay consistent across tabs
4. Interactions should feel responsive and calm
5. No gimmicks: avoid novelty effects that do not improve usability

## Scope

### In scope

- Shared visual system upgrades (tokens, surfaces, transitions)
- Leaderboard layout and filter UX overhaul
- Track idle/recording presentation overhaul
- Confetti trigger fix and replacement micro-feedback

### Out of scope (for this implementation cycle)

- Full image crop/zoom library migration (captured as follow-up)

## Architecture and component design

## 1) Shared design foundation

Primary files:

- `ios/FastTrack/FastTrack/DesignSystem.swift`
- `ios/FastTrack/FastTrack/Views/SharedComponents.swift`

### 1.1 Color and surface model

Keep existing core semantics (`ftBlue`, `ftGreen`, `ftAmber`, `ftRed`, `ftCardBg`, `ftSurfaceBg`) but add restrained usage rules:

- Use one dominant accent per surface (usually `ftBlue`)
- Use warm accents (`ftAmber`, `ftRed`) only for speed intensity and warnings
- Avoid multi-stop rainbow treatment for default gauges

Add lightweight surface variants:

- `ftGlassBg`: translucent dark material for overlays/cards
- `ftGlassStroke`: low-contrast border for glass panels
- `ftHighlightBlue`: subtle highlight fill for selected cards/rows

### 1.2 Motion tokens

Add centralized motion tokens so transitions are coherent:

- `ftMotionQuick` (tap feedback)
- `ftMotionStandard` (state updates)
- `ftMotionEntrance` (section/card entrances)
- `ftMotionHero` (large HUD transitions)

All new animations should use these tokens, not local one-off curves.

### 1.3 Reusable modifiers/components

Add/upgrade reusable primitives:

- `FTGlassCard` (or evolve `InstrumentCard`) for frosted surfaces
- `FTActiveGlow` modifier for active speed/readout states
- `FTValueTransition` wrapper to standardize numeric text transitions
- `FTProgressBar` for restrained animated bars (single-tone or two-tone)

No emoji assets or emoji placeholders in redesigned UI components.

## 2) Leaderboard redesign

Primary file:

- `ios/FastTrack/FastTrack/Views/SocialView.swift`

Supporting:

- `ios/FastTrack/FastTrack/Models/SocialModels.swift`
- `ios/FastTrack/FastTrack/Views/SharedComponents.swift`

### 2.1 Information hierarchy

New vertical flow:

1. Header with title/actions
2. Category switcher (Top Speed / 0-60 / Distance)
3. Quick filter row (Scope + Period one-tap controls)
4. Optional "Your Position" card (when current user is in results)
5. Ranked list (full leaderboard starting at #1)

### 2.2 Filter interaction model (minimal interaction, low friction)

Current issue: three segmented controls + text filter are always visible and consume too much attention.

New model:

- Keep category segmented control visible inline (primary interaction)
- Add two compact quick-filter chips inline:
  - Scope chip: one tap toggles `Global <-> Following`
  - Period chip: one tap cycles `24h -> 7d -> All Time`
- Car filter is secondary and stays behind a trailing filter/search button
- Tapping filter/search opens a lightweight sheet only for car make/model input and clear action
- Scope and period changes auto-apply immediately (no explicit Apply button)
- Show active filter summary only when car filter is applied (example: `BMW M3`)

Benefits:

- Reduces persistent clutter
- Makes common filter changes one tap
- Keeps advanced filtering accessible
- Preserves all existing backend query capabilities

### 2.3 Ranked list and "Your Position"

- Remove podium entirely
- Keep one consistent ranked-list metaphor for all positions
- Add an optional compact "Your Position" card above the list for fast self-orientation
- Keep current user highlight (`You`) in-row with a subtle badge and calm highlight
- Top 3 differentiation is lightweight (rank tint and medal iconography only), not layout-breaking

### 2.4 Motion

- "Your Position" card enters with subtle fade/slide when available
- List diffs animate position/opacities when category/filter changes
- Pull-to-refresh and loading states retain shimmer but with calmer timings

## 3) Track view redesign (HUD feel, no gimmicks)

Primary file:

- `ios/FastTrack/FastTrack/Views/ContentView.swift`

Supporting:

- `ios/FastTrack/FastTrack/DesignSystem.swift`
- `ios/FastTrack/FastTrack/Views/SharedComponents.swift`

### 3.1 State-aware layout

Idle and recording become more distinct:

- Idle: calmer map-forward state with minimal instrumentation and clear start CTA
- Recording: HUD-forward state with active speed hero and compact live metrics

### 3.2 Speed hero

- Introduce animated speed arc/ring behind numeric speed value
- Keep monospaced numeric readout with `numericText` transitions
- Apply active glow only during recording state
- Palette is restrained (primary blue + warm threshold accents), not rainbow-heavy

### 3.3 Live metric strip

- Keep MAX / AVG / TIME / DISTANCE but refine cards as frosted compact blocks
- Bars animate from previous value to new value using standard tokenized motion
- Preserve legibility over map background via stronger contrast rules

### 3.4 Map integration

- Keep map visible in both states
- Reduce heavy dim overlay in recording mode so map context remains visible
- Preserve route, start marker, and user location behavior

### 3.5 Controls

- Retain current Start/Stop semantics and safety disclaimer behavior
- Improve visual affordance without changing control logic/state machine

## 4) Confetti behavior and achievement feedback

Primary files:

- `ios/FastTrack/FastTrack/Views/CarDetailView.swift`
- `ios/FastTrack/FastTrack/Views/Components/ConfettiView.swift`
- `ios/FastTrack/FastTrack/Models/CarDetailData+Derive.swift`

### 4.1 Functional fix

Current issue: confetti appears repeatedly on revisit.

Target behavior:

- One-shot celebration for newly eligible achievement moments
- Do not replay every time car detail is opened for the same achievement window

### 4.2 UX replacement after one-shot

- Replace repeated confetti with subtle badge/glow on relevant achievement card/section
- Maintain delight without visual fatigue

## 5) Deferred crop/zoom migration (captured follow-up)

Current custom cropper is clunky; migration to a mature third-party tool is desired but deferred to avoid widening this overhaul.

Follow-up spec/plan will select and integrate a library with:

- Stable pinch/pan gesture handling
- Configurable aspect ratios (avatar vs car)
- Better output quality than current `ImageRenderer` path

## Data flow and compatibility

- No backend contract changes required for this overhaul
- Leaderboard API usage remains unchanged; only presentation and client-side filter UX changes
- Track drive recording and upload flow remain unchanged
- Confetti eligibility logic remains additive; behavior gating is client-side state/trigger logic

Backward compatibility impact: none expected for API contracts and persisted server data.

## Error handling and edge cases

Leaderboard:

- Keep existing loading/error/empty states
- Bottom-sheet filter apply should gracefully handle no-results states

Track:

- Preserve current GPS quality states and fallback messaging
- Animations should degrade gracefully when values unavailable

Confetti:

- If one-shot state cannot be resolved, fail safe to no confetti replay

## Testing strategy

### Unit tests

- Leaderboard filter-state reducer/presenter logic (summary text, apply/clear behavior)
- Confetti one-shot gating logic (new tests around replay prevention)

### UI/state tests

- SocialView transitions between category/scope/period with sheet interactions
- Track view idle -> recording transitions keep controls and metric values correct

### Snapshot/manual verification

- iPhone small and large simulator sizes
- Light and dark color schemes
- Dynamic type at least default + one larger size
- Verify no emoji placeholders in redesigned surfaces
- Verify restrained palette (no rainbow gauge defaults)

## Implementation phases

1. Shared foundation tokens/modifiers/components
2. Leaderboard redesign (unified ranked list + quick filters + lightweight car filter sheet)
3. Track HUD redesign (state-aware + speed hero + refined metric strip)
4. Confetti one-shot + subtle post-celebration indicator
5. Final polish pass and regression checks

## Success criteria

1. Users can read leaderboard faster with less persistent filter clutter
2. Track screen feels more immersive and responsive while preserving clarity
3. Visual language is cohesive across major tabs (motion, surfaces, accents)
4. Confetti no longer repeats on every car profile visit
5. No regression in core flows (drive recording, leaderboard loading, profile navigation)

## Default interaction decisions

1. Scope and period quick filters auto-apply immediately on tap (single-interaction changes)
2. Podium is removed; leaderboard uses a unified ranked list with optional "Your Position" card
3. Car make/model filter is the only sheet-based filter and applies as the user submits text
4. Post-confetti subtle indicator lives in the achievements strip (not duplicated in header)
