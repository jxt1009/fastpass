# FastPass - GPS Speed Tracking App 🚗💨

A complete iOS speed tracking application with real-time GPS, live maps, drive statistics, and cloud sync. Like TripRank, but self-hosted!

## ✨ Features

- 📱 **iOS App** - SwiftUI with real-time GPS tracking
- 🗺️ **Live Maps** - See your route as you drive
- 📊 **Drive Statistics** - Max/min/avg speed, distance, time
- 🍎 **Apple Sign In** - Secure authentication
- ☁️ **Cloud Sync** - Go backend with PostgreSQL
- 🔒 **Self-Hosted** - Deploy to your own Kubernetes cluster
- 💾 **Auto Backups** - Daily database backups

---

## 🚀 Quick Deploy to Your Server

```bash
# On your server (10.0.0.102)
cd ~
git clone https://github.com/YOUR_USERNAME/fastpass.git
cd fastpass
./deploy-local.sh
```

**That's it!** The script will:
- Deploy independent PostgreSQL database
- Build and deploy API (2 replicas)
- Configure ingress for fast.toper.dev
- Set up automated daily backups
- Test everything

See **[DEPLOY_ON_SERVER.md](DEPLOY_ON_SERVER.md)** for details.

---

## 📱 iOS App Setup

### 1. Open in Xcode
```bash
open ios/FastPass/FastPass.xcodeproj
```

### 2. Configure (One-Time Setup)
Follow **[XCODE_SETUP.md](XCODE_SETUP.md)**:
- Add files to target
- Enable "Sign in with Apple" capability
- Enable "Background Modes" → "Location updates"  
- Add location permission keys to Info.plist
- Select your team for signing

### 3. Build & Run
- Simulator: Cmd+R (limited GPS simulation)
- Device: Best for real testing with actual GPS

---

## 📚 Documentation

### Quick Start
- **[DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md)** - Complete overview
- **[QUICK_DEPLOY.md](QUICK_DEPLOY.md)** - Quick reference
- **[XCODE_SETUP.md](XCODE_SETUP.md)** - iOS project configuration

### Deployment
- **[DEPLOY_ON_SERVER.md](DEPLOY_ON_SERVER.md)** - Server deployment guide
- **[deploy-local.sh](deploy-local.sh)** - Automated deployment script
- **[deploy-to-toper.sh](deploy-to-toper.sh)** - Deploy from Mac (requires SSH)

### Database
- **[DATABASE_MANAGEMENT.md](DATABASE_MANAGEMENT.md)** - Complete DB guide
- **[backup-restore.sh](backup-restore.sh)** - Backup management script

### Features & Architecture
- **[FEATURES.md](FEATURES.md)** - Feature overview
- **[AUTH_IMPLEMENTATION.md](AUTH_IMPLEMENTATION.md)** - Authentication details
- **[GETTING_STARTED.md](GETTING_STARTED.md)** - Initial setup guide

---

## 🏗️ Architecture

### iOS App (SwiftUI)
```
FastPass.app
├── Views/           # UI components
│   ├── ContentView.swift        # Main tracking screen + live map
│   ├── DriveHistoryView.swift   # List of drives
│   ├── DriveDetailView.swift    # Drive details
│   ├── SignInView.swift         # Apple Sign In
│   └── SharedComponents.swift   # Reusable UI
├── Services/        # Business logic
│   ├── LocationManager.swift    # GPS tracking
│   ├── APIService.swift         # Backend API client
│   ├── AuthManager.swift        # Token management
│   └── AppleSignInManager.swift # Apple auth
├── ViewModels/
│   └── DriveManager.swift       # Drive recording logic
└── Models/
    └── Drive.swift              # Data model
```

### Backend API (Go)
```
fast.toper.dev/
├── /health                      # Health check
├── /api/v1/auth/apple          # Sign in with Apple
├── /api/v1/auth/refresh        # Refresh tokens
├── /api/v1/me                  # User profile (protected)
└── /api/v1/drives              # Drive CRUD (protected)
```

**Stack**: Go + Gin + GORM + PostgreSQL + JWT

### Database (PostgreSQL)
```
fastpass (database)
├── users   # Apple user data
└── drives  # GPS tracks with stats
```

**Independent PostgreSQL** (not shared with other services)
- 20GB data storage
- 10GB backup storage  
- Daily automated backups at 2 AM UTC
- 30-day retention

---

## 🎯 Production Checklist

### Backend Deployment
- [ ] Push code to GitHub
- [ ] SSH to server and clone repo
- [ ] Run `./deploy-local.sh`
- [ ] Configure DNS: `fast.toper.dev` → ingress IP
- [ ] Wait for SSL certificate (5 min)
- [ ] Test: `curl https://fast.toper.dev/health`

### iOS Configuration  
- [ ] Open project in Xcode
- [ ] Add all files to target
- [ ] Enable Sign in with Apple capability
- [ ] Enable Background Modes capability
- [ ] Add location permission keys to Info.plist
- [ ] Select signing team
- [ ] Update API URL if needed
- [ ] Build and test on device

### Verification
- [ ] Backend health check passes
- [ ] Database connection works
- [ ] Backups are scheduled
- [ ] Apple Sign In works
- [ ] Can start/stop recording
- [ ] Map shows live route
- [ ] Drives sync to backend
- [ ] History view loads

---

## 🔧 Common Operations

### View Logs
```bash
kubectl logs -f deployment/fastpass-api
```

### Create Backup
```bash
./backup-restore.sh backup
```

### Restart API
```bash
kubectl rollout restart deployment/fastpass-api
```

### Update Code
```bash
git pull && ./deploy-local.sh
```

---

## 🐛 Troubleshooting

### API Not Responding
```bash
kubectl get pods -l app=fastpass-api
kubectl logs -l app=fastpass-api
```

### iOS App Crashes
- Check Xcode console for errors
- Verify all capabilities enabled
- See [XCODE_SETUP.md](XCODE_SETUP.md) troubleshooting section

### Database Issues
```bash
./backup-restore.sh test
kubectl get pods -l app=fastpass-postgres
```

### More Help
See individual documentation files for detailed troubleshooting.

---

## 📊 Tech Stack

| Component | Technology |
|-----------|------------|
| iOS | SwiftUI, iOS 18+ |
| Backend | Go 1.26, Gin framework |
| Database | PostgreSQL 15 |
| Auth | Apple Sign In + JWT |
| Deployment | Kubernetes, Docker |
| SSL | Let's Encrypt (auto) |
| Backup | CronJob (daily, automated) |

---

## 🎓 Project Structure

```
fastpass/
├── backend/
│   ├── main.go              # API entry point
│   ├── models.go            # Database models
│   ├── handlers.go          # API endpoints
│   ├── auth_*.go            # Authentication
│   ├── jwt.go               # JWT handling
│   ├── Dockerfile           # Container image
│   └── k8s/                 # Kubernetes manifests
│       ├── deployment.yaml
│       ├── service.yaml
│       ├── ingress.yaml
│       ├── postgres.yaml
│       └── backup-cronjob.yaml
├── ios/FastPass/FastPass/
│   ├── FastPassApp.swift    # App entry
│   ├── Models/
│   ├── Views/
│   ├── ViewModels/
│   └── Services/
├── deploy-local.sh          # Automated deployment
├── backup-restore.sh        # Database management
└── *.md                     # Documentation
```

---

## 🔐 Security

- ✅ Apple Sign In verified server-side
- ✅ JWT tokens (24h access, 30d refresh)
- ✅ HTTPS only (Let's Encrypt SSL)
- ✅ Independent database (isolated)
- ✅ Secure credential storage
- ✅ No secrets in code

---

## 🚀 Next Steps

1. **Deploy Backend**: Follow [DEPLOY_ON_SERVER.md](DEPLOY_ON_SERVER.md)
2. **Configure iOS**: Follow [XCODE_SETUP.md](XCODE_SETUP.md)  
3. **Test**: Record a drive and verify sync
4. **Monitor**: Check logs and backups
5. **Enjoy**: Track your drives! 🎉

---

## 📞 Support

- **Deployment Issues**: See [DEPLOY_ON_SERVER.md](DEPLOY_ON_SERVER.md)
- **Database Issues**: See [DATABASE_MANAGEMENT.md](DATABASE_MANAGEMENT.md)
- **iOS Issues**: See [XCODE_SETUP.md](XCODE_SETUP.md)
- **API Reference**: See [DEPLOYMENT_SUMMARY.md](DEPLOYMENT_SUMMARY.md)

---

**Version**: 1.0  
**Status**: Production Ready ✅  
**Domain**: fast.toper.dev  
**Last Updated**: April 1, 2026

