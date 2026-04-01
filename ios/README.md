# TripRank iOS App

## Setup Instructions

### 1. Open Project in Xcode

Since Xcode projects require interactive creation, follow these steps:

1. Open Xcode
2. File → New → Project
3. Select "iOS" → "App"
4. Configure:
   - Product Name: **TripRank**
   - Team: Select your team
   - Organization Identifier: `com.yourdomain`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Storage: None needed
5. Save to: `/Users/jtoper/DEV/triprank/ios`

### 2. Add Source Files

The source files are already created in the TripRank folder. In Xcode:

1. Delete the default `ContentView.swift` and `TripRankApp.swift` that Xcode created
2. Right-click the TripRank group in Project Navigator
3. Select "Add Files to TripRank..."
4. Select all files from the `/Users/jtoper/DEV/triprank/ios/TripRank` folder
5. Make sure "Copy items if needed" is UNCHECKED
6. Click Add

### 3. Configure Permissions

In your project's Info.plist (or Info tab), add these keys:

- **Privacy - Location When In Use Usage Description**: "We need your location to track your driving speed and route"
- **Privacy - Location Always and When In Use Usage Description**: "We need continuous access to your location to accurately track your drives even when the app is in the background"
- **Required background modes**: Add "location" to enable background location tracking

### 4. Configure API Endpoint

In `Services/APIService.swift`, update the `baseURL` to point to your backend:

```swift
private let baseURL = "https://your-backend-url.com/api/v1"
```

### 5. Configure Signing & Capabilities

1. Select your project in Project Navigator
2. Select the TripRank target
3. Go to "Signing & Capabilities"
4. Add capability: "Background Modes"
5. Check "Location updates"
6. Select your Team for code signing

### 6. Run the App

1. Select a simulator or your iOS device
2. Press Cmd+R to build and run
3. When prompted, allow location permissions

## Project Structure

```
TripRank/
├── TripRankApp.swift           # App entry point
├── Views/
│   ├── ContentView.swift       # Main screen with speed tracking
│   ├── DriveHistoryView.swift  # List of recorded drives
│   └── DriveDetailView.swift   # Individual drive details
├── Models/
│   └── Drive.swift             # Drive data model
├── Services/
│   ├── LocationManager.swift   # GPS/location tracking
│   └── APIService.swift        # Backend API client
└── ViewModels/
    └── DriveManager.swift      # Drive recording logic
```

## Features

- **Real-time Speed Tracking**: Displays current speed in MPH
- **Trip Recording**: Start/stop drive recording with button
- **Live Statistics**: See duration, distance, max/avg speed while driving
- **Drive History**: View all your recorded trips
- **Drive Details**: See detailed information about each trip
- **Cloud Sync**: Automatically syncs to backend API
- **Background Tracking**: Continues tracking even when app is backgrounded

## Requirements

- iOS 18.0+
- Xcode 26.0+
- Swift 5.10+

## Notes

- Location permission is required for the app to function
- Background location tracking requires "Always" permission
- API endpoint must be configured before syncing will work
- Currently uses a UUID for user identification (add proper auth later)
