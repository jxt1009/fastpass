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
	"sync"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var jwtSecret []byte

const (
	tokenTypeAccess   = "access"
	tokenTypeRefresh  = "refresh"
	legacyRefreshTTL  = 6 * 24 * time.Hour
	appleBundleID     = "com.toper.FastTrack"
	legacyAppleAppID  = "com.toper.FastPass"
	appleJWKSCacheTTL = 6 * time.Hour
)

var applePublicKeyCache = struct {
	sync.RWMutex
	keys      map[string]*rsa.PublicKey
	fetchedAt time.Time
}{}

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
	TokenType   string `json:"token_type"`
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
	appleUserID := ""
	if user.AppleUserID != nil {
		appleUserID = *user.AppleUserID
	}

	claims := JWTClaims{
		UserID:      user.ID,
		AppleUserID: appleUserID,
		Email:       user.Email,
		TokenType:   tokenTypeAccess,
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
	appleUserID := ""
	if user.AppleUserID != nil {
		appleUserID = *user.AppleUserID
	}

	claims := JWTClaims{
		UserID:      user.ID,
		AppleUserID: appleUserID,
		Email:       user.Email,
		TokenType:   tokenTypeRefresh,
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

func requireTokenType(claims *JWTClaims, expectedType string) error {
	if claims.TokenType == "" {
		if expectedType == tokenTypeAccess {
			return nil
		}
		if expectedType == tokenTypeRefresh && isLegacyRefreshToken(claims) {
			return nil
		}
		return errors.New("token type missing")
	}
	if claims.TokenType != expectedType {
		return fmt.Errorf("unexpected token type: %s", claims.TokenType)
	}
	return nil
}

func isLegacyRefreshToken(claims *JWTClaims) bool {
	if claims.ExpiresAt == nil || claims.IssuedAt == nil {
		return false
	}
	return claims.ExpiresAt.Time.Sub(claims.IssuedAt.Time) >= legacyRefreshTTL
}

func verifyAppleIdentityToken(identityToken string) (*AppleIDTokenClaims, error) {
	// Parse the token without verification first to get the header
	token, _, err := new(jwt.Parser).ParseUnverified(identityToken, jwt.MapClaims{})
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
	claims := jwt.MapClaims{}
	token, err = jwt.ParseWithClaims(identityToken, claims, func(token *jwt.Token) (interface{}, error) {
		if !isSupportedAppleSigningMethod(token.Method) {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return publicKey, nil
	})

	if err != nil {
		return nil, fmt.Errorf("failed to verify token: %w", err)
	}

	if !token.Valid {
		return nil, errors.New("invalid token claims")
	}

	issuer, err := requiredStringClaim(claims, "iss")
	if err != nil {
		return nil, err
	}
	if issuer != "https://appleid.apple.com" {
		return nil, errors.New("invalid issuer")
	}

	audiences := claimAudiences(claims["aud"])
	if len(audiences) == 0 {
		return nil, errors.New("token missing audience")
	}
	if !hasAllowedAppleAudience(audiences) {
		return nil, fmt.Errorf("invalid audience: got %q, allowed %q", strings.Join(audiences, ", "), strings.Join(allowedAppleAudiences(), ", "))
	}

	expiresAt, err := claims.GetExpirationTime()
	if err != nil {
		return nil, fmt.Errorf("invalid expiration: %w", err)
	}
	if expiresAt == nil || time.Now().After(expiresAt.Time) {
		return nil, errors.New("token expired")
	}

	subject, err := requiredStringClaim(claims, "sub")
	if err != nil {
		return nil, err
	}
	email, _ := optionalStringClaim(claims, "email")
	emailVerified, _ := optionalStringClaim(claims, "email_verified")
	isPrivateEmail, _ := optionalStringClaim(claims, "is_private_email")
	issuedAt, _ := claims.GetIssuedAt()

	return &AppleIDTokenClaims{
		Iss:            issuer,
		Aud:            audiences[0],
		Exp:            expiresAt.Time.Unix(),
		Iat:            unixTime(issuedAt),
		Sub:            subject,
		Email:          email,
		EmailVerified:  emailVerified,
		IsPrivateEmail: isPrivateEmail,
	}, nil
}

func allowedAppleAudiences() []string {
	seen := make(map[string]struct{}, 3)
	audiences := make([]string, 0, 3)
	add := func(audience string) {
		audience = strings.TrimSpace(audience)
		if audience == "" {
			return
		}
		if _, exists := seen[audience]; exists {
			return
		}
		seen[audience] = struct{}{}
		audiences = append(audiences, audience)
	}

	for _, audience := range strings.Split(os.Getenv("APPLE_APP_BUNDLE_ID"), ",") {
		add(audience)
	}
	add(appleBundleID)
	add(legacyAppleAppID)

	return audiences
}

func isAllowedAppleAudience(audience string) bool {
	for _, allowed := range allowedAppleAudiences() {
		if strings.EqualFold(strings.TrimSpace(audience), allowed) {
			return true
		}
	}
	return false
}

func hasAllowedAppleAudience(audiences []string) bool {
	for _, audience := range audiences {
		if isAllowedAppleAudience(audience) {
			return true
		}
	}
	return false
}

func claimAudiences(value any) []string {
	switch raw := value.(type) {
	case string:
		if strings.TrimSpace(raw) == "" {
			return nil
		}
		return []string{strings.TrimSpace(raw)}
	case []any:
		audiences := make([]string, 0, len(raw))
		for _, entry := range raw {
			if text, ok := entry.(string); ok && strings.TrimSpace(text) != "" {
				audiences = append(audiences, strings.TrimSpace(text))
			}
		}
		return audiences
	case []string:
		audiences := make([]string, 0, len(raw))
		for _, entry := range raw {
			if strings.TrimSpace(entry) != "" {
				audiences = append(audiences, strings.TrimSpace(entry))
			}
		}
		return audiences
	default:
		return nil
	}
}

func requiredStringClaim(claims jwt.MapClaims, name string) (string, error) {
	value, ok := claims[name]
	if !ok {
		return "", fmt.Errorf("token missing %s", name)
	}
	text, err := optionalStringLikeClaim(value)
	if err != nil || text == "" {
		return "", fmt.Errorf("invalid %s claim", name)
	}
	return text, nil
}

func optionalStringClaim(claims jwt.MapClaims, name string) (string, error) {
	value, ok := claims[name]
	if !ok {
		return "", nil
	}
	return optionalStringLikeClaim(value)
}

func optionalStringLikeClaim(value any) (string, error) {
	switch raw := value.(type) {
	case string:
		return raw, nil
	case bool:
		if raw {
			return "true", nil
		}
		return "false", nil
	default:
		return "", fmt.Errorf("unsupported claim type %T", value)
	}
}

func unixTime(ts *jwt.NumericDate) int64 {
	if ts == nil {
		return 0
	}
	return ts.Time.Unix()
}

func isSupportedAppleSigningMethod(method jwt.SigningMethod) bool {
	_, ok := method.(*jwt.SigningMethodRSA)
	return ok
}

func getApplePublicKey(kid string) (*rsa.PublicKey, error) {
	if key := cachedApplePublicKey(kid); key != nil {
		return key, nil
	}
	if err := refreshApplePublicKeys(); err != nil {
		if key := cachedApplePublicKey(kid); key != nil {
			return key, nil
		}
		return nil, err
	}
	if key := cachedApplePublicKey(kid); key != nil {
		return key, nil
	}
	return nil, fmt.Errorf("apple public key %q not found", kid)
}

func cachedApplePublicKey(kid string) *rsa.PublicKey {
	applePublicKeyCache.RLock()
	defer applePublicKeyCache.RUnlock()

	if time.Since(applePublicKeyCache.fetchedAt) > appleJWKSCacheTTL {
		return nil
	}
	return applePublicKeyCache.keys[kid]
}

func refreshApplePublicKeys() error {
	// Fetch Apple's public keys
	resp, err := http.Get("https://appleid.apple.com/auth/keys")
	if err != nil {
		return err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("unexpected JWKS status %d", resp.StatusCode)
	}

	var keys ApplePublicKeys
	if err := json.NewDecoder(resp.Body).Decode(&keys); err != nil {
		return err
	}

	parsedKeys := make(map[string]*rsa.PublicKey, len(keys.Keys))
	for _, key := range keys.Keys {
		parsedKey, err := parseApplePublicKey(key)
		if err != nil {
			return err
		}
		parsedKeys[key.Kid] = parsedKey
	}

	applePublicKeyCache.Lock()
	defer applePublicKeyCache.Unlock()
	applePublicKeyCache.keys = parsedKeys
	applePublicKeyCache.fetchedAt = time.Now()

	return nil
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
