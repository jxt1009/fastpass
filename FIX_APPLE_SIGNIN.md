# Fix: Apple Sign In Authentication Errors

## Errors You're Seeing

```
Authorization failed: Error Domain=AKAuthenticationError Code=-7026
ASAuthorizationController credential request failed with error: 
Error Domain=com.apple.AuthenticationServices.AuthorizationError Code=1000
```

## Root Causes

1. **Sign in with Apple capability not configured** (most likely)
2. **Missing entitlements**
3. **Running in simulator** (Apple Sign In has limitations)
4. **Bundle ID mismatch**

---

## Fix #1: Configure Sign in with Apple Capability (REQUIRED)

### Steps:

1. **Open Xcode**:
   ```bash
   open ios/FastPass/FastPass.xcodeproj
   ```

2. **Select Project**:
   - Click **FastPass** (blue icon) in Project Navigator
   - Select **FastPass** under TARGETS

3. **Go to Signing & Capabilities Tab**

4. **Add Sign in with Apple**:
   - Click **+ Capability** button (top left)
   - Search for: **Sign in with Apple**
   - Click to add it

5. **Verify**:
   - You should see "Sign in with Apple" section in capabilities
   - No errors should appear

6. **Clean and Rebuild**:
   - Clean build folder: `Cmd + Shift + K`
   - Build: `Cmd + B`
   - Run: `Cmd + R`

---

## Fix #2: Verify Bundle Identifier

The bundle ID must match what's registered with Apple.

### Check Bundle ID:

1. In Xcode, go to **General** tab
2. **Identity** section → **Bundle Identifier**: `com.toper.FastPass`
3. This should match your Apple Developer account

### If You Need to Change It:

1. Update Bundle Identifier to match your team
2. Example: `com.yourname.FastPass`
3. Update in **both**:
   - General tab → Bundle Identifier
   - Signing & Capabilities → Team

---

## Fix #3: Configure Apple Developer Account

### Option A: Using Your Own Apple ID (Free Tier)

1. **Add Account**:
   - Xcode → Settings (Cmd + ,)
   - Accounts tab
   - Click **+** → Add Apple ID
   - Sign in with your Apple ID

2. **Select Team**:
   - Back in your project → Signing & Capabilities
   - Team: Select your personal team (Your Name - Personal Team)

3. **Automatic Signing**:
   - Check: ☑️ **Automatically manage signing**

### Option B: Using Apple Developer Program ($99/year)

If you have a paid developer account:
1. Sign in with your developer account in Xcode
2. Select your team
3. The app will use your registered App ID

**Note**: For testing, free tier works fine. For App Store, you need paid account.

---

## Fix #4: Test on Physical Device (Recommended)

Apple Sign In works better on physical devices than simulator.

### Steps:

1. **Connect iPhone via USB**
2. **Trust Device**:
   - First time: "Trust This Computer?" on iPhone
3. **Select Device** in Xcode toolbar (not simulator)
4. **Run**: `Cmd + R`

### On Device First Run:

1. You may see: "Untrusted Developer"
2. Fix: Settings → General → Device Management
3. Trust your developer certificate
4. Go back to app and launch

---

## Fix #5: Simulator Limitations

If testing in simulator:

### Simulator Issues:
- ✅ Apple Sign In UI will appear
- ⚠️ May have authentication issues
- ⚠️ May not save credentials properly
- ⚠️ Better to test on physical device

### Simulator Workaround:

For simulator testing only, you can add mock authentication:

1. Comment out real Apple Sign In in `SignInView.swift`
2. Use a debug bypass (temporary, for testing only)

**Not recommended** - better to test on real device.

---

## Fix #6: Check Entitlements File

The entitlements file should be auto-generated when you add the capability.

### Verify:

1. In Project Navigator, find: `FastPass.entitlements`
2. Should contain:
   ```xml
   <key>com.apple.developer.applesignin</key>
   <array>
       <string>Default</string>
   </array>
   ```

### If Missing:

1. The capability wasn't added properly
2. Remove and re-add "Sign in with Apple" capability
3. Clean build

---

## Complete Checklist

Before testing Apple Sign In:

- [ ] Sign in with Apple capability added in Xcode
- [ ] Background Modes capability added with Location updates
- [ ] Bundle ID set: `com.toper.FastPass` (or your own)
- [ ] Team selected in Signing & Capabilities
- [ ] Apple ID added to Xcode Accounts
- [ ] Automatically manage signing enabled
- [ ] Testing on physical device (recommended)
- [ ] Device trusted in Settings (if using personal team)
- [ ] Clean build performed
- [ ] App runs without crashing

---

## Testing Apple Sign In

### Expected Flow:

1. **Launch app** → Shows "Sign in with Apple" screen
2. **Tap button** → Apple Sign In modal appears
3. **Face ID/Touch ID** → Authenticate
4. **Choose email** → Use real email or hide
5. **Success** → App shows main screen with map

### Debug Output:

Watch Xcode console for:
- ✅ `Background location updates enabled`
- ✅ Apple Sign In request initiated
- ✅ Token received
- ✅ API authentication successful

### Common Errors:

| Error Code | Meaning | Fix |
|------------|---------|-----|
| -7026 | Authentication error | Add capability |
| 1000 | Authorization error | Add capability |
| 1001 | User cancelled | Normal - user backed out |
| -54 | Database permission | Simulator issue or capability missing |

---

## Still Not Working?

### Debug Steps:

1. **Check Xcode Console**:
   - Look for "Sign in with Apple" errors
   - Note the error code

2. **Verify Capabilities**:
   - Target → Signing & Capabilities
   - Should see TWO capabilities:
     - ✅ Sign in with Apple
     - ✅ Background Modes (Location updates)

3. **Check Bundle ID**:
   - Must not have spaces
   - Must be reverse-DNS format: `com.yourname.appname`

4. **Device vs Simulator**:
   - Try on physical device first
   - Simulator has known issues with Apple Sign In

5. **Network Connection**:
   - Apple Sign In requires internet
   - Check WiFi/cellular

6. **Apple Server Status**:
   - Check: https://developer.apple.com/system-status/
   - Sign in with Apple service should be operational

---

## Quick Test (Physical Device)

```bash
# 1. Connect iPhone
# 2. In Xcode:
#    - Select your device (not simulator)
#    - Select your team in Signing
#    - Cmd + R to run

# 3. On iPhone:
#    - If prompted, trust developer
#    - Launch app
#    - Tap "Sign in with Apple"
#    - Authenticate with Face ID
#    - Success!
```

---

## Development vs Production

### Development (Current Setup):
- Uses personal team
- Sign in with Apple works
- Can test full flow
- Free

### Production (App Store):
- Requires paid Apple Developer Program ($99/year)
- App ID must be registered
- Sign in with Apple must be enabled in App ID
- Proper provisioning profiles

For now, **development mode is fine** for testing!

---

## Alternative: Mock Sign In (Testing Only)

If you just want to test the rest of the app without Apple Sign In:

**Add to `SignInView.swift`**:

```swift
// TEMPORARY: For testing without Apple Sign In
Button("Debug: Skip Sign In") {
    authManager.saveToken("debug-token-for-testing")
    authManager.isAuthenticated = true
}
.foregroundColor(.gray)
```

**⚠️ Warning**: This bypasses real authentication. Backend calls will fail. Only use for UI testing.

---

## Summary

**Most Common Fix**:
1. Add "Sign in with Apple" capability in Xcode
2. Test on physical device (not simulator)
3. Make sure bundle ID is valid

**Capabilities Needed**:
- ✅ Sign in with Apple
- ✅ Background Modes (Location updates)

**Testing**:
- Physical device recommended
- Simulator has limitations

See `XCODE_SETUP.md` for complete capability configuration.
