# Public Social Mirror via Thin No-Auth SPA + High-Value App Features Plan

**Date:** 2026-05-31  
**Branch:** `feat/public-social-mirror-thin-spa` (worktree at `.worktrees/public-social-mirror`)  
**Status:** Phase 1 complete (SPA scaffolded at `website/spa/`, FastTrack theme + nav + CTAs ported, static build verified). Starting implementation of public social features (Leaderboard first).

## Progress

- [x] Worktree created + plan artifact
- [x] Thin Svelte 5 SPA scaffolded in `website/spa/` (minimal + TS + Tailwind + static adapter)
- [x] FastTrack dark theme, sticky nav, and strong app CTAs ported
- [x] Home page is a clean public social discovery landing
- [x] Public Leaderboard page (filters + table using live API)
- [x] Public profile pages + dynamic follower/following lists
- [ ] Public "Find People" search
- [ ] Backend serving + redirects from old template routes
- [ ] Docs + PR

## Context & Revised Scope (from user feedback)

The original request was to mirror social aspects of the iOS app (profiles, following, leaderboard, search) to the website, plus brainstorm high-value (non-gimmick) features for the app.

**Key decisions after iteration (no login/auth on web):**
- **Completely drop** any web login, OAuth, cookies, sessions, or authenticated flows on the website. This avoids significant complexity (web Apple/Google flows, client IDs, revocation, cookie middleware, security surface).
- Web remains a **secondary, public-only marketing + discovery surface** (mobile app is the primary experience).
- "Social mirror" = richer **public** social discovery using only existing public/optional-auth API endpoints:
  - Dynamic follower/following lists on public profiles (currently static in templates; iOS has the endpoints but never calls them).
  - Public user search / "Find People" UI.
  - Enhanced public leaderboard + profiles.
  - Clear messaging that personalized "Following" scope + full social requires the app.
  - Strong CTAs driving downloads / TestFlight.
- Deliver via a **thin public (no-auth) SPA** in the `website/` directory (reviving the vestigial dir as a lightweight static frontend for social pages).
- SPA uses a **light modern small framework** (Svelte / SvelteKit SPA mode or Astro recommended for tiny bundles + great DX).
- SPA becomes the **primary public social experience** (`/leaderboard`, `/u/:username`, search).
- Current Go templates (`backend/templates/`, `public_pages.go`, `web_handlers.go`) stay **only** for:
  - Home (`/`), Privacy, Terms.
  - Basic crawlers/SEO fallbacks + simple redirects for old social routes.
- Backend changes are **minimal** (serve SPA static assets for same-origin, optional tiny CORS, update links + redirects). No new auth, no new social logic.
- High-value app feature brainstorm (iOS-focused) is included with prioritized list + actionable sketches for top 3 (leveraging existing rich route data, events, Follow graph, analytics heuristics).

This keeps changes surgical, respects "prioritize mobile", eliminates the heavy auth lift, and still delivers real user value on the public web surface (better discovery of the social features that already exist in the app + backend).

## Assumptions & Tradeoffs

- **No auth on web ever in this plan.** Follow/unfollow, personalized leaderboards, private data, etc. remain iOS-only.
- **Thin SPA** = small bundle (<100-150 KB gzipped ideal), client-side routing for nice UX on public pages, direct fetches to the public FastTrack API (`https://fast.toper.dev/api/v1`).
- Serving strategy (chosen for simplicity/single deploy surface): Build SPA to static files; backend serves them (extend existing `/static` handling or mount under social paths). Alternative: re-enable/adapt lightweight static hosting for `website/` output.
- Framework: Svelte (or SvelteKit static/SPA) preferred for "light modern + thin". Astro as strong alternative. Avoid heavy React/Next unless justified.
- Existing public data model unchanged (everything gated by `user.is_public`).
- iOS unaffected except possible low-effort parity (wiring the unused follower/following list endpoints).
- Drive visibility/sharing is **out of scope** here (would require new privacy model + backend work; can be future brainstorm item).
- All work follows repo conventions: worktree, conventional commits (≤100 char header), squash-merge PRs via `gh`, release-please, full test/build/lint verification before PR.
- Plan file is the source of truth and will be updated at each milestone.

**Tradeoffs accepted:**
- New (small) build step for website/ SPA vs pure in-place edits to current vanilla templates/JS.
- One additional frontend surface to maintain (but very narrow: public social discovery only).
- SPA routing means old template social pages become redirects/fallbacks.

## Recommended Tech for Thin SPA

- **Framework:** Svelte 5 (runes) + Vite, or SvelteKit with static adapter (SPA mode). Extremely small output, excellent TypeScript support, great for data-driven UIs like leaderboards/profiles.
- **Styling:** Tailwind (via Vite plugin) or copy/adapt the existing dark theme from `backend/static/css/app.css` for visual consistency (preferred for minimalism).
- **Routing:** Client-side (SvelteKit file-based or tiny router).
- **Data:** Vanilla `fetch` to public API endpoints. No state management beyond Svelte stores for filters/search.
- **Assets:** Avatars served from backend `/uploads`.
- **Build output:** Static files (`dist/` or `build/`) served by backend.

Alternative if we want even thinner later: pure vanilla + history API + minimal bundling.

## Part 1: Thin Public SPA — Social Mirror Implementation

### Verifiable Goals for Part 1
- Public users can discover other drivers via search.
- Public profiles show live, clickable follower/following lists.
- Leaderboard is fully functional in SPA with clear "use the app for personalized Following scope" messaging.
- Strong, repeated CTAs to the mobile app.
- SPA is fast, mobile-friendly, and visually consistent with the brand.
- Old social template routes gracefully redirect or fallback.
- Zero impact on iOS or authenticated backend flows.
- Single deploy surface (SPA assets served from backend).

### Detailed Phases

#### Phase 0 — Setup (this worktree + plan)
- [x] `git worktree add -b feat/public-social-mirror-thin-spa .worktrees/public-social-mirror main`
- [ ] Create this plan file in `docs/plans/2026-05-31-public-social-mirror-thin-spa-and-high-value-features.md` (first commit).
- [ ] Update todo list / status.
- [ ] Confirm stack (Svelte) and serving approach with any final quick questions if needed.

#### Phase 1 — Scaffold Thin SPA in `website/`
- Initialize Svelte (or chosen light framework) project inside `website/` (or `website/social-spa/` subdir for cleanliness).
- Set up TypeScript, minimal routing, Tailwind (or ported CSS vars/theme).
- Configure build to output pure static assets.
- Add basic layout matching FastTrack dark theme.
- Add simple "Get the App" components / CTAs (TestFlight email + future App Store link).
- **Success check:** `npm run build` produces clean static output; can be manually served.

#### Phase 2 — Core Public Social Features (using existing API)
- Public Leaderboard view (reuse filter logic from current `app.js`; fetch `/api/v1/leaderboard` with all params; "Following" scope shows global + banner).
- Public Profile view (`/u/:username`): avatar, stats, garage (JSON), dynamic followers list (fetch `/api/v1/users/:username/followers`), following list, links to other profiles.
- Public Search / Find People: input → debounce → fetch `/api/v1/users/search`, results link to profiles.
- Basic error/loading/skeleton states (match iOS quality where reasonable).
- **Success check:** All three surfaces work end-to-end against production public API (no login required); lists are live and navigable.

#### Phase 3 — Polish, Messaging, CTAs, Integration
- "Following scope" education + prominent mobile app CTAs on every social page.
- Mobile responsiveness (the current templates are already decent; make SPA better).
- Client-side routing + nice URLs.
- Redirects/fallbacks: backend changes to point old `/leaderboard` and `/u/*` to SPA (or serve SPA index for those paths) + basic HTML fallback for crawlers.
- Update home page (current `public_pages.go`) to link to the new social SPA surface.
- Visual consistency with existing brand (colors, typography, avatar fallbacks).
- **Success check:** Beautiful public discovery experience; clear path from web → app; no broken old links for casual visitors.

#### Phase 4 — Backend Serving + Minimal Glue
- Extend backend static serving (or add dedicated handler) to serve the SPA's built assets under the social routes (same origin preferred).
- Optional: tiny CORS header if SPA ends up on different origin during development.
- Update any marketing links.
- **Success check:** SPA loads from the same domain the API is on; old template social pages no longer render the heavy Go templates for social paths.

#### Phase 5 — Docs, Cleanup, Verification, PR
- Update `README.md`, `docs/DEVELOPMENT.md`, any deployment notes.
- Note in `website/README.md` that it now hosts the thin public social SPA.
- Full verification (see below).
- Conventional commit(s), rebase on main, push from worktree, `gh pr create`.
- Merge via squash (per repo rules).

## Part 2: Brainstorm — High-Value (Non-Gimmick) Features for the iOS App

(See research for full rationale: all ideas leverage the already-captured rich v2 route data (points + events), physics (G-force, accel, maneuvers), car garage, Follow graph, existing analytics heuristics, and current social surface. No new sensors or vanity mechanics.)

### Prioritized List (Value > Effort)
1. Event timeline + scrubber jump in DriveDetailView (highest immediate "learning" value).
2. Personal drive comparisons + "similar drives" finder (self-improvement from your own data).
3. Normalized technique trends in Analytics (real progress signals like brakes per 100 mi, smoothness).
4. Activate dead-but-useful code (CarStats comparisons, PerformanceMetrics bits).
5. Lightweight private share cards (image export of replay + stats).
6. Light follower activity feed (opt-in aggregates from people you follow).
7. Opt-in per-drive publish (future, with new privacy model).

### Top 3 + High-Level Phased Sketches (Ready for Future Work)
**1. Event timeline + jump (DriveDetailView.swift + existing RouteEvent parsing)**
- Phase A (1-2 days): Add sorted List of events below the replay map (icon + "Brake at 42 mph, 0.8G"). Tap sets `playbackProgress`.
- Phase B: Persist simple user notes on events.
- Verifiable: Uses already-parsed v2 data + existing replay engine. Add tests.

**2. Personal comparisons + similar-drives finder**
- Phase A: On drive detail, compute on-the-fly similar historical drives (distance/duration ±20%) and show deltas (brakeEvents, smoothnessScore, best060 vs your avg).
- Phase B: Car-filtered "vs my best on similar route".
- Phase C (social): Light comparison against public aggregates of followed users.
- Value: Turns rich personal data into actionable coaching.

**3. Technique trends in Analytics**
- Phase A: Extend metric picker + breakdowns with normalized metrics (brakes/100 mi, avg peak G, smoothness trend) using existing fields + heuristics.
- Phase B: Per-car views + "insights" callouts ("Your braking improved 18%").
- Value: Real technique improvement signal (far more motivating than raw leaderboards).

These are surgical, build directly on existing code (DriveManager+Processing, AnalyticsModels, PerformanceMetrics stubs, SocialModels, etc.), and can be done independently of the web SPA work.

## Full Verification Checklist (before every PR)
- Backend: `CGO_ENABLED=1 go build ./... && go vet ./... && go test ./... -v -timeout 60s`
- iOS: `xcodebuild build-for-testing ...` + full test suite or targeted social/drive tests (CODE_SIGNING_ALLOWED=NO)
- SPA: `npm run build` + manual serve + public API flows (no auth)
- Manual: Public discovery works on mobile + desktop; CTAs present; old routes handled gracefully.
- No regressions in home/privacy/terms or any authenticated iOS flows.
- Lint / typecheck clean.
- Plan file updated with milestone status.

## Risks & Mitigations
- SPA framework choice: Mitigated by picking "light modern" (Svelte) + keeping surface very narrow.
- Serving story: Prefer backend mount (single deploy). Document clearly.
- Scope creep: This plan explicitly excludes auth and drive sharing.
- Maintenance of two social surfaces temporarily: Short-lived (templates become thin fallbacks quickly).

## Next Immediate Steps (after plan creation)
1. Scaffold SPA (Phase 1).
2. Implement core social features (Phase 2).
3. Iterate with user on exact framework details if needed.
4. Keep this plan updated.

---

**This plan is the canonical artifact.** Update it at every major milestone. All work happens in the dedicated worktree. Let's deliver maximum public discovery value with minimal complexity and strong drive-to-app CTAs.

Status: Plan created. Ready for Phase 1 scaffolding.