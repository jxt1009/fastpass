package main

import (
	"encoding/base64"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"strings"

	"github.com/gin-gonic/gin"
)

func appleSignIn(c *gin.Context) {
	var req AppleSignInRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify Apple's identity token
	claims, err := verifyAppleIdentityToken(req.IdentityToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid Apple token", "details": err.Error()})
		return
	}

	// Check if user exists
	var user User
	result := db.Where("apple_user_id = ?", claims.Sub).First(&user)

	if result.Error != nil {
		// Create new user
		user = User{
			AppleUserID: claims.Sub,
			Email:       claims.Email,
			FullName:    req.FullName,
		}

		// Use email from request if provided (first time sign in)
		if req.Email != "" && user.Email == "" {
			user.Email = req.Email
		}

		if err := db.Create(&user).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user"})
			return
		}
	}

	// Generate JWT tokens
	token, err := generateJWT(user)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	refreshToken, err := generateRefreshToken(user)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate refresh token"})
		return
	}

	c.JSON(http.StatusOK, AuthResponse{
		Token:        token,
		RefreshToken: refreshToken,
		User:         user,
	})
}

func refreshToken(c *gin.Context) {
	var req RefreshTokenRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Validate refresh token
	claims, err := validateJWT(req.RefreshToken)
	if err != nil {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid refresh token"})
		return
	}

	// Get user from database
	var user User
	if err := db.First(&user, claims.UserID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// Generate new tokens
	token, err := generateJWT(user)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate token"})
		return
	}

	newRefreshToken, err := generateRefreshToken(user)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to generate refresh token"})
		return
	}

	c.JSON(http.StatusOK, AuthResponse{
		Token:        token,
		RefreshToken: newRefreshToken,
		User:         user,
	})
}

func getCurrentUser(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var user User
	if err := db.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	c.JSON(http.StatusOK, user)
}

func updateProfile(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var req UpdateProfileRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	var user User
	if err := db.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	user.Username = req.Username
	user.Country = req.Country

	// Update legacy car fields for backward compatibility
	user.CarMake = req.CarMake
	user.CarModel = req.CarModel
	user.CarYear = req.CarYear
	user.CarTrim = req.CarTrim

	// Update garage fields
	user.Garage = req.Garage
	user.SelectedCarID = req.SelectedCarID

	// Update privacy setting only when explicitly provided
	if req.IsPublic != nil {
		user.IsPublic = *req.IsPublic
	}

	if err := db.Save(&user).Error; err != nil {
		// Detect unique constraint violation on username
		if strings.Contains(err.Error(), "unique") || strings.Contains(err.Error(), "23505") {
			c.JSON(http.StatusConflict, gin.H{"error": "Username already taken"})
			return
		}
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update profile"})
		return
	}

	c.JSON(http.StatusOK, user)
}

// uploadAvatar handles PUT /api/v1/profile/avatar
// Accepts {"image_data": "<base64 JPEG>"} and saves to disk.
func uploadAvatar(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var req struct {
		ImageData string `json:"image_data" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image_data required"})
		return
	}

	data, err := base64.StdEncoding.DecodeString(req.ImageData)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid base64"})
		return
	}

	// Reject payloads larger than 8 MB decoded
	if len(data) > 8*1024*1024 {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "image too large (max 8 MB)"})
		return
	}

	dir := filepath.Join("uploads", "avatars")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "storage error"})
		return
	}

	filename := fmt.Sprintf("%d.jpg", userID)
	dst := filepath.Join(dir, filename)
	if err := os.WriteFile(dst, data, 0o644); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "write error"})
		return
	}

	baseURL := os.Getenv("BASE_URL")
	if baseURL == "" {
		baseURL = "https://fast.toper.dev"
	}
	avatarURL := fmt.Sprintf("%s/uploads/avatars/%s", baseURL, filename)

	db.Model(&User{}).Where("id = ?", userID).Update("avatar_url", avatarURL)

	c.JSON(http.StatusOK, gin.H{"avatar_url": avatarURL})
}

// getCarStats returns the stored car stats JSON blob for the authenticated user.
func getCarStats(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	var user User
	if err := db.Select("car_stats_data").First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}
	// Return as raw JSON so the iOS client can decode directly
	c.Header("Content-Type", "application/json")
	if user.CarStatsData == "" {
		c.String(http.StatusOK, "{}")
		return
	}
	c.String(http.StatusOK, user.CarStatsData)
}

// putCarStats stores the car stats JSON blob for the authenticated user.
func putCarStats(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	var req struct {
		StatsData string `json:"stats_data" binding:"required"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": "stats_data required"})
		return
	}
	db.Model(&User{}).Where("id = ?", userID).Update("car_stats_data", req.StatsData)
	c.JSON(http.StatusOK, gin.H{"ok": true})
}
