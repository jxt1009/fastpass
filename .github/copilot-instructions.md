# FastTrack Copilot Instructions

## Build, test, and lint commands

### Backend (`backend/`)

```bash
cd backend

# Build
CGO_ENABLED=1 go build ./...

# Closest thing to linting used in CI
CGO_ENABLED=1 go vet ./...

# Full test suite
go test ./... -v -timeout 60s

# Run one backend test
go test ./... -run TestGenerateAndValidateJWT -v
```

The backend runs against PostgreSQL in normal development, but the handler tests in `handlers_test.go` use in-memory SQLite. Use `backend/main.go` and the GitHub Actions workflow as the source of truth for runtime vs. test setup.

### iOS app (`ios/FastTrack/`)

```bash
cd ios/FastTrack

# CI/local build prep
cp FastTrack/Secrets.swift.template FastTrack/Secrets.swift

# Build for testing without signing
xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO

# Run the full iOS test suite
xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO

# Run one iOS test
xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/DriveCalculationTests/testAvgSpeed_EmptyReadings \
  CODE_SIGNING_ALLOWED=NO
```

There is also a Fastlane test lane:

```bash
cd ios/FastTrack
bundle exec fastlane test
```

Always recreate `FastTrack/Secrets.swift` from `FastTrack/Secrets.swift.template` in ephemeral environments; `Secrets.swift` is gitignored and should not be committed.

## High-level architecture

FastTrack is two deployable pieces in one repo:

1. `backend/` is a Go API using Gin + GORM + PostgreSQL. `main.go` wires structured logging, request IDs, Prometheus metrics, avatar static file serving, JWT auth routes, and the authenticated `/api/v1` API. The backend also serves the landing page, privacy policy, and terms of service via `public_pages.go`. The data model is centered on `User`, `Drive`, and `Follow`, with GORM auto-migrations done at startup.
2. `ios/FastTrack/FastTrack/` is the SwiftUI app. `LocationManager` fuses GPS + IMU data, `DriveManager` owns the recording state machine and serializes route/stat payloads, and `APIService`/`AuthManager` handle backend sync and auth token lifecycle.

The `website/` directory is vestigial — public pages are now served by the backend. Deployment is workflow-driven: the backend Docker image is built, then applied with Kubernetes manifests under `backend/k8s/` and the staging/production overlays in `backend/k8s/overlays/`.

## Git and release workflow

- `main` is branch-protected. Assume all repository changes go through pull requests; do not plan around direct pushes to `main`.
- **Always use squash merges** for human-authored PRs. The `conventional-commits.yml` workflow lints every commit pushed to `main` via `@commitlint/config-conventional`. A merge-commit merge preserves all branch commits on `main`, and each one is subject to commitlint. Squash merges produce a single commit with the PR title as its message, so only the PR title needs to be valid.
- **Commit message header must not exceed 100 characters.** `@commitlint/config-conventional` enforces `header-max-length: [2, 'always', 100]`. This applies to every commit that lands on `main` — whether it's the squash commit or individual commits from a merge-commit merge. The PR title action (`amannn/action-semantic-pull-request`) only validates the PR title, not individual branch commits; a commit that passes in the PR can still fail on `main` if merged via merge commit.
- Prefer semantic PR titles (`feat: ...`, `fix(scope): ...`, etc.) so the resulting squash commit message is valid. Keep PR titles ≤ 100 characters.
- `release-please` is the source of truth for release PRs and version bumps. It opens or updates the release PR from commits already merged to `main`, and merging that PR creates the `v*` tag.
- The tag-triggered [`release.yml`](workflows/release.yml) workflow creates GitHub Release notes with `git-cliff`; it must not depend on pushing release artifacts back to protected `main`.
- Historical or backfilled tags should be republished via the manual **Release** workflow dispatch with a `tag` input rather than by pushing an old tag again.
- `RELEASE_PLEASE_TOKEN` must remain a PAT or GitHub App token instead of `GITHUB_TOKEN`, because downstream tag workflows need to trigger from the release tag push.

### Fixing a commitlint failure on `main`

If a commit with an invalid conventional commit message (e.g. header > 100 chars, bad type) lands on `main` via a merge-commit merge, the fix requires a PR that reverts the bad merge and re-introduces the changes with a clean commit:

1. Create a branch from `main`.
2. `git revert -m 1 <merge-hash> --no-edit` — revert the merge (use `-m 1` to keep main as the primary parent).
3. `git commit --amend -m "revert: <description>"` — give the revert a valid message.
4. Re-apply the original changes and commit with a valid conventional message (≤ 100 chars).
5. Push the branch and open a PR. **Use squash merge** when merging the fix PR.

## Key conventions

- The backend JSON contract is snake_case, and the iOS models mirror it with explicit `CodingKeys`. When adding or renaming API fields, update both sides together.
- User profile data is intentionally split across legacy single-car fields and newer garage sync fields. `User.Garage`, `selected_car_id`, `car_stats_data`, `unit_system`, and `color_scheme` are stored as text/blob-like fields on the backend and decoded manually on iOS. If you touch profile or garage flows, preserve backward compatibility instead of deleting the legacy fields outright.
- `Drive.route_data` is a versioned JSON blob, not normalized relational data. `DriveManager` writes route/event payloads, and downstream readers in views/models parse that blob. Any route format change must be applied across the recorder and every parser.
- Sign-in and token refresh are also data-restore events. `AuthManager` calls `restoreUserDataFromServer(...)` after auth so profile, garage, car stats, avatar, and display settings come back onto the device; keep that behavior intact when editing auth flows.
- `backend/jwt.go` is the source of truth for token behavior. If you change token lifetimes or auth semantics, reconcile `README.md`, tests, and client expectations in the same change.
- The API assumes request ID + structured logging + Prometheus metrics middleware on every request. Preserve `X-Request-ID`, `request_id` log fields, and `/metrics` scraping behavior when editing server startup or middleware.
