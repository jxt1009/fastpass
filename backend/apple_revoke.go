package main

import (
	"crypto/ecdsa"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"os"
	"strings"
	"time"

	"github.com/golang-jwt/jwt/v5"
)

var errAppleRevocationNotConfigured = errors.New("apple revocation is not configured")

func revokeAppleAuthorizationCode(authCode string) error {
	if authCode == "" {
		return errors.New("apple authorization code is required")
	}

	clientID := os.Getenv("APPLE_APP_BUNDLE_ID")
	teamID := os.Getenv("APPLE_TEAM_ID")
	keyID := os.Getenv("APPLE_KEY_ID")
	privateKeyPEM := normalizePEMEnv(os.Getenv("APPLE_PRIVATE_KEY"))
	if clientID == "" {
		clientID = "com.toper.FastTrack"
	}
	if teamID == "" || keyID == "" || privateKeyPEM == "" {
		return errAppleRevocationNotConfigured
	}

	clientSecret, err := generateAppleClientSecret(teamID, keyID, clientID, privateKeyPEM)
	if err != nil {
		return fmt.Errorf("generate Apple client secret: %w", err)
	}

	form := url.Values{}
	form.Set("client_id", clientID)
	form.Set("client_secret", clientSecret)
	form.Set("token", authCode)
	form.Set("token_type_hint", "authorization_code")

	resp, err := http.PostForm("https://appleid.apple.com/auth/revoke", form)
	if err != nil {
		return fmt.Errorf("call Apple revoke endpoint: %w", err)
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return fmt.Errorf("apple revoke failed with status %d", resp.StatusCode)
	}

	return nil
}

func generateAppleClientSecret(teamID, keyID, clientID, privateKeyPEM string) (string, error) {
	block, _ := pem.Decode([]byte(privateKeyPEM))
	if block == nil {
		return "", errors.New("invalid Apple private key PEM")
	}

	privateKey, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return "", fmt.Errorf("parse PKCS8 private key: %w", err)
	}

	signingKey, ok := privateKey.(*ecdsa.PrivateKey)
	if !ok {
		return "", errors.New("Apple private key must be ECDSA")
	}

	now := time.Now()
	token := jwt.NewWithClaims(jwt.SigningMethodES256, jwt.RegisteredClaims{
		Issuer:    teamID,
		Subject:   clientID,
		Audience:  jwt.ClaimStrings{"https://appleid.apple.com"},
		IssuedAt:  jwt.NewNumericDate(now),
		ExpiresAt: jwt.NewNumericDate(now.Add(5 * time.Minute)),
	})
	token.Header["kid"] = keyID

	signed, err := token.SignedString(signingKey)
	if err != nil {
		return "", fmt.Errorf("sign Apple client secret: %w", err)
	}

	return signed, nil
}

func normalizePEMEnv(value string) string {
	if value == "" {
		return ""
	}
	return strings.ReplaceAll(value, `\n`, "\n")
}
