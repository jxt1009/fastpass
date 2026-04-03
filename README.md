# FastTrack

A self-hosted iOS performance drive tracker. Real-time GPS speed tracking, live maps, drive statistics, and social features — backed by a Go/PostgreSQL API deployed at [fast.toper.dev](https://fast.toper.dev).

## Features

- **Real-time GPS tracking** — speed, distance, route polyline on a live map
- **Drive statistics** — max/min/avg speed, 0–60 time, g-force, acceleration/braking events
- **Drive history** — full route replay and per-drive stats
- **Car garage** — track multiple cars; stats tied to each vehicle
- **Social** — public profiles, follow system, leaderboard
- **Analytics** — charts and insights across all drives
- **Apple Sign In + Google Sign In** — JWT-based auth (24h access / 30d refresh)
- **Cloud sync** — drives, profile, display preferences synced to backend
- **Background location** — continues tracking with screen off

---

## Repo Structure

```
fasttrack/
├── backend/                     # Go API (Gin + GORM + PostgreSQL)
│   ├── main.go                  # Router setup, DB init
│   ├── auth_models.go           # User, auth request/response types
│   ├── models.go                # Drive, Follow types
│   ├── auth_handlers.go         # Apple Sign In, token refresh
│   ├── google_auth.go           # Google OAuth handler
│   ├── handlers.go              # Drive CRUD, profile, stats, social
│   ├── social_handlers.go       # Follow, leaderboard, search
│   ├── jwt.go                   # JWT generation + Apple token verification
│   ├── middleware.go            # Auth middleware
│   ├── Dockerfile
│   └── k8s/                     # Kubernetes manifests
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       ├── postgres.yaml        # Independent PostgreSQL instance
│       ├── postgres-hostpath.yaml
│       └── backup-cronjob.yaml
├── ios/FastTrack/FastTrack/      # iOS SwiftUI app
│   ├── FastTrackApp.swift
│   ├── Models/Drive.swift
│   ├── Views/                   # ContentView, DriveHistoryView, DriveDetailView,
│   │                            #   SignInView, SocialView, ProfileView,
│   │                            #   AnalyticsView, AchievementsView, SettingsView, …
│   ├── ViewModels/DriveManager.swift
│   └── Services/                # LocationManager, APIService, AuthManager,
│                                #   AppleSignInManager
├── deploy-local.sh              # One-shot K8s deploy (run on server)
├── deploy-to-toper.sh           # Deploy from Mac via SSH
└── backup-restore.sh            # Database backup management
```

---

## Quick Start — Backend

### Prerequisites (on server)
- Docker + kubectl
- Kubernetes cluster with nginx-ingress and cert-manager

### Deploy
```bash
# On the server (10.0.0.102)
git clone https://github.com/jxt1009/fasttrack.git
cd fasttrack
./deploy-local.sh
```

The script builds the Docker image, creates K8s secrets (auto-generates JWT), deploys PostgreSQL, deploys 2 API replicas, and configures ingress for `fast.toper.dev`.

### Verify
```bash
curl https://fast.toper.dev/health
# {"status":"ok"}
```

### Local dev (no Kubernetes)
```bash
cd backend
export DATABASE_URL="host=localhost user=postgres password=postgres dbname=fasttrack port=5432 sslmode=disable"
export JWT_SECRET="$(openssl rand -base64 32)"
go run .
```

---

## Quick Start — iOS

1. Open `ios/FastTrack/FastTrack.xcodeproj` in Xcode
2. In **Signing & Capabilities**, add:
   - **Sign in with Apple**
   - **Background Modes** → check **Location updates**
3. In **Info** tab, add:
   - `Privacy - Location When In Use Usage Description`
   - `Privacy - Location Always and When In Use Usage Description`
4. Select your team for signing
5. Build and run on a physical device (`Cmd+R`)

See [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) for full Xcode setup.

---

## Environment Variables

| Variable | Required | Description |
|---|---|---|
| `DATABASE_URL` | Yes | PostgreSQL DSN (e.g. `host=... user=fasttrack password=... dbname=fasttrack port=5432 sslmode=disable`) |
| `JWT_SECRET` | Yes | Random secret for signing JWTs. Generate: `openssl rand -base64 32` |
| `APPLE_APP_BUNDLE_ID` | Yes | Bundle ID for Apple token verification (e.g. `com.toper.FastTrack`) |
| `BASE_URL` | Yes | Public API base URL (e.g. `https://fast.toper.dev`) — used in auth callbacks |
| `GOOGLE_CLIENT_ID` | For Google auth | Google OAuth client ID |
| `GOOGLE_CLIENT_SECRET` | For Google auth | Google OAuth client secret |
| `PORT` | No | API listen port (default: `8080`) |

Secrets are stored in Kubernetes secrets (`fasttrack-secrets`), never in source code.

---

## API Overview

**Base URL**: `https://fast.toper.dev`

| Group | Endpoints |
|---|---|
| Health | `GET /health` |
| Auth (public) | `POST /api/v1/auth/apple`, `POST /api/v1/auth/google`, `POST /api/v1/auth/refresh` |
| User | `GET /api/v1/me`, `PUT /api/v1/profile`, `PUT /api/v1/profile/avatar` |
| Car stats | `GET /api/v1/stats`, `PUT /api/v1/stats` |
| Display settings | `PUT /api/v1/display-settings` |
| Drives | `POST/GET /api/v1/drives`, `GET/PUT /api/v1/drives/:id` |
| Social | `GET /api/v1/users/search`, `GET /api/v1/leaderboard`, `GET /api/v1/users/:username`, `POST/DELETE /api/v1/users/:username/follow`, `GET /api/v1/users/:username/followers`, `GET /api/v1/users/:username/following` |
| Static | `GET /uploads/*` (avatars) |

All `/api/v1/*` routes except auth require a `Authorization: Bearer <jwt>` header.

---

## Tech Stack

| Component | Technology |
|---|---|
| iOS | Swift + SwiftUI, iOS 18+, MapKit, Core Location |
| Backend | Go 1.21+, Gin, GORM |
| Database | PostgreSQL 15 |
| Auth | Apple Sign In + Google OAuth + JWT |
| Deployment | Kubernetes (single-node), Docker |
| SSL | Let's Encrypt via cert-manager |
| Backups | K8s CronJob (daily, 2 AM UTC, 30-day retention) |

---

## Common Operations

```bash
# View API logs
kubectl logs -f deployment/fasttrack-api

# Restart API
kubectl rollout restart deployment/fasttrack-api

# Update (pull + redeploy)
cd ~/fasttrack && git pull && ./deploy-local.sh

# Create database backup
./backup-restore.sh backup

# Connect to database
kubectl exec -it deployment/fasttrack-postgres -- psql -U fasttrack -d fasttrack
```

---

## Documentation

- [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) — Server deployment, DNS, SSL, scaling
- [`docs/DATABASE.md`](docs/DATABASE.md) — Database management, backups, restore
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) — Xcode setup, local dev, Apple/Google Sign In
