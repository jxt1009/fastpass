# 🚨 App Crashing on Launch? Read This First!

## The Crash You're Seeing

```
NSInternalInconsistencyException: Invalid parameter not satisfying: 
!stayUp || CLClientIsBackgroundable...
```

## The Fix (2 Minutes)

### In Xcode:

1. Click **FastTrack** project (blue icon at top)
2. Click **FastTrack** under TARGETS
3. Click **Signing & Capabilities** tab
4. Click **+ Capability**
5. Add **Background Modes**
6. Check: ☑️ **Location updates**
7. Clean build: `Cmd + Shift + K`
8. Run again: `Cmd + R`

**Done!** The app should now launch without crashing.

## Why?

The app needs the "Background Modes" capability to track location in the background. Without it, iOS crashes the app immediately.

## Still Crashing?

1. Make sure you checked "Location updates" (not other options)
2. Delete the app from simulator/device
3. Clean build folder (Cmd+Shift+K)
4. Rebuild and run

## Need More Help?

See `FIX_BACKGROUND_CRASH.md` for detailed instructions with screenshots.

---

**TL;DR**: Add "Background Modes" capability with "Location updates" checked in Xcode.
