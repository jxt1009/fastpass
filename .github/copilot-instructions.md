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

### Website (`website/`)

```bash
# Container build used by deploy workflow
docker build -t fasttrack-web ./website
```

## High-level architecture

FastTrack is three deployable pieces in one repo:

1. `backend/` is a Go API using Gin + GORM + PostgreSQL. `main.go` wires structured logging, request IDs, Prometheus metrics, avatar static file serving, JWT auth routes, and the authenticated `/api/v1` API. The data model is centered on `User`, `Drive`, and `Follow`, with GORM auto-migrations done at startup.
2. `ios/FastTrack/FastTrack/` is the SwiftUI app. `LocationManager` fuses GPS + IMU data, `DriveManager` owns the recording state machine and serializes route/stat payloads, and `APIService`/`AuthManager` handle backend sync and auth token lifecycle.
3. `website/` is a static nginx container serving the landing page plus `/privacy` and `/terms`.

Deployment is workflow-driven: backend and website images are built separately, then applied with Kubernetes manifests under `backend/k8s/` and the staging/production overlays in `backend/k8s/overlays/`. The production ingress is shared between the API and website deployment flow.

## Key conventions

- The backend JSON contract is snake_case, and the iOS models mirror it with explicit `CodingKeys`. When adding or renaming API fields, update both sides together.
- User profile data is intentionally split across legacy single-car fields and newer garage sync fields. `User.Garage`, `selected_car_id`, `car_stats_data`, `unit_system`, and `color_scheme` are stored as text/blob-like fields on the backend and decoded manually on iOS. If you touch profile or garage flows, preserve backward compatibility instead of deleting the legacy fields outright.
- `Drive.route_data` is a versioned JSON blob, not normalized relational data. `DriveManager` writes route/event payloads, and downstream readers in views/models parse that blob. Any route format change must be applied across the recorder and every parser.
- Sign-in and token refresh are also data-restore events. `AuthManager` calls `restoreUserDataFromServer(...)` after auth so profile, garage, car stats, avatar, and display settings come back onto the device; keep that behavior intact when editing auth flows.
- `backend/jwt.go` is the source of truth for token behavior. If you change token lifetimes or auth semantics, reconcile `README.md`, tests, and client expectations in the same change.
- The API assumes request ID + structured logging + Prometheus metrics middleware on every request. Preserve `X-Request-ID`, `request_id` log fields, and `/metrics` scraping behavior when editing server startup or middleware.
