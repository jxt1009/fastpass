# 🚨 Apple Sign In Not Working?

## The Error

```
Authorization failed: Error Domain=AKAuthenticationError Code=-7026
ASAuthorizationController credential request failed with error: Code=1000
```

## Quick Fix (2 Minutes)

### In Xcode:

1. Click **FastTrack** project → **FastTrack** target
2. **Signing & Capabilities** tab
3. Click **+ Capability**
4. Add **"Sign in with Apple"**
5. Add your Apple ID: Xcode → Settings → Accounts
6. Select your team in Signing section
7. **Test on PHYSICAL DEVICE** (not simulator - Apple Sign In has issues in simulator)

### On Your iPhone:

1. Connect iPhone via USB
2. Select iPhone in Xcode (not simulator)
3. Run app (Cmd + R)
4. If "Untrusted Developer": Settings → General → Device Management → Trust
5. Launch app
6. Tap "Sign in with Apple"
7. Should work!

## Why It Fails

- Missing "Sign in with Apple" capability
- Testing in simulator (use real device)
- No Apple ID in Xcode

## Two Capabilities Needed

✅ **Sign in with Apple** - For authentication  
✅ **Background Modes** (Location updates) - For GPS tracking

Both are REQUIRED!

## Still Issues?

See `FIX_APPLE_SIGNIN.md` for detailed troubleshooting.

---

**TL;DR**: Add "Sign in with Apple" capability in Xcode AND test on physical device.
