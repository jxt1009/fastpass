# FastPass - Speed Tracking App 🚗💨

A speed tracking iOS app (TripRank-style) that accurately tracks drives/trips and syncs to a cloud backend.

## Project Structure

```
triprank/
├── backend/           # Go backend API
│   ├── main.go, models.go, handlers.go
│   ├── Dockerfile
│   ├── k8s/          # Kubernetes manifests
│   └── triprank-api  # Compiled binary
└── ios/
    └── FastPass/     # iOS SwiftUI app
        ├── FastPass/ # App source code (8 files)
        ├── SETUP.md  # Integration guide
        └── check-integration.sh
```

## Tech Stack

- **iOS**: SwiftUI, Core Location (iOS 18+)
- **Backend**: Go, Gin framework, PostgreSQL, GORM
- **Deployment**: Kubernetes cluster
- **API**: RESTful JSON API

## Quick Start

### For iOS Development

```bash
cd ios/FastPass
./check-integration.sh   # Verify files are ready
# Then follow SETUP.md for Xcode configuration
```

### For Backend Deployment

```bash
cd backend
# See DEPLOYMENT.md for Kubernetes instructions
# Or run locally with PostgreSQL:
./triprank-api
```
