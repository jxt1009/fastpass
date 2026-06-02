# 2026-06-01 — Web SPA fixes: homepage routing, profile nav, leaderboard transitions

## Context

Three related UX bugs on the public social web (`/leaderboard`, `/u/:username`, `/`):

1. **Logo on the SPA dumps users onto a different homepage.** The SPA layout's logo
   (`website/spa/src/routes/+layout.svelte:15`) is `<a href="/">`. The Go backend
   (`backend/internal/app/public_pages.go:284`) intercepts `/` and serves its own
   TestFlight marketing page. The SvelteKit root route
   (`website/spa/src/routes/+page.svelte` — the "Public Discovery" page) is dead
   code because Go's `/` shadows it. Result: clicking the logo on `/leaderboard` or
   `/u/:username` leaves the SPA entirely and reloads a different-looking page.

2. **Clicking a leaderboard row to open a profile feels stuck on loading.**
   `website/spa/src/routes/leaderboard/+page.svelte:146` does
   `window.location.href = ...` — a full page reload. The SPA has to re-bootstrap
   from scratch (re-download JS, re-init router, re-render layout) which feels like
   it's hanging. The fix is SvelteKit's `goto()` from `$app/navigation` for
   client-side routing.

3. **Leaderboard table jumps on category change.** `loading = true` is set
   immediately when a filter pill is clicked, which swaps the table for
   "Loading leaderboard…" and then swaps it back when the new data arrives. The
   "jump" is the disappearance/reappearance of the table. The fix is to keep the
   old table visible during the reload, show a subtle "refreshing" indicator, and
   let the new data replace the old in place.

## Decisions

- **Homepage swap:** Move the Go TestFlight marketing page from `/` to `/app`, and
  add `/` to the SPA fallback routes. The SvelteKit root route becomes the real
  homepage. The marketing page keeps the same content (hero, features strip,
  TestFlight CTA) at a new URL; the SPA root already has a TestFlight CTA of its
  own for first-time visitors.

  - Path chosen: `/app` (short, implies "the app page"; matches the
    `fast.toper.dev` branding the SPA footer already links to).
  - Privacy and Terms pages keep their existing footers — their `<a href="/">`
    links will now go to the SPA root, which is the correct "home" behavior.

- **Profile row click:** Use `goto()` from `$app/navigation`. One-line behavior
  change plus an import.

- **Leaderboard transitions:**
  - On the first load (no data yet), show "Loading leaderboard…" as before.
  - On subsequent loads (filter change while data is already on screen), keep
    the table visible with a small "Refreshing…" badge and reduced opacity. When
    the new data arrives, the rows update in place. The rows are keyed by
    `entry.username` so the same driver stays in the same row across category
    changes when possible.

## Files

- `backend/internal/app/public_pages.go` — move `/` → `/app`
- `backend/internal/app/routes_public.go` — add `/` to SPA fallback
- `website/spa/src/routes/leaderboard/+page.svelte` — `goto()` import + row
  click, split `loading` into `loading` (initial) and `refreshing` (subsequent),
  add keyed `{#each}`, add refreshing badge + CSS
- `docs/plans/2026-06-01-web-spa-fixes.md` — this plan

## Verification

1. Backend: `cd backend && CGO_ENABLED=1 go build ./...` and
   `CGO_ENABLED=1 go vet ./...`.
2. Backend tests: `cd backend && go test ./... -timeout 60s`.
3. SPA typecheck: `cd website/spa && npm run check` (or the closest equivalent
   given the local node setup).
4. Manual smoke: `curl -I http://localhost:8080/` should now return the SPA
   `index.html` shell; `curl -I http://localhost:8080/app` should return the
   marketing HTML with `content-type: text/html`. (Optional — only if a dev
   server is running.)
