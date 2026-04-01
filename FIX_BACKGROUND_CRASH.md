# CRITICAL FIX: Background Location Crash

## Problem

App crashes on launch with:
```
Terminating app due to uncaught exception 'NSInternalInconsistencyException', 
reason: 'Invalid parameter not satisfying: !stayUp || CLClientIsBackgroundable(internal->fClient) || _CFMZEnabled()'
```

## Root Cause

The app tries to enable background location updates, but the **Background Modes** capability is not configured in Xcode. This is a **REQUIRED** capability - the app WILL crash without it.

## Fix Steps

### Step 1: Open Xcode Project

```bash
open ios/FastPass/FastPass.xcodeproj
```

### Step 2: Configure Background Modes

1. Click on **FastPass** (blue icon) in Project Navigator
2. Select **FastPass** target (under TARGETS)
3. Click on **Signing & Capabilities** tab
4. Click **+ Capability** button (top left)
5. Search for: **Background Modes**
6. Click to add it
7. In the expanded Background Modes section, check **ONLY**:
   - ☑️ **Location updates**
8. DO NOT check other options (Background fetch, Remote notifications, etc.)

### Step 3: Verify Configuration

After adding the capability, you should see:

**In Signing & Capabilities tab:**
- Background Modes section visible
- "Location updates" is checked

**In Info.plist (optional verification):**
- Navigate to Info.plist in Project Navigator
- Open as Source Code
- Should contain:
  ```xml
  <key>UIBackgroundModes</key>
  <array>
      <string>location</string>
  </array>
  ```

### Step 4: Rebuild and Run

1. Clean build folder: `Cmd + Shift + K`
2. Build: `Cmd + B`
3. Run on device or simulator: `Cmd + R`

The app should now launch without crashing.

## Why This Happens

iOS requires explicit declaration when apps want to use background location. Setting `allowsBackgroundLocationUpdates = true` in code is not enough - you MUST also:

1. Enable the "Background Modes" capability
2. Check "Location updates" mode
3. Have proper Info.plist entries for location permissions

Without the capability, iOS throws an assertion failure (not catchable) and crashes the app immediately.

## Updated Code

The LocationManager now checks for the capability before attempting to enable:

```swift
if Bundle.main.object(forInfoDictionaryKey: "UIBackgroundModes") != nil {
    locationManager.allowsBackgroundLocationUpdates = true
    locationManager.pausesLocationUpdatesAutomatically = false
    print("✅ Background location updates enabled")
} else {
    print("ℹ️ Background location not configured - app will track in foreground only")
}
```

However, it's still **REQUIRED** to configure the capability - without it, the app will only work in foreground.

## What If I Don't Need Background Location?

If you only want foreground tracking:

1. **Option A**: Configure the capability anyway (recommended - enables full features)
2. **Option B**: Modify `LocationManager.swift` and remove/comment out lines 21-27 (the background location setup)

But for a speed tracking app, background location is essential - otherwise tracking stops when:
- Screen locks
- User switches to another app
- Phone receives a call

## Testing

After fix:

1. **Foreground test**: App open, start recording, see speed updates ✅
2. **Background test**: Start recording, lock phone, unlock after 1 minute, see continued tracking ✅
3. **App switching test**: Start recording, switch to another app, return, see continued tracking ✅

## Need Help?

If still crashing:
1. Verify Background Modes capability is enabled
2. Verify "Location updates" is checked
3. Clean build folder (Cmd+Shift+K)
4. Delete app from simulator/device
5. Rebuild and reinstall

Check console output for:
- "✅ Background location updates enabled" - Good!
- "ℹ️ Background location not configured" - Capability missing
- Crash with NSInternalInconsistencyException - Capability not configured

## Related Documentation

- `XCODE_SETUP.md` - Complete Xcode configuration guide
- `TESTING_GUIDE.md` - End-to-end testing instructions
