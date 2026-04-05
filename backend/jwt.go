package main

import (
	"crypto/rsa"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"math/big"
	"net/http"
	"os"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var jwtSecret []byte

func initJWTSecret() {
	secret := os.Getenv("JWT_SECRET")
	if secret == "" {
		slog.Error("JWT_SECRET environment variable is not set — refusing to start")
		os.Exit(1)
	}
	jwtSecret = []byte(secret)
}

type JWTClaims struct {
	UserID      uint   `json:"user_id"`
	AppleUserID string `json:"apple_user_id"`
	Email       string `json:"email"`
	jwt.RegisteredClaims
}

// Apple's public keys for verifying tokens
type ApplePublicKey struct {
	Kty string `json:"kty"`
	Kid string `json:"kid"`
	Use string `json:"use"`
	Alg string `json:"alg"`
	N   string `json:"n"`
	E   string `json:"e"`
}

type ApplePublicKeys struct {
	Keys []ApplePublicKey `json:"keys"`
}

type AppleIDTokenClaims struct {
	Iss            string `json:"iss"`
	Aud            string `json:"aud"`
	Exp            int64  `json:"exp"`
	Iat            int64  `json:"iat"`
	Sub            string `json:"sub"` // Apple User ID
	Email          string `json:"email"`
	EmailVerified  string `json:"email_verified"`
	IsPrivateEmail string `json:"is_private_email"`
	jwt.RegisteredClaims
}

func generateJWT(user User) (string, error) {
	claims := JWTClaims{
		UserID:      user.ID,
		AppleUserID: user.AppleUserID,
		Email:       user.Email,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(2 * time.Hour)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "triprank-api",
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(jwtSecret)
}

func generateRefreshToken(user User) (string, error) {
	claims := JWTClaims{
		UserID:      user.ID,
		AppleUserID: user.AppleUserID,
		Email:       user.Email,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(7 * 24 * time.Hour)), // 7 days
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			Issuer:    "triprank-api",
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	return token.SignedString(jwtSecret)
}

func validateJWT(tokenString string) (*JWTClaims, error) {
	token, err := jwt.ParseWithClaims(tokenString, &JWTClaims{}, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return jwtSecret, nil
	})

	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(*JWTClaims); ok && token.Valid {
		return claims, nil
	}

	return nil, errors.New("invalid token")
}

func verifyAppleIdentityToken(identityToken string) (*AppleIDTokenClaims, error) {
	// Parse the token without verification first to get the header
	token, _, err := new(jwt.Parser).ParseUnverified(identityToken, &AppleIDTokenClaims{})
	if err != nil {
		return nil, fmt.Errorf("failed to parse token: %w", err)
	}

	// Get the kid from header
	kid, ok := token.Header["kid"].(string)
	if !ok {
		return nil, errors.New("no kid in token header")
	}

	// Fetch Apple's public keys
	publicKey, err := getApplePublicKey(kid)
	if err != nil {
		return nil, fmt.Errorf("failed to get public key: %w", err)
	}

	// Verify the token with the public key
	token, err = jwt.ParseWithClaims(identityToken, &AppleIDTokenClaims{}, func(token *jwt.Token) (interface{}, error) {
		return publicKey, nil
	})

	if err != nil {
		return nil, fmt.Errorf("failed to verify token: %w", err)
	}

	if claims, ok := token.Claims.(*AppleIDTokenClaims); ok && token.Valid {
		// Verify issuer
		if claims.Iss != "https://appleid.apple.com" {
			return nil, errors.New("invalid issuer")
		}

		// Verify audience matches the app bundle ID
		expectedAud := os.Getenv("APPLE_APP_BUNDLE_ID")
		if expectedAud == "" {
			expectedAud = "dev.toper.FastTrack"
		}
		if claims.Aud != expectedAud {
			return nil, fmt.Errorf("invalid audience: got %q, expected %q", claims.Aud, expectedAud)
		}

		// Verify expiration
		if time.Now().Unix() > claims.Exp {
			return nil, errors.New("token expired")
		}

		return claims, nil
	}

	return nil, errors.New("invalid token claims")
}

func getApplePublicKey(kid string) (*rsa.PublicKey, error) {
	// Fetch Apple's public keys
	resp, err := http.Get("https://appleid.apple.com/auth/keys")
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()

	var keys ApplePublicKeys
	if err := json.NewDecoder(resp.Body).Decode(&keys); err != nil {
		return nil, err
	}

	// Find the key with matching kid
	for _, key := range keys.Keys {
		if key.Kid == kid {
			return parseApplePublicKey(key)
		}
	}

	return nil, errors.New("public key not found")
}

func parseApplePublicKey(key ApplePublicKey) (*rsa.PublicKey, error) {
	nBytes, err := base64.RawURLEncoding.DecodeString(key.N)
	if err != nil {
		return nil, err
	}

	eBytes, err := base64.RawURLEncoding.DecodeString(key.E)
	if err != nil {
		return nil, err
	}

	n := new(big.Int).SetBytes(nBytes)
	e := 0
	for _, b := range eBytes {
		e = e<<8 + int(b)
	}

	return &rsa.PublicKey{
		N: n,
		E: e,
	}, nil
}

func extractBearerToken(authHeader string) (string, error) {
	if authHeader == "" {
		return "", errors.New("no authorization header")
	}

	parts := strings.Split(authHeader, " ")
	if len(parts) != 2 || parts[0] != "Bearer" {
		return "", errors.New("invalid authorization header format")
	}

	return parts[1], nil
}
