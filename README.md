# FastTrack

A self-hosted iOS performance drive tracker with a Go/PostgreSQL backend.

## Features

- Real-time GPS tracking and route capture
- Per-drive stats (speed, acceleration, distance, duration)
- Drive history and analytics
- Social profiles, follow system, leaderboard
- Apple Sign In + Google Sign In with JWT auth
- Backend-served public pages (`/`, `/privacy`, `/terms`)

---

## Repository Architecture

| Area | Purpose | Source of truth |
|---|---|---|
| `backend/` | Go API, backend-served public pages, Kubernetes manifests/overlays | Backend runtime + deploy configuration |
| `ios/FastTrack/` | iOS app project and release config | Mobile app release surface |
| `.github/workflows/` | CI/CD, release automation, deployment gates | Canonical automation path |
| `scripts/` | Operational helper scripts (manual/local workflows) | Secondary/manual tooling |
| `docs/` | Runbooks for development, release, deploy, operations | Human-operational guidance |
| `website/` | Legacy static assets (deprecated) | Historical only |

## Quick Start — Backend

### Local development

```bash
cd backend
export DATABASE_URL="host=localhost user=postgres dbname=fasttrack port=5432 sslmode=disable"
export JWT_SECRET="$(openssl rand -base64 32)"
export BASE_URL="http://localhost:8080"
go run ./cmd/server
```

### Deployment

The canonical deployment path is GitHub Actions:

- [`backend-deploy.yml`](.github/workflows/backend-deploy.yml)
- Staging namespace: `fasttrack-staging`
- Production namespace: `fasttrack-production` (manual environment gate)

Manual/local helper scripts are in [`scripts/`](scripts/README.md).

## Quick Start — iOS

1. Open `ios/FastTrack/FastTrack.xcodeproj` in Xcode
2. Configure signing in **Signing & Capabilities**
3. Build and run on a physical device

See [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) for full setup.

---

## Backend Environment Variables

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | Yes | PostgreSQL DSN |
| `JWT_SECRET` | Yes | JWT signing secret |
| `APPLE_APP_BUNDLE_ID` | Yes | Allowed iOS app bundle IDs for Apple auth |
| `APPLE_TEAM_ID` | Apple revocation flow | Apple developer team ID |
| `APPLE_KEY_ID` | Apple revocation flow | Sign in with Apple key ID |
| `APPLE_PRIVATE_KEY` | Apple revocation flow | Sign in with Apple private key (`.p8` contents) |
| `BASE_URL` | Yes | Public API base URL for the active environment |
| `GOOGLE_CLIENT_ID` | Google auth | Google OAuth client ID allowlist/fallback |
| `GOOGLE_CLIENT_SECRET` | Google auth | Google OAuth client secret |
| `PORT` | No | API listen port (default `8080`) |

---

## Documentation

- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md)
- [`docs/RELEASING.md`](docs/RELEASING.md)
- [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md)
- [`docs/DATABASE.md`](docs/DATABASE.md)
- [`docs/OBSERVABILITY.md`](docs/OBSERVABILITY.md)
