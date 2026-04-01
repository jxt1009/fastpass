# FastTrack - Complete End-to-End Testing Guide

## 🎉 Deployment Complete!

Your FastTrack speed tracking app is now fully deployed and ready to test!

**API Endpoint**: https://fast.toper.dev  
**Status**: ✅ Live and responding

---

## Testing the Complete Flow

### Prerequisites
- Xcode installed and working
- Physical iOS device (background location doesn't work properly in simulator)
- Apple ID for Sign in with Apple
- iOS device must have cellular or WiFi connection

### Step 1: Configure Xcode Capabilities

1. Open Xcode project: `ios/FastTrack/FastTrack.xcodeproj`
2. Select "FastTrack" target
3. Go to "Signing & Capabilities" tab
4. Enable the following capabilities:

   **Background Modes**:
   - ☑️ Location updates

   **Sign in with Apple**:
   - Should already be added (if not, click + and add it)

5. Ensure your development team is selected
6. Verify bundle identifier matches: `com.toper.FastTrack`

Full setup guide: See `XCODE_SETUP.md`

### Step 2: Build to Physical Device

1. Connect your iPhone via USB
2. Select your device from the device dropdown (not simulator)
3. Click the "Play" button to build and run
4. If prompted, trust the developer certificate on your iPhone:
   - Settings → General → Device Management → Trust your developer certificate

### Step 3: Test Authentication

1. App should show "Sign in with Apple" screen
2. Tap "Sign in with Apple" button
3. Complete Apple authentication flow
4. App should navigate to main screen showing:
   - Speed card (0 mph initially)
   - Map view
   - "Start Recording" button

### Step 4: Test Drive Recording

1. **Before starting**: Go outside or drive (GPS needs movement to track properly)
2. Tap "Start Recording" button
3. You should see:
   - Button changes to "Stop Recording"
   - Timer starts counting
   - Map starts showing your route as a blue line
   - Speed updates in real-time
   - Statistics cards update:
     - Time Elapsed
     - Distance (miles)
     - Max Speed
     - Min Speed
     - Avg Speed
     - Data Points

4. **During recording**:
   - Move around (walk, drive, etc.)
   - Watch the map follow your location with blue dot
   - See the blue route line draw behind you
   - Speed should update in real-time

5. **Stop recording**:
   - Tap "Stop Recording" button
   - Data is automatically saved to backend
   - Navigate to "History" tab

### Step 5: Verify Backend Sync

1. **Check History**:
   - Tap "History" tab at bottom
   - You should see your recorded drive
   - Shows: date, duration, distance, max speed

2. **View Details**:
   - Tap on a drive to see full details
   - Shows all statistics
   - Map with complete route

3. **Verify Backend**:
   ```bash
   # Get your user ID from logs or use API
   # Replace <your-jwt-token> with actual token
   curl -H "Authorization: Bearer <your-jwt-token>" https://fast.toper.dev/api/v1/drives
   ```

### Step 6: Test Multiple Drives

1. Record another drive (different location/time)
2. Verify both appear in history
3. Check leaderboard functionality (if implemented)

---

## Common Issues & Solutions

### Issue: "Location services not authorized"

**Solution**: 
1. Go to iPhone Settings → Privacy & Security → Location Services
2. Find "FastTrack"
3. Set to "Always" or "While Using the App"
4. Enable "Precise Location"

### Issue: Speed not updating

**Causes**:
- Not moving (GPS needs actual movement)
- Indoor location (GPS needs clear sky view)
- Simulator (use physical device)

**Solution**: Go outside and walk/drive

### Issue: Map not showing route

**Cause**: Location updates not received

**Solution**:
1. Check location permissions (see above)
2. Ensure you're moving
3. Check Xcode console for errors

### Issue: "Failed to save drive"

**Causes**:
- Network connectivity issue
- Backend server down
- Authentication expired

**Solution**:
1. Check network connection
2. Verify backend: `curl https://fast.toper.dev/health`
3. Try signing out and back in

### Issue: App crashes on launch

**Cause**: Core Location background mode issue

**Solution**: Already fixed in code with simulator detection. Rebuild and try again.

---

## Monitoring & Debugging

### Check Backend Logs

```bash
# SSH to server
ssh -p 2222 jtoper@10.0.0.102

# View API logs
kubectl logs -f -l app=fasttrack-api

# View PostgreSQL logs
kubectl logs -f -l app=fasttrack-postgres
```

### Check Database

```bash
# Connect to postgres pod
kubectl exec -it deployment/fasttrack-postgres -- psql -U fasttrack -d fasttrack

# List users
SELECT id, apple_user_id, email, full_name FROM users;

# List drives
SELECT id, user_id, start_time, duration, distance, max_speed FROM drives;

# Exit
\q
```

### Test API Endpoints

```bash
# Health check
curl https://fast.toper.dev/health

# Auth endpoint (returns user info and JWT)
curl -X POST https://fast.toper.dev/api/v1/auth/apple \
  -H "Content-Type: application/json" \
  -d '{"identityToken":"<token>","authorizationCode":"<code>"}'
```

---

## Performance Testing

### Test Different Scenarios

1. **City Driving**:
   - Frequent stops and starts
   - Lower speeds (0-45 mph)
   - Many turns

2. **Highway Driving**:
   - Higher speeds (55-75 mph)
   - Longer duration
   - Straight routes

3. **Walking**:
   - Very low speeds (0-4 mph)
   - Precise tracking
   - Short distances

4. **Long Duration**:
   - 30+ minute drives
   - Battery usage monitoring
   - Background mode testing

### Metrics to Monitor

- Battery drain during recording
- GPS accuracy (should be within 10-20 meters)
- Network usage (minimal until stop)
- App responsiveness
- Route smoothness on map

---

## Success Criteria

✅ **Authentication**: Successfully sign in with Apple  
✅ **Recording**: Can start/stop drive recording  
✅ **Live Tracking**: Speed and stats update in real-time  
✅ **Map Display**: Route draws on map as you move  
✅ **Backend Sync**: Drives saved to server  
✅ **History**: Can view past drives  
✅ **Details**: Can see full drive details  
✅ **Multi-User**: Each user sees only their drives  

---

## Next Steps After Testing

1. **Add Features**:
   - Leaderboard (backend ready, needs UI)
   - Share drives with friends
   - Export GPX/KML files
   - Drive statistics dashboard
   - Achievements/badges

2. **Polish**:
   - App icon
   - Launch screen
   - Onboarding tutorial
   - Settings screen

3. **App Store Preparation**:
   - Screenshots
   - App description
   - Privacy policy
   - Terms of service
   - App review submission

4. **Monitoring**:
   - Set up error tracking (Sentry, etc.)
   - Analytics (privacy-friendly)
   - Backend monitoring (Prometheus/Grafana)

---

## Support & Troubleshooting

**Backend Issues**: Check `TROUBLESHOOTING_DB_CONNECTION.md`  
**DNS/Deployment**: Check `DEPLOYMENT_STATUS.md`  
**Xcode Setup**: Check `XCODE_SETUP.md`  
**Features**: Check `FEATURES.md`

**Backend Status**: https://fast.toper.dev/health  
**Server Access**: `ssh -p 2222 jtoper@10.0.0.102`

---

## Testing Checklist

- [ ] Sign in with Apple works
- [ ] Start recording button works
- [ ] Speed updates while moving
- [ ] Map shows current location
- [ ] Route line draws on map
- [ ] All stat cards update (time, distance, speeds)
- [ ] Stop recording button works
- [ ] Drive appears in history
- [ ] Can view drive details
- [ ] Map in details shows full route
- [ ] Multiple drives work
- [ ] Background tracking works
- [ ] App doesn't crash
- [ ] Battery usage is reasonable
- [ ] Network usage is minimal

---

**Ready to test!** 🚀

If you encounter any issues, check the logs and troubleshooting guides above.
