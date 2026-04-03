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
	user := User{Email: "test@example.com", AppleUserID: "apple.123"}
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
}

func TestValidateJWT_ExpiredToken(t *testing.T) {
	user := User{Email: "test@example.com"}
	user.ID = 1

	// Manually create an already-expired token
	claims := JWTClaims{
		UserID: 1,
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
		UserID: 99,
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

	// Refresh token should expire ~30 days from now
	expiry := claims.ExpiresAt.Time
	daysUntilExpiry := time.Until(expiry).Hours() / 24
	if daysUntilExpiry < 25 || daysUntilExpiry > 32 {
		t.Errorf("expected refresh token to expire in ~30 days, got %.1f days", daysUntilExpiry)
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
