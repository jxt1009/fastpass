package main

import (
	"encoding/json"
	"fmt"
	"io"
	"net/http"
	"net/url"
	"os"

	"github.com/gin-gonic/gin"
)

// Google token endpoint
const googleTokenEndpoint = "https://oauth2.googleapis.com/token"

// googleTokenResponse is returned by Google's token exchange endpoint
type googleTokenResponse struct {
AccessToken string `json:"access_token"`
IDToken     string `json:"id_token"`
TokenType   string `json:"token_type"`
ExpiresIn   int    `json:"expires_in"`
Error       string `json:"error"`
}

// googleUserInfo is extracted from the id_token by calling userinfo
type googleUserInfo struct {
Sub           string `json:"sub"`
Email         string `json:"email"`
EmailVerified bool   `json:"email_verified"`
Name          string `json:"name"`
GivenName     string `json:"given_name"`
FamilyName    string `json:"family_name"`
Picture       string `json:"picture"`
}

// handleGoogleSignIn exchanges a PKCE authorization code for tokens, then signs in
func handleGoogleSignIn(c *gin.Context) {
var req GoogleSignInRequest
if err := c.ShouldBindJSON(&req); err != nil {
c.JSON(http.StatusBadRequest, gin.H{"error": "Invalid request"})
return
}

clientID := os.Getenv("GOOGLE_CLIENT_ID")
clientSecret := os.Getenv("GOOGLE_CLIENT_SECRET")
if clientID == "" {
c.JSON(http.StatusInternalServerError, gin.H{"error": "Google OAuth not configured"})
return
}

// Exchange authorization code for tokens (PKCE — no client_secret required for iOS)
form := url.Values{}
form.Set("code", req.Code)
form.Set("client_id", clientID)
form.Set("code_verifier", req.CodeVerifier)
form.Set("redirect_uri", req.RedirectURI)
form.Set("grant_type", "authorization_code")
if clientSecret != "" {
form.Set("client_secret", clientSecret)
}

resp, err := http.PostForm(googleTokenEndpoint, form)
if err != nil {
c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to reach Google: " + err.Error()})
return
}
defer resp.Body.Close()

body, _ := io.ReadAll(resp.Body)

var tokenResp googleTokenResponse
if err := json.Unmarshal(body, &tokenResp); err != nil || tokenResp.IDToken == "" {
c.JSON(http.StatusUnauthorized, gin.H{"error": "Token exchange failed: " + string(body)})
return
}

// Fetch user profile using the access token
userInfo, err := fetchGoogleUserInfo(tokenResp.AccessToken)
if err != nil {
c.JSON(http.StatusUnauthorized, gin.H{"error": "Failed to fetch user info: " + err.Error()})
return
}

if !userInfo.EmailVerified {
c.JSON(http.StatusUnauthorized, gin.H{"error": "Google email not verified"})
return
}

// Find or create user
var user User
result := db.Where("google_user_id = ?", userInfo.Sub).First(&user)
if result.Error != nil {
// Also check by email in case user signed up with Apple
db.Where("email = ?", userInfo.Email).First(&user)
if user.ID == 0 {
user = User{
GoogleUserID: &userInfo.Sub,
Email:        userInfo.Email,
FullName:     userInfo.Name,
AuthProvider: "google",
}
if err := db.Create(&user).Error; err != nil {
c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user"})
return
}
} else {
sub := userInfo.Sub; user.GoogleUserID = &sub
db.Save(&user)
}
} else {
user.Email = userInfo.Email
user.FullName = userInfo.Name
db.Save(&user)
}

accessToken, err := generateJWT(user)
if err != nil {
c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate access token"})
return
}

refreshToken, err := generateRefreshToken(user)
if err != nil {
c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate refresh token"})
return
}

c.JSON(http.StatusOK, AuthResponse{
Token:        accessToken,
RefreshToken: refreshToken,
User:         user,
})
}

// fetchGoogleUserInfo calls Google's userinfo endpoint with the access token
func fetchGoogleUserInfo(accessToken string) (*googleUserInfo, error) {
req, _ := http.NewRequest("GET", "https://www.googleapis.com/oauth2/v3/userinfo", nil)
req.Header.Set("Authorization", "Bearer "+accessToken)

resp, err := http.DefaultClient.Do(req)
if err != nil {
return nil, fmt.Errorf("request failed: %w", err)
}
defer resp.Body.Close()

body, _ := io.ReadAll(resp.Body)
if resp.StatusCode != http.StatusOK {
return nil, fmt.Errorf("userinfo error: %s", string(body))
}

var info googleUserInfo
if err := json.Unmarshal(body, &info); err != nil {
return nil, fmt.Errorf("parse error: %w", err)
}
return &info, nil
}
