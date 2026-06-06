package app

import (
	"bytes"
	"crypto/rand"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"image"
	_ "image/gif"
	_ "image/jpeg"
	_ "image/png"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
)

func generateUniqueUsername() string {
	b := make([]byte, 4)
	if _, err := rand.Read(b); err != nil {
		return fmt.Sprintf("user_%d", time.Now().UnixMilli())
	}
	return "user_" + hex.EncodeToString(b)
}

func appleSignIn(c *gin.Context) {
	var req AppleSignInRequest
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	// Verify Apple's identity token
	claims, err := verifyAppleIdentityToken(req.IdentityToken)
	if err != nil {
		logWithRequestID(c).Warn("apple sign-in failed", "details", err.Error())
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Invalid Apple token", "details": err.Error()})
		return
	}

	// Check if user exists
	var user User
	result := db.Where("apple_user_id = ?", claims.Sub).First(&user)

	if result.Error != nil {
		// Create new user
		appleUserID := claims.Sub
		user = User{
			AppleUserID:  &appleUserID,
			Email:        claims.Email,
			FullName:     req.FullName,
			Username:     generateUniqueUsername(),
			AuthProvider: "apple",
		}

		// Use email from request if provided (first time sign in)
		if req.Email != "" && user.Email == "" {
			user.Email = req.Email
		}

		if err := db.Create(&user).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to create user"})
			return
		}
		// Business metric: new Apple Sign-In signup
		userSignupsTotal.WithLabelValues("apple").Inc()
		logWithRequestID(c).Info("user signed up", "provider", "apple", "user_id", user.ID)
	} else if user.AuthProvider == "" {
		user.AuthProvider = "apple"
		if err := db.Model(&user).Update("auth_provider", user.AuthProvider).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to update user"})
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
	if err := requireTokenType(claims, tokenTypeRefresh); err != nil {
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
// Accepts {"image_data": "<base64 image>"} and saves a validated image to disk.
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

	ext, err := detectAvatarExtension(data)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	dir := filepath.Join("uploads", "avatars")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "storage error"})
		return
	}

	if err := deleteAvatarFiles(userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "storage error"})
		return
	}

	filename := fmt.Sprintf("%d%s", userID, ext)
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

func detectAvatarExtension(data []byte) (string, error) {
	config, format, err := image.DecodeConfig(bytes.NewReader(data))
	if err != nil {
		return "", errors.New("invalid image data")
	}
	if config.Width <= 0 || config.Height <= 0 {
		return "", errors.New("invalid image dimensions")
	}

	switch format {
	case "jpeg":
		return ".jpg", nil
	case "png":
		return ".png", nil
	case "gif":
		return ".gif", nil
	default:
		return "", errors.New("unsupported image format")
	}
}

func deleteAvatarFiles(userID uint) error {
	matches, err := filepath.Glob(filepath.Join("uploads", "avatars", fmt.Sprintf("%d.*", userID)))
	if err != nil {
		return err
	}
	for _, match := range matches {
		if err := os.Remove(match); err != nil && !errors.Is(err, os.ErrNotExist) {
			return err
		}
	}
	return nil
}

// uploadCarPhoto handles PUT /api/v1/garage/cars/:carId/photo
// Accepts {"image_data": "<base64 image>"} and writes a validated image to
// uploads/garage_cars/, then mutates the matching UserCar.photo_url inside
// the user's `garage` JSON blob. The blob is treated as opaque JSON to match
// the looser approach used by the avatar endpoint.
func uploadCarPhoto(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	carID := strings.TrimSpace(c.Param("carId"))
	if carID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "carId required"})
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

	if len(data) == 0 {
		c.JSON(http.StatusBadRequest, gin.H{"error": "image_data required"})
		return
	}

	// Reject payloads larger than 8 MB decoded
	if len(data) > 8*1024*1024 {
		c.JSON(http.StatusRequestEntityTooLarge, gin.H{"error": "image too large (max 8 MB)"})
		return
	}

	ext, err := detectAvatarExtension(data)
	if err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}

	dir := filepath.Join("uploads", "garage_cars")
	if err := os.MkdirAll(dir, 0o755); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "storage error"})
		return
	}

	var user User
	if err := db.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// Locate the matching car in the existing JSON blob. We do not parse it
	// as a typed struct — match the looser approach used by the avatar
	// endpoint and the rest of the garage round-trip path.
	cars, oldURL, err := findCarInGarage(user.Garage, carID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	saltBytes := make([]byte, 16)
	if _, err := rand.Read(saltBytes); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "storage error"})
		return
	}
	filename := fmt.Sprintf("%d_%s_%s%s", userID, carID, hex.EncodeToString(saltBytes), ext)
	dst := filepath.Join(dir, filename)
	if err := os.WriteFile(dst, data, 0o644); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "write error"})
		return
	}

	baseURL := os.Getenv("BASE_URL")
	if baseURL == "" {
		baseURL = "https://fast.toper.dev"
	}
	photoURL := fmt.Sprintf("%s/uploads/garage_cars/%s", baseURL, filename)

	// Best-effort: unlink the old file if it lived under our uploads dir.
	if oldURL != "" {
		if oldPath, ok := stripBaseURLPath(oldURL, baseURL, "garage_cars"); ok {
			if err := os.Remove(oldPath); err != nil && !errors.Is(err, os.ErrNotExist) {
				logWithRequestID(c).Warn("failed to remove previous car photo", "path", oldPath, "err", err.Error())
			}
		}
	}

	// Mutate the JSON blob: set the matching car's photo_url and marshal back.
	updated, err := setCarPhotoURLInGarage(cars, carID, photoURL)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to mutate garage"})
		return
	}
	blob, err := json.Marshal(updated)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to marshal garage"})
		return
	}
	if err := db.Model(&User{}).Where("id = ?", userID).Update("garage", string(blob)).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to persist garage"})
		return
	}

	c.JSON(http.StatusOK, CarPhotoResponse{PhotoURL: photoURL})
}

// deleteCarPhoto handles DELETE /api/v1/garage/cars/:carId/photo
// Clears the matching UserCar.photo_url inside the user's `garage` JSON
// blob and best-effort unlinks the file from disk.
func deleteCarPhoto(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	carID := strings.TrimSpace(c.Param("carId"))
	if carID == "" {
		c.JSON(http.StatusBadRequest, gin.H{"error": "carId required"})
		return
	}

	var user User
	if err := db.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	cars, oldURL, err := findCarInGarage(user.Garage, carID)
	if err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": err.Error()})
		return
	}

	updated, err := setCarPhotoURLInGarage(cars, carID, "")
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to mutate garage"})
		return
	}
	blob, err := json.Marshal(updated)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to marshal garage"})
		return
	}
	if err := db.Model(&User{}).Where("id = ?", userID).Update("garage", string(blob)).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "failed to persist garage"})
		return
	}

	if oldURL != "" {
		baseURL := os.Getenv("BASE_URL")
		if baseURL == "" {
			baseURL = "https://fast.toper.dev"
		}
		if oldPath, ok := stripBaseURLPath(oldURL, baseURL, "garage_cars"); ok {
			if err := os.Remove(oldPath); err != nil && !errors.Is(err, os.ErrNotExist) {
				logWithRequestID(c).Warn("failed to remove car photo on delete", "path", oldPath, "err", err.Error())
			}
		}
	}

	c.Status(http.StatusNoContent)
}

// findCarInGarage parses the user's `garage` JSON blob (treating it as
// opaque JSON) and locates the car with the given id. Returns the parsed
// cars slice (for re-marshalling) and the car.photo_url of the match
// (empty string if absent).
func findCarInGarage(blob string, carID string) ([]map[string]any, string, error) {
	raw := []byte(blob)
	if len(bytes.TrimSpace(raw)) == 0 {
		raw = []byte("[]")
	}
	var cars []map[string]any
	if err := json.Unmarshal(raw, &cars); err != nil {
		return nil, "", errors.New("garage blob is not valid JSON")
	}
	for _, car := range cars {
		if id, ok := car["id"].(string); ok && id == carID {
			url, _ := car["photo_url"].(string)
			return cars, url, nil
		}
	}
	return nil, "", errors.New("car not found in garage")
}

// setCarPhotoURLInGarage mutates the parsed cars slice in place, setting
// the matching car.photo_url to the supplied value. Returns the slice
// ready for marshalling.
func setCarPhotoURLInGarage(cars []map[string]any, carID string, photoURL string) ([]map[string]any, error) {
	for i, car := range cars {
		if id, ok := car["id"].(string); ok && id == carID {
			cars[i]["photo_url"] = photoURL
			return cars, nil
		}
	}
	return nil, errors.New("car not found in garage")
}

// stripBaseURLPath returns the local filesystem path for a URL we
// previously emitted, scoped to uploads/<subdir>/. Returns ok=false
// if the URL does not belong to us.
func stripBaseURLPath(url, baseURL, subdir string) (string, bool) {
	prefix := fmt.Sprintf("%s/uploads/%s/", baseURL, subdir)
	if !strings.HasPrefix(url, prefix) {
		return "", false
	}
	rel := strings.TrimPrefix(url, prefix)
	// Defensive: reject path traversal.
	if strings.Contains(rel, "..") || strings.Contains(rel, "/") {
		return "", false
	}
	return filepath.Join("uploads", subdir, rel), true
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

// putDisplaySettings saves unit_system and color_scheme for the authenticated user.
func putDisplaySettings(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	var req struct {
		UnitSystem  string `json:"unit_system"`
		ColorScheme string `json:"color_scheme"`
	}
	if err := c.ShouldBindJSON(&req); err != nil {
		c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
		return
	}
	updates := map[string]interface{}{}
	if req.UnitSystem != "" {
		updates["unit_system"] = req.UnitSystem
	}
	if req.ColorScheme != "" {
		updates["color_scheme"] = req.ColorScheme
	}
	if len(updates) > 0 {
		db.Model(&User{}).Where("id = ?", userID).Updates(updates)
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

func deleteCurrentUser(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	var req DeleteAccountRequest
	if c.Request.Body != nil && c.Request.ContentLength != 0 {
		if err := c.ShouldBindJSON(&req); err != nil {
			c.JSON(http.StatusBadRequest, gin.H{"error": err.Error()})
			return
		}
	}

	var user User
	if err := db.First(&user, userID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	authProvider := user.AuthProvider
	if authProvider == "" && user.AppleUserID != nil && *user.AppleUserID != "" {
		authProvider = "apple"
	}

	if authProvider == "apple" {
		if req.AppleAuthorizationCode == "" {
			c.JSON(http.StatusBadRequest, gin.H{"error": "apple_authorization_code is required for Apple account deletion"})
			return
		}
		if err := revokeAppleAuthorizationCode(req.AppleAuthorizationCode); err != nil {
			status := http.StatusBadGateway
			if errors.Is(err, errAppleRevocationNotConfigured) {
				status = http.StatusServiceUnavailable
			}
			c.JSON(status, gin.H{"error": "Failed to revoke Apple authorization", "details": err.Error()})
			return
		}
	}

	if err := deleteAvatarFiles(userID); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete account"})
		return
	}

	if err := db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Where("follower_id = ? OR following_id = ?", userID, userID).Delete(&Follow{}).Error; err != nil {
			return err
		}
		if err := tx.Where("user_id = ?", userID).Delete(&Drive{}).Error; err != nil {
			return err
		}
		if err := tx.Delete(&User{}, userID).Error; err != nil {
			return err
		}
		return nil
	}); err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to delete account"})
		return
	}

	c.JSON(http.StatusOK, gin.H{"ok": true})
}
