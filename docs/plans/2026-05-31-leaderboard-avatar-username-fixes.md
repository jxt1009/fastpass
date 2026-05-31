# Fix: leaderboard loading, avatar 404, and @ prefix consistency

## Background

Three user-facing issues were reported after the recent backend refactoring (split
into `cmd/internal` layout) and iOS app-state refactoring (`@ObservedObject` →
`@EnvironmentObject`):

1.  **Leaderboard not loading in the iOS app** — API works fine on the website,
    but the iOS Social tab doesn't display data.
2.  **Avatar images returning 404 on the website** — The profile page at
    `fast.toper.dev/u/james` shows a broken image for
    `/uploads/avatars/1.jpg`.
3.  **Missing `@` prefix on usernames** — The website uses `@username` on
    profile pages, but the iOS app shows bare usernames in several places.

## Root causes and changes

### 1. Docker WORKDIR mismatch → avatar 404

**Root cause**: The Docker runtime stage sets `WORKDIR /root/`, so the code's
relative path `./uploads` resolves to `/root/uploads/`. However, the K8s
deployment mounts the persistent volume at `/app/uploads`. The static file
server (`r.Static("/uploads", "./uploads")`) looks in `/root/uploads/`, but the
volume is at `/app/uploads/` — they never meet.

**Fix**: Changed `WORKDIR /root/` to `WORKDIR /app` in the Dockerfile so that
`./uploads` resolves to `/app/uploads`, matching the volume mount.

### 2. Leaderboard not loading (investigation)

The leaderboard API endpoint (`/api/v1/leaderboard`) returns valid JSON and
works from the website. The iOS app's `APIService` constructs the correct URL
(`https://fast.toper.dev/api/v1/leaderboard?category=...`).

The `SocialView` was recently changed from `@ObservedObject` to
`@EnvironmentObject` for `ProfileManager`. Environment objects are correctly
injected in `FastTrackApp`. The iOS build and all tests pass.

**If the issue persists**, check:
- Whether the TestFlight build has been updated to include the latest commits.
- Whether the device has a valid network connection to `fast.toper.dev`.
- Whether an expired auth token is causing the request to fail (the leaderboard
  API uses `optionalAuthMiddleware`, which should still return data).

### 3. `@` prefix added to usernames

The following iOS views now display `@username` instead of bare `username`:

- **SocialView.swift** (leaderboard row): `Text("@\(entry.username)")`
- **FindPeopleView.swift** (search results): `Text("@\(result.username)")`
- **ProfileView.swift** (own profile header):
  `Text(profileManager.profile.map { "@\($0.username)" } ?? "Set up profile")`
- **PublicProfileView.swift**: already had `@` on the main display; no change needed.
- **AppStoreScreenshotMode.swift** (mock leaderboard): `Text("@\(entry.username)")`

Navigation titles and API calls continue to use bare usernames (no `@` needed
for those contexts).

## Verification

- [x] iOS app builds and all tests pass
- [x] Backend builds and `go vet` passes
- [x] Leaderboard API returns valid JSON with query params
- [ ] Avatar path works after new Docker image is deployed (requires deploy)
