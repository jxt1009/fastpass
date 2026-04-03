# Development Guide

---

## iOS — Xcode Setup

### 1. Open the project
```bash
open ios/FastTrack/FastTrack.xcodeproj
```

### 2. Add capabilities

In **Signing & Capabilities** tab → **+ Capability**:

| Capability | Setting |
|---|---|
| **Sign in with Apple** | (just add it) |
| **Background Modes** | Check **Location updates** only |

Without these the app will crash on launch (`NSInternalInconsistencyException`) and Apple Sign In will fail (`AKAuthenticationError -7026`).

### 3. Add location permission keys

In the **Info** tab → **Custom iOS Target Properties**, add:

| Key | Value |
|---|---|
| `Privacy - Location When In Use Usage Description` | `FastTrack needs your location to track speed and route.` |
| `Privacy - Location Always and When In Use Usage Description` | `FastTrack needs background location to continue tracking when the app is backgrounded.` |

### 4. Signing

- **General** tab → **Bundle Identifier**: `com.toper.FastTrack`
- **Signing & Capabilities** → check **Automatically manage signing** → select your **Team**

### 5. Backend URL

In `Services/APIService.swift`, the base URL is already set to production:
```swift
private let baseURL = "https://fast.toper.dev/api/v1"
```
For local dev, change to `http://localhost:8080/api/v1`.

### 6. Build and run

Prefer a **physical device** for:
- Accurate GPS and speed data
- Background location tracking
- Apple Sign In (simulator has known issues)

On first run on device: **Settings → General → VPN & Device Management → Trust** your developer certificate.

---

## iOS — Project Structure

```
ios/FastTrack/FastTrack/
├── FastTrackApp.swift
├── Models/
│   └── Drive.swift                  # Codable drive model
├── Services/
│   ├── LocationManager.swift        # Core Location, speed/route tracking
│   ├── APIService.swift             # Backend REST client (async/await)
│   ├── AuthManager.swift            # JWT storage and auto-refresh
│   └── AppleSignInManager.swift     # ASAuthorizationController wrapper
├── ViewModels/
│   └── DriveManager.swift           # Drive recording state machine
└── Views/
    ├── ContentView.swift            # Main screen: map + speed + stats
    ├── DriveHistoryView.swift       # Drive list
    ├── DriveDetailView.swift        # Per-drive stats + route map
    ├── SignInView.swift             # Apple / Google sign-in screen
    ├── ProfileView.swift            # User profile
    ├── ProfileSetupView.swift       # First-time username setup
    ├── PublicProfileView.swift      # Other users' profiles
    ├── SocialView.swift             # Feed / following
    ├── FindPeopleView.swift         # User search
    ├── AnalyticsView.swift          # Charts and insights
    ├── AchievementsView.swift       # Badges
    ├── CarPickerView.swift          # Car selection UI
    ├── CarSelectorView.swift        # Garage management
    ├── MoreView.swift               # Tab bar overflow
    ├── SettingsView.swift           # App settings
    └── SharedComponents.swift       # Reusable UI components
```

---

## iOS — Simulator Tips

GPS simulation in Xcode: **Debug → Simulate Location → City Run / Freeway Drive**

Apple Sign In in simulator may fail — use a physical device for auth testing.

---

## Backend — Local Development

### Prerequisites
- Go 1.21+
- PostgreSQL running locally (or via Docker)

### Run locally
```bash
cd backend

# Start PostgreSQL (Docker example)
docker run -d --name fasttrack-pg \
  -e POSTGRES_USER=fasttrack \
  -e POSTGRES_PASSWORD=secret \
  -e POSTGRES_DB=fasttrack \
  -p 5432:5432 postgres:15-alpine

export DATABASE_URL="host=localhost user=fasttrack password=secret dbname=fasttrack port=5432 sslmode=disable"
export JWT_SECRET="$(openssl rand -base64 32)"
export APPLE_APP_BUNDLE_ID="com.toper.FastTrack"
export BASE_URL="http://localhost:8080"

go run .
```

### Test endpoints
```bash
curl http://localhost:8080/health
# {"status":"ok"}

# Auth (will return 401 with invalid token — expected)
curl -X POST http://localhost:8080/api/v1/auth/apple \
  -H "Content-Type: application/json" \
  -d '{"identity_token":"test"}'

# Protected endpoint (requires valid JWT)
curl http://localhost:8080/api/v1/drives \
  -H "Authorization: Bearer YOUR_JWT"
```

### Build
```bash
cd backend
go build -o fasttrack-api
./fasttrack-api
```

---

## Apple Sign In — Setup

### Development (personal team, free)
1. Add Apple ID to Xcode: **Settings → Accounts → +**
2. Add "Sign in with Apple" capability to the target
3. Select your personal team
4. Test on physical device

### Production (Apple Developer Program, $99/year)
1. In [Apple Developer Portal](https://developer.apple.com) → Certificates, IDs & Profiles
2. Select your App ID → enable **Sign in with Apple**
3. No redirect URIs needed for native iOS apps

### Backend verification
The backend verifies Apple's identity token using Apple's public JWKS endpoint. It checks:
- Token signature
- Expiry
- Audience matches `APPLE_APP_BUNDLE_ID` env var

### Troubleshooting Apple Sign In

| Error | Cause | Fix |
|---|---|---|
| `AKAuthenticationError -7026` | Missing capability | Add "Sign in with Apple" in Xcode |
| `Code=1000` | Same as above | Add capability, test on device |
| `Code=1001` | User cancelled | Normal — user backed out |
| "Invalid Apple token" | Token expired / wrong bundle ID | Check `APPLE_APP_BUNDLE_ID` env var |

---

## Google Sign In — Setup

### 1. Google Cloud Console
1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. **APIs & Services → Credentials → Create Credentials → OAuth client ID**
3. Application type: **iOS**
4. Bundle ID: `com.toper.FastTrack`
5. Copy the Client ID

### 2. Backend env vars
```bash
export GOOGLE_CLIENT_ID="YOUR_CLIENT_ID.apps.googleusercontent.com"
export GOOGLE_CLIENT_SECRET="YOUR_CLIENT_SECRET"
```

### 3. iOS — Info.plist
```xml
<key>GIDClientID</key>
<string>YOUR_CLIENT_ID.apps.googleusercontent.com</string>

<key>CFBundleURLTypes</key>
<array>
  <dict>
    <key>CFBundleURLSchemes</key>
    <array>
      <string>com.googleusercontent.apps.YOUR_REVERSED_CLIENT_ID</string>
    </array>
  </dict>
</array>
```

---

## Testing Checklist (physical device)

- [ ] App launches without crash
- [ ] Apple Sign In completes
- [ ] Location permission granted
- [ ] "Start Recording" begins tracking
- [ ] Speed updates while moving
- [ ] Map shows live route polyline
- [ ] Statistics cards update (time, distance, max/avg/min speed)
- [ ] Screen lock → tracking continues in background
- [ ] "Stop Recording" saves drive
- [ ] Drive appears in history
- [ ] Drive detail shows full route and stats
- [ ] Profile page loads
- [ ] Leaderboard loads
