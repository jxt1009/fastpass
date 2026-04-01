# FastTrack Setup - Final Steps

## ✅ Files Added

All source files have been copied to your FastTrack project! Here's what's in place:

```
FastTrack/FastTrack/
├── FastTrackApp.swift       ✅ Updated with managers
├── Views/
│   ├── ContentView.swift   ✅ Main screen with speed tracking
│   ├── DriveHistoryView.swift  ✅ Drive list
│   └── DriveDetailView.swift   ✅ Drive details
├── Models/
│   └── Drive.swift         ✅ Data model
├── Services/
│   ├── LocationManager.swift   ✅ GPS tracking
│   └── APIService.swift    ✅ Backend API
└── ViewModels/
    └── DriveManager.swift  ✅ Recording logic
```

## 📝 Required Configuration in Xcode

### Step 1: Add Files to Xcode Project

1. In Xcode, in the Project Navigator (left sidebar), right-click on the **FastTrack** group
2. Select **"Add Files to FastTrack..."**
3. Navigate to and select these folders:
   - `Views`
   - `Models`
   - `Services`
   - `ViewModels`
4. **IMPORTANT**: Make sure "Copy items if needed" is UNCHECKED (files are already in the right place)
5. Click **Add**

### Step 2: Configure Location Permissions

Since iOS 18 doesn't always use Info.plist, add permissions in the project settings:

1. Select **FastTrack** project in Project Navigator
2. Select the **FastTrack** target
3. Go to the **Info** tab
4. Click the **+** button under "Custom iOS Target Properties"
5. Add these keys:

**Key 1:**
- Key: `Privacy - Location When In Use Usage Description`
- Type: String
- Value: `We need your location to track your driving speed and route`

**Key 2:**
- Key: `Privacy - Location Always and When In Use Usage Description`
- Type: String
- Value: `We need continuous access to your location to accurately track your drives even when the app is in the background`

### Step 3: Enable Background Location

1. Still in target settings, go to **"Signing & Capabilities"** tab
2. Click **"+ Capability"**
3. Add **"Background Modes"**
4. Check the box for **"Location updates"**

### Step 4: Configure Backend API

1. In Xcode, open `Services/APIService.swift`
2. Find the line: `private let baseURL = "http://localhost:8080/api/v1"`
3. Change it to your backend URL:
   ```swift
   private let baseURL = "https://your-backend-url.com/api/v1"
   ```

### Step 5: Build and Run

1. Select your target device (iPhone simulator or physical device)
2. Press **Cmd+B** to build
3. Press **Cmd+R** to run
4. When prompted, grant location permissions ("Allow While Using App" or "Allow Always")

## 🎮 How to Use

1. **Grant Location Permission**: Tap "Allow" when prompted
2. **Start Recording**: Tap "Start Recording" button
3. **Drive Around**: Watch your speed update in real-time
4. **View Stats**: See distance, duration, max/avg speed while driving
5. **Stop Recording**: Tap "Stop Recording" when done
6. **View History**: Tap "View History" to see all your drives
7. **View Details**: Tap any drive to see full details

## 🔧 Troubleshooting

### Build Errors
- Make sure all files are added to the target (check the File Inspector)
- Clean build folder: **Product → Clean Build Folder** (Cmd+Shift+K)
- Restart Xcode if needed

### Location Not Working
- Check location permissions in Settings → FastTrack
- Make sure "Location updates" is enabled in Background Modes
- Run on a physical device for best GPS accuracy

### API Connection Issues
- Verify backend URL is correct in APIService.swift
- Make sure backend is deployed and running
- Check network connectivity

## 📱 Testing Tips

- **Simulator**: Debug → Location → Freeway Drive (simulates driving)
- **Physical Device**: Best for accurate speed tracking
- **Background Testing**: Start a drive, then minimize the app

## 🚀 Backend Deployment

Your Go backend is ready in `/Users/jtoper/DEV/triprank/backend`

See `backend/DEPLOYMENT.md` for Kubernetes deployment instructions.

Quick local test:
```bash
cd /Users/jtoper/DEV/triprank/backend
export DATABASE_URL="host=localhost user=postgres password=postgres dbname=triprank port=5432 sslmode=disable"
./triprank-api
```

---

**You're all set!** 🎉 Start building and testing your speed tracking app!
