# Google Sign In Setup Guide

## Overview

Google Sign In is added as an alternative to Apple Sign In. It works on all platforms (iOS, Android, web) and doesn't require Apple Developer Program capabilities.

## Backend Setup (Already Done ✅)

The backend now supports Google OAuth:
- **Endpoint**: `POST /api/v1/auth/google`
- **Request**: `{"id_token": "google_id_token_here"}`
- **Response**: Same as Apple Sign In (access token, refresh token, user info)

The backend verifies the Google ID token with Google's servers and creates/updates the user.

---

## iOS App Setup

### Option 1: Using Google Sign-In SDK (Recommended)

#### Step 1: Create Google Cloud Project

1. Go to [Google Cloud Console](https://console.cloud.google.com/)
2. Create a new project (or use existing)
3. Enable **Google+ API** or **Google Identity Services**

#### Step 2: Create OAuth 2.0 Credentials

1. Go to **APIs & Services** → **Credentials**
2. Click **Create Credentials** → **OAuth client ID**
3. Application type: **iOS**
4. Bundle ID: `com.toper.FastTrack` (match your Xcode bundle ID)
5. Click **Create**
6. Copy the **Client ID** (looks like: `123456789-abcdefg.apps.googleusercontent.com`)

#### Step 3: Add Google Sign-In to iOS App

**Install via SPM (Swift Package Manager)**:

1. In Xcode: File → Add Package Dependencies
2. Enter: `https://github.com/google/GoogleSignIn-iOS`
3. Version: 7.0.0 or later
4. Click Add Package

**Or install via CocoaPods**:

```ruby
# Podfile
pod 'GoogleSignIn'
```

Then run: `pod install`

#### Step 4: Configure Info.plist

Add your Google Client ID to `Info.plist`:

```xml
<key>GIDClientID</key>
<string>YOUR_CLIENT_ID_HERE.apps.googleusercontent.com</string>

<key>CFBundleURLTypes</key>
<array>
    <dict>
        <key>CFBundleTypeRole</key>
        <string>Editor</string>
        <key>CFBundleURLSchemes</key>
        <array>
            <string>com.googleusercontent.apps.YOUR_REVERSED_CLIENT_ID</string>
        </array>
    </dict>
</array>
```

**Note**: For the URL scheme, reverse your client ID. Example:
- Client ID: `123456-abc.apps.googleusercontent.com`
- URL Scheme: `com.googleusercontent.apps.123456-abc`

#### Step 5: Update SignInView

Replace `SignInView.swift` with `SignInView_Updated.swift`:

```bash
cd ios/FastTrack/FastTrack/Views
mv SignInView.swift SignInView_Old.swift
mv SignInView_Updated.swift SignInView.swift
```

#### Step 6: Build and Test

1. Build app: `Cmd + B`
2. Run on device or simulator: `Cmd + R`
3. Tap "Sign in with Google"
4. Complete Google sign-in flow
5. Should see main app screen ✅

---

### Option 2: Firebase Authentication (Alternative)

If you want to add email/password, phone auth, etc. in the future, Firebase is a good choice.

#### Setup:

1. Create Firebase project at [Firebase Console](https://console.firebase.google.com/)
2. Add iOS app with bundle ID
3. Download `GoogleService-Info.plist`
4. Add to Xcode project
5. Install Firebase SDK:
   ```
   https://github.com/firebase/firebase-ios-sdk
   ```
6. Enable Google Sign-In in Firebase Console → Authentication → Sign-in methods

**Benefits**:
- Supports many providers: Google, Facebook, Twitter, GitHub, email/password, phone, etc.
- Built-in user management
- Easy to add more auth methods later

---

## Testing

### Test Flow:

1. **Launch app** → Shows sign in screen
2. **Tap "Sign in with Google"** → Google consent screen appears
3. **Select Google account** → Authorize app
4. **Success** → App shows main screen with map
5. **Verify backend** → User created in database

### Check Backend:

```bash
# SSH to server
ssh -p 2222 jtoper@10.0.0.102

# Connect to database
kubectl exec -it deployment/fasttrack-postgres -- psql -U fasttrack -d fasttrack

# Check users
SELECT id, email, full_name, auth_provider FROM users;

# Should see entries with auth_provider = 'google'
```

---

## Comparison: Apple vs Google Sign In

| Feature | Apple Sign In | Google Sign In |
|---------|---------------|----------------|
| **Setup Complexity** | Medium (capabilities) | Medium (Cloud Console) |
| **Works on iOS** | ✅ Yes | ✅ Yes |
| **Works on Android** | ❌ No | ✅ Yes |
| **Works on Web** | ❌ No | ✅ Yes |
| **Simulator Support** | ⚠️ Limited | ✅ Good |
| **Xcode Capabilities** | ✅ Required | ❌ Not required |
| **Privacy** | ✅ Hide email option | ⚠️ Shows real email |
| **User Base** | iOS users | Everyone |
| **Cost** | Free | Free |

**Recommendation**: Offer **both**! Let users choose their preferred method.

---

## Multiple Auth Providers

Users can sign in with either Apple or Google. The backend handles both:

```
User A: Signs in with Apple → Creates user with apple_user_id
User B: Signs in with Google → Creates user with google_user_id
User A: Can't sign in with Google (different account)
User B: Can't sign in with Apple (different account)
```

### Account Linking (Future Enhancement):

If you want users to link multiple auth providers to one account:

1. Add `account_links` table
2. Link by email address
3. Allow user to connect Google + Apple to same account

For now, each auth provider creates a separate account.

---

## Backend API Endpoints

### Google Sign In:
```bash
POST https://fast.toper.dev/api/v1/auth/google
Content-Type: application/json

{
  "id_token": "eyJhbGciOiJSUzI1NiIsImtpZCI6..."
}
```

**Response**:
```json
{
  "token": "eyJhbGciOiJIUzI1NiIs...",
  "refresh_token": "eyJhbGciOiJIUzI1NiIs...",
  "user": {
    "id": 1,
    "email": "user@gmail.com",
    "full_name": "John Doe",
    "google_user_id": "1234567890",
    "auth_provider": "google"
  }
}
```

### Apple Sign In:
```bash
POST https://fast.toper.dev/api/v1/auth/apple
Content-Type: application/json

{
  "identity_token": "eyJraWQiOiJlWGF1bm1MIn...",
  "auth_code": "c1234567890abcdef...",
  "full_name": "John Doe",
  "email": "user@privaterelay.appleid.com"
}
```

---

## Troubleshooting

### Error: "Google Client ID not configured"

**Fix**: Add `GIDClientID` to Info.plist

### Error: "Unable to find root view controller"

**Fix**: This happens in SwiftUI previews. Test on actual device/simulator, not preview.

### Error: "Invalid client ID"

**Fix**: 
1. Check Client ID matches in Google Cloud Console
2. Make sure bundle ID matches
3. Client ID should end with `.apps.googleusercontent.com`

### Error: "redirect_uri_mismatch"

**Fix**: Add URL scheme to Info.plist with reversed client ID

### Google sign in works but backend returns 401

**Fix**: 
1. Backend can't verify token
2. Check network connectivity
3. Check backend logs: `kubectl logs -l app=fasttrack-api`

---

## Production Checklist

Before App Store / Production:

- [ ] Google OAuth consent screen configured (in Google Cloud Console)
- [ ] App domain verified
- [ ] Privacy policy URL added
- [ ] Terms of service URL added
- [ ] App icon and branding configured
- [ ] Both Apple and Google sign in tested
- [ ] Account data handling documented
- [ ] GDPR compliance if serving EU users

---

## Migration Path

Current users with Apple Sign In will continue to work. New features:

1. **Now**: Users can choose Apple or Google
2. **Soon**: Add email/password option
3. **Later**: Add Facebook, Twitter, GitHub, etc.
4. **Future**: Account linking (merge Apple + Google accounts)

---

## Summary

✅ **Google Sign In added as alternative to Apple Sign In**  
✅ **Works on all platforms (iOS, Android, web)**  
✅ **No Xcode capabilities required**  
✅ **Backend already supports it**  
⏳ **Need to configure Google Cloud project and add SDK to iOS app**

See implementation files:
- Backend: `google_auth.go`
- iOS: `GoogleSignInManager.swift`, `SignInView_Updated.swift`
