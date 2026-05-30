package main

import (
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

func init() {
	// Set a test JWT secret for all jwt tests
	jwtSecret = []byte("test-secret-for-unit-tests-at-least-32-bytes-long")
}

func TestGenerateAndValidateJWT(t *testing.T) {
	appleUserID := "apple.123"
	user := User{Email: "test@example.com", AppleUserID: &appleUserID}
	user.ID = 42

	tokenString, err := generateJWT(user)
	if err != nil {
		t.Fatalf("generateJWT failed: %v", err)
	}
	if tokenString == "" {
		t.Fatal("expected non-empty token string")
	}

	claims, err := validateJWT(tokenString)
	if err != nil {
		t.Fatalf("validateJWT failed: %v", err)
	}
	if claims.UserID != 42 {
		t.Errorf("expected UserID 42, got %d", claims.UserID)
	}
	if claims.Email != "test@example.com" {
		t.Errorf("expected email test@example.com, got %s", claims.Email)
	}
	if claims.TokenType != tokenTypeAccess {
		t.Errorf("expected access token type, got %s", claims.TokenType)
	}
}

func TestValidateJWT_ExpiredToken(t *testing.T) {
	user := User{Email: "test@example.com"}
	user.ID = 1

	// Manually create an already-expired token
	claims := JWTClaims{
		UserID:    1,
		TokenType: tokenTypeAccess,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(-1 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now().Add(-2 * time.Hour)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	expired, _ := token.SignedString(jwtSecret)

	_, err := validateJWT(expired)
	if err == nil {
		t.Fatal("expected error for expired token, got nil")
	}
}

func TestValidateJWT_TamperedToken(t *testing.T) {
	user := User{Email: "test@example.com"}
	user.ID = 1

	tokenString, _ := generateJWT(user)

	// Tamper by appending a character to the signature
	tampered := tokenString + "X"

	_, err := validateJWT(tampered)
	if err == nil {
		t.Fatal("expected error for tampered token, got nil")
	}
}

func TestValidateJWT_WrongSecret(t *testing.T) {
	// Sign with a different secret
	otherSecret := []byte("completely-different-secret-key-here-64-chars-plus")
	claims := JWTClaims{
		UserID:    99,
		TokenType: tokenTypeAccess,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(1 * time.Hour)),
		},
	}
	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	badToken, _ := token.SignedString(otherSecret)

	_, err := validateJWT(badToken)
	if err == nil {
		t.Fatal("expected error for token signed with wrong secret, got nil")
	}
}

func TestGenerateRefreshToken(t *testing.T) {
	user := User{Email: "refresh@example.com"}
	user.ID = 7

	tokenString, err := generateRefreshToken(user)
	if err != nil {
		t.Fatalf("generateRefreshToken failed: %v", err)
	}

	claims, err := validateJWT(tokenString)
	if err != nil {
		t.Fatalf("validateJWT on refresh token failed: %v", err)
	}

	if claims.TokenType != tokenTypeRefresh {
		t.Fatalf("expected refresh token type, got %s", claims.TokenType)
	}

	// Refresh token should expire ~7 days from now
	expiry := claims.ExpiresAt.Time
	daysUntilExpiry := time.Until(expiry).Hours() / 24
	if daysUntilExpiry < 6 || daysUntilExpiry > 8 {
		t.Errorf("expected refresh token to expire in ~7 days, got %.1f days", daysUntilExpiry)
	}
}

func TestRequireTokenType_AcceptsLegacyRefreshToken(t *testing.T) {
	claims := &JWTClaims{
		UserID: 1,
		RegisteredClaims: jwt.RegisteredClaims{
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(7 * 24 * time.Hour)),
		},
	}

	if err := requireTokenType(claims, tokenTypeRefresh); err != nil {
		t.Fatalf("expected legacy refresh token to be accepted, got %v", err)
	}
}

func TestRequireTokenType_RejectsLegacyAccessTokenOnRefresh(t *testing.T) {
	claims := &JWTClaims{
		UserID: 1,
		RegisteredClaims: jwt.RegisteredClaims{
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(2 * time.Hour)),
		},
	}

	if err := requireTokenType(claims, tokenTypeRefresh); err == nil {
		t.Fatal("expected legacy access token to be rejected for refresh")
	}
}

func TestExtractBearerToken(t *testing.T) {
	tests := []struct {
		header  string
		want    string
		wantErr bool
	}{
		{"Bearer abc123", "abc123", false},
		{"", "", true},
		{"Basic abc123", "", true},
		{"Bearer", "", true},
		{"Bearer tok en", "", true},
	}

	for _, tt := range tests {
		got, err := extractBearerToken(tt.header)
		if (err != nil) != tt.wantErr {
			t.Errorf("extractBearerToken(%q): error = %v, wantErr %v", tt.header, err, tt.wantErr)
		}
		if got != tt.want {
			t.Errorf("extractBearerToken(%q): got %q, want %q", tt.header, got, tt.want)
		}
	}
}

func TestAllowedAppleAudiences_DefaultsToCurrentAndLegacyBundleIDs(t *testing.T) {
	t.Setenv("APPLE_APP_BUNDLE_ID", "")

	got := allowedAppleAudiences()
	want := []string{appleBundleID, legacyAppleAppID}

	if len(got) != len(want) {
		t.Fatalf("expected %d audiences, got %d: %v", len(want), len(got), got)
	}
	for i, audience := range want {
		if got[i] != audience {
			t.Fatalf("expected audience %d to be %q, got %q", i, audience, got[i])
		}
	}
}

func TestAllowedAppleAudiences_UsesConfiguredAllowlistOnce(t *testing.T) {
	t.Setenv("APPLE_APP_BUNDLE_ID", " com.example.FastTrack , com.toper.FastTrack , com.toper.FastPass ")

	got := allowedAppleAudiences()
	want := []string{"com.example.FastTrack", appleBundleID, legacyAppleAppID}

	if len(got) != len(want) {
		t.Fatalf("expected %d audiences, got %d: %v", len(want), len(got), got)
	}
	for i, audience := range want {
		if got[i] != audience {
			t.Fatalf("expected audience %d to be %q, got %q", i, audience, got[i])
		}
	}
}

func TestIsAllowedAppleAudience_AcceptsLegacyBundleID(t *testing.T) {
	t.Setenv("APPLE_APP_BUNDLE_ID", "")

	if !isAllowedAppleAudience(legacyAppleAppID) {
		t.Fatal("expected legacy FastPass audience to be accepted")
	}
	if !isAllowedAppleAudience("com.toper.fasttrack") {
		t.Fatal("expected case-insensitive canonical audience to be accepted")
	}
	if isAllowedAppleAudience("com.example.Unknown") {
		t.Fatal("expected unknown audience to be rejected")
	}
}

func TestClaimAudiences_SupportsStringAndArray(t *testing.T) {
	tests := []struct {
		name string
		raw  any
		want []string
	}{
		{name: "string", raw: "com.toper.FastTrack", want: []string{"com.toper.FastTrack"}},
		{name: "array", raw: []any{"com.toper.FastTrack", "com.toper.FastPass"}, want: []string{"com.toper.FastTrack", "com.toper.FastPass"}},
		{name: "empty", raw: []any{"", 1}, want: nil},
	}

	for _, tt := range tests {
		got := claimAudiences(tt.raw)
		if len(got) != len(tt.want) {
			t.Fatalf("%s: expected %d audiences, got %d (%v)", tt.name, len(tt.want), len(got), got)
		}
		for i, audience := range tt.want {
			if got[i] != audience {
				t.Fatalf("%s: expected audience %d to be %q, got %q", tt.name, i, audience, got[i])
			}
		}
	}
}

func TestIsSupportedAppleSigningMethod_RequiresRSA(t *testing.T) {
	if !isSupportedAppleSigningMethod(jwt.SigningMethodRS256) {
		t.Fatal("expected RS256 to be accepted for Apple identity tokens")
	}
	if isSupportedAppleSigningMethod(jwt.SigningMethodES256) {
		t.Fatal("expected ES256 to be rejected for Apple identity tokens")
	}
}
