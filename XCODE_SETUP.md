# Xcode Project Setup Guide

## Required Configuration for FastPass iOS App

After adding files to your Xcode project, you need to configure capabilities and permissions.

---

## 1. Add Files to Xcode Target

1. Open `FastPass.xcodeproj` in Xcode
2. Right-click on the `FastPass` group in Project Navigator
3. Select "Add Files to 'FastPass'..."
4. Navigate to the `FastPass` folder you copied
5. Select all folders: `Models/`, `Views/`, `ViewModels/`, `Services/`
6. **Important**: Check "Add to targets: FastPass"
7. Click "Add"

**Verify:**
- Go to Target → Build Phases → Compile Sources
- All `.swift` files should be listed

---

## 2. Sign in with Apple Capability

**Steps:**
1. Select your project in Project Navigator
2. Select the `FastPass` target
3. Go to "Signing & Capabilities" tab
4. Click "+ Capability"
5. Search for and add: **"Sign in with Apple"**

**What it does:**
- Enables Apple Sign In authentication
- Required for `/api/v1/auth/apple` to work

---

## 3. Background Modes (Location Updates)

**Steps:**
1. In "Signing & Capabilities" tab
2. Click "+ Capability"
3. Search for and add: **"Background Modes"**
4. Check the box: ☑️ **"Location updates"**

**What it does:**
- Allows the app to receive location updates in background
- Required for tracking drives when app is not active
- Without this, tracking stops when screen locks

**Note:** The app now gracefully handles missing capability on simulator

---

## 4. Location Permissions (Info.plist)

**Steps:**
1. Select `Info.plist` in Project Navigator
2. Right-click → Open As → Source Code
3. Add these keys **before** the closing `</dict>` tag:

```xml
<!-- Location permission descriptions -->
<key>NSLocationWhenInUseUsageDescription</key>
<string>FastPass needs your location to track your speed and route during drives.</string>

<key>NSLocationAlwaysAndWhenInUseUsageDescription</key>
<string>FastPass needs background location access to continue tracking your drives even when the app is in the background.</string>

<key>NSLocationAlwaysUsageDescription</key>
<string>FastPass tracks your drives in the background to provide accurate statistics.</string>
```

**Or add via Property List editor:**
1. Select `Info.plist`
2. Click + to add new row
3. Add these keys with descriptions:

| Key | Type | Value |
|-----|------|-------|
| Privacy - Location When In Use Usage Description | String | FastPass needs your location to track your speed and route during drives. |
| Privacy - Location Always and When In Use Usage Description | String | FastPass needs background location access to continue tracking your drives even when the app is in the background. |
| Privacy - Location Always Usage Description | String | FastPass tracks your drives in the background to provide accurate statistics. |

---

## 5. Update Bundle Identifier (if needed)

**Steps:**
1. Select project → Target → General tab
2. Update **Bundle Identifier** to match your Apple Developer account
3. Example: `com.yourname.FastPass`

**For Apple Sign In:**
- Must match the identifier registered in Apple Developer Portal
- Must have Sign in with Apple capability enabled in portal

---

## 6. Verify Team & Signing

**Steps:**
1. General tab → Signing section
2. Check "Automatically manage signing"
3. Select your **Team** from dropdown
4. Xcode will automatically create provisioning profiles

**Troubleshooting:**
- If signing fails, check Apple Developer account status
- Ensure bundle ID doesn't conflict with existing apps

---

## 7. Fix Common Build Errors

### Duplicate ContentView.swift

If you see error: `Filename "ContentView.swift" used twice`

**Solution:**
1. In Project Navigator, find the **old** `ContentView.swift` (in root)
2. Right-click → Delete → "Move to Trash"
3. Keep only: `FastPass/Views/ContentView.swift`
4. Clean build folder: Product → Clean Build Folder (Shift+Cmd+K)

### Missing Target Membership

If files show in Xcode but don't compile:

**Solution:**
1. Select the file in Project Navigator
2. Open File Inspector (right panel, first tab)
3. Under "Target Membership", check ☑️ **FastPass**

---

## 8. Build Settings (Optional but Recommended)

### Increase Build Performance

**Steps:**
1. Select project → Build Settings
2. Search: "Debug Information Format"
3. Set to: **DWARF** (not DWARF with dSYM)
4. This speeds up debug builds

### Swift Compiler Settings

Already configured in project, but verify:
- Swift Language Version: **Swift 5**
- Optimization Level (Debug): **No Optimization [-Onone]**
- Optimization Level (Release): **Optimize for Speed [-O]**

---

## 9. Test on Simulator

**Steps:**
1. Select a simulator (e.g., iPhone 15 Pro)
2. Build: Cmd+B
3. Run: Cmd+R

**Expected behavior:**
- App launches
- Shows Sign In with Apple screen
- Location requests prompt appears
- No crashes!

**Simulator limitations:**
- GPS coordinates simulated
- Speed always 0 (use Debug → Location → City Run to simulate)
- Background mode limited

---

## 10. Test on Real Device

**For full functionality:**
1. Connect iPhone via USB
2. Select device in Xcode
3. Build and run
4. Trust developer certificate on device (Settings → General → VPN & Device Management)

**Test checklist:**
- [ ] Apple Sign In works
- [ ] Location permission granted
- [ ] Start recording drive
- [ ] Lock phone - recording continues
- [ ] GPS coordinates update
- [ ] Speed updates in real-time
- [ ] Map shows route
- [ ] Stop recording saves drive
- [ ] View in history

---

## 11. App Store Connect Setup (Future)

When ready to distribute:

1. **Register App ID** in Apple Developer Portal
   - Identifier: `com.yourname.FastPass`
   - Capabilities: Sign in with Apple, Background Modes

2. **Create App in App Store Connect**
   - Bundle ID must match Xcode
   - Configure app details
   - Upload screenshots

3. **Archive and Upload**
   - Product → Archive
   - Upload to App Store Connect
   - Submit for review

---

## Troubleshooting

### Location Not Working

**Check:**
```swift
// In Xcode console, look for:
"Location services enabled"
"Authorization status: authorizedAlways"
```

**Fix:**
- Grant location permission in Settings → Privacy
- Ensure Background Modes capability is enabled
- Check Info.plist has location usage descriptions

### Apple Sign In Fails

**Check:**
- Sign in with Apple capability added
- Bundle ID matches registered App ID
- Backend API is accessible (test with curl)
- Token verification works on backend

### App Crashes on Launch

**Check:**
- All files added to target
- No duplicate files
- Clean build folder
- Check crash log for specific error

### Background Tracking Stops

**Check:**
- Background Modes → Location updates enabled
- Always location permission granted (not just "While Using")
- Battery saver mode not enabled
- App not force-quit by user

---

## Quick Verification Checklist

Before testing, ensure:

- [ ] All Swift files added to Xcode target
- [ ] Sign in with Apple capability enabled
- [ ] Background Modes capability enabled
- [ ] Location updates checked in Background Modes
- [ ] Info.plist has all 3 location permission keys
- [ ] Bundle identifier is correct
- [ ] Team is selected for signing
- [ ] No duplicate ContentView.swift
- [ ] Clean build succeeds (Cmd+Shift+K, then Cmd+B)
- [ ] Backend API is running (or URL updated)

---

## Additional Resources

- **Apple Documentation**: [Core Location Background Updates](https://developer.apple.com/documentation/corelocation/cllocationmanager/1620568-allowsbackgroundlocationupdates)
- **Sign in with Apple**: [Implementing User Authentication](https://developer.apple.com/documentation/sign_in_with_apple/implementing_user_authentication_with_sign_in_with_apple)
- **Background Modes**: [Updating Location in Background](https://developer.apple.com/documentation/corelocation/getting_the_user_s_location/handling_location_events_in_the_background)

---

**Last Updated**: April 1, 2026  
**Xcode Version**: 26.4+  
**iOS Version**: 18.0+
