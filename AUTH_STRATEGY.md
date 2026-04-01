# Authentication Strategy for FastTrack

## Recommendation: Apple Sign In + JWT

### Why This Approach?

1. **Apple Sign In** is:
   - ✅ Required by Apple if you offer any social login
   - ✅ Privacy-focused (hide email option)
   - ✅ Native iOS integration
   - ✅ Free (no additional costs)
   - ✅ Works with self-hosted backend

2. **JWT (JSON Web Tokens)** for session management:
   - ✅ Stateless (no session storage needed)
   - ✅ Works great with Kubernetes (any pod can verify)
   - ✅ Industry standard
   - ✅ Your PostgreSQL database is perfect for this

### Architecture Overview

```
iOS App → Apple Sign In → Backend verifies Apple token → Issues JWT → Client uses JWT for API calls
```

### Database Impact

**Minimal changes needed!** Just add a users table:

```sql
CREATE TABLE users (
    id SERIAL PRIMARY KEY,
    apple_user_id VARCHAR(255) UNIQUE NOT NULL,  -- Apple's unique identifier
    email VARCHAR(255),                           -- Optional (user can hide)
    full_name VARCHAR(255),
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW()
);

-- Update drives table to reference users
ALTER TABLE drives ADD COLUMN user_id INTEGER REFERENCES users(id);
-- Create index for performance
CREATE INDEX idx_drives_user_id ON drives(user_id);
```

Your existing PostgreSQL setup works perfectly!

## Implementation Plan

### Backend Changes (Go)

**Dependencies needed:**
```bash
go get github.com/golang-jwt/jwt/v5
go get github.com/dgrijalva/jwt-go  # Alternative
```

**New files to create:**
1. `auth.go` - Apple Sign In token verification
2. `jwt.go` - JWT generation and validation
3. `middleware.go` - Auth middleware for protected routes
4. Update `models.go` - Add User model
5. Update `handlers.go` - Add auth endpoints

**New endpoints:**
- `POST /api/v1/auth/apple` - Verify Apple token, return JWT
- `POST /api/v1/auth/refresh` - Refresh JWT token
- All existing endpoints - Add auth middleware

### iOS Changes (Swift)

**Built-in framework (no dependencies!):**
- Use `AuthenticationServices` framework

**New files to create:**
1. `AppleSignInManager.swift` - Handle Sign in with Apple
2. `AuthManager.swift` - Store/manage JWT tokens
3. `SignInView.swift` - Login screen

**Updates needed:**
- `APIService.swift` - Add JWT to request headers
- `FastTrackApp.swift` - Check auth state on launch
- Add login screen before main app

## Alternative Options

### Option 1: Apple Sign In (Recommended)
- **Pros**: Native, free, required anyway, privacy-focused
- **Cons**: iOS-only (need Google/other for Android later)
- **Database**: PostgreSQL ✅ (just add users table)
- **Complexity**: Low

### Option 2: Self-Hosted OAuth Provider (Keycloak/Authentik/Zitadel)
- **Pros**: Full-featured, supports many providers, admin UI
- **Cons**: Additional service to maintain, more complex
- **Database**: PostgreSQL ✅ (separate database for auth service)
- **Complexity**: High
- **Good for**: If you want multi-platform from day 1

### Option 3: Supabase Auth (Hosted or Self-Hosted)
- **Pros**: Complete auth solution, can self-host, good docs
- **Cons**: Another dependency, uses its own PostgreSQL
- **Database**: Would replace your current PostgreSQL setup
- **Complexity**: Medium

### Option 4: Firebase Auth
- **Pros**: Easy to use, handles everything
- **Cons**: Google-hosted (not self-hosted), costs at scale
- **Database**: Keep PostgreSQL for drives, Firebase for auth
- **Complexity**: Low

## Recommended: Start with Apple Sign In

This is the sweet spot for your use case:

### Phase 1: Apple Sign In Only (Now)
- Implement Apple Sign In on iOS
- Add JWT authentication to backend
- Add users table to PostgreSQL
- Takes ~4-6 hours to implement

### Phase 2: Add More Providers (Later)
When you want Android/web support:
- Add Google Sign In (similar flow)
- Add email/password (if needed)
- Consider migrating to Keycloak if you want centralized identity management

## Implementation Files Ready

I can create all the necessary files for Apple Sign In + JWT:

**Backend (Go):**
- ✅ User model
- ✅ Apple token verification
- ✅ JWT generation/validation
- ✅ Auth middleware
- ✅ Auth endpoints

**iOS (Swift):**
- ✅ Sign in with Apple integration
- ✅ Token storage
- ✅ Auth state management
- ✅ Login UI

**Database:**
- ✅ Migration script for users table

Would you like me to implement this? It will:
1. Keep your PostgreSQL database
2. Add authentication without external dependencies
3. Work with your Kubernetes setup
4. Be ready in ~10 minutes

## Security Considerations

- ✅ Apple validates the user identity
- ✅ Backend verifies Apple's JWT signature
- ✅ Backend issues its own JWT with short expiry
- ✅ Use refresh tokens for long-term access
- ✅ Store JWT in iOS Keychain (secure)
- ✅ HTTPS required (your K8s ingress handles this)

## Cost Impact

**$0** - Everything is free:
- Apple Sign In: Free
- JWT libraries: Open source
- PostgreSQL: You're already running it
- No auth service subscription needed

---

**My recommendation**: Start with Apple Sign In + JWT. It's the simplest, most iOS-native solution that works perfectly with your self-hosted infrastructure. Want me to implement it?
