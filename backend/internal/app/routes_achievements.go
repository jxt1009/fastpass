package app

import (
	"net/http"

	"github.com/gin-gonic/gin"
)

// UserAchievementsResponse is the payload returned by both the auth and
// public achievement endpoints. The catalog is always included so clients
// (iOS, web) can render locked vs. unlocked state.
type UserAchievementsResponse struct {
	Catalog  []AchievementCatalogEntry `json:"catalog"`
	Unlocked []UnlockedAchievement     `json:"unlocked"`
}

// getMyAchievements handles GET /api/v1/me/achievements
func getMyAchievements(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	unlocked, err := loadUnlockedAchievements(userID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to load achievements"})
		return
	}
	c.JSON(http.StatusOK, UserAchievementsResponse{
		Catalog:  defaultCatalog,
		Unlocked: unlocked,
	})
}

// getUserAchievements handles GET /api/v1/users/:username/achievements.
// Returns 404 for private users. No auth required.
func getUserAchievements(c *gin.Context) {
	username := c.Param("username")
	var user User
	if err := db.Where("username = ? AND is_public = true", username).First(&user).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}
	unlocked, err := loadUnlockedAchievements(user.ID)
	if err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": "Failed to load achievements"})
		return
	}
	c.JSON(http.StatusOK, UserAchievementsResponse{
		Catalog:  defaultCatalog,
		Unlocked: unlocked,
	})
}

// getPublicDrive handles GET /api/v1/drives/:id/public.
// Returns 404 if the drive's owner is private, otherwise the full drive
// (including route_data so maps/attempts render). No auth required.
func getPublicDrive(c *gin.Context) {
	id := c.Param("id")
	var drive Drive
	if err := db.Where("id = ?", id).First(&drive).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Drive not found"})
		return
	}
	var owner User
	if err := db.First(&owner, drive.UserID).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "Drive not found"})
		return
	}
	if !owner.IsPublic {
		c.JSON(http.StatusNotFound, gin.H{"error": "Drive not found"})
		return
	}
	c.JSON(http.StatusOK, drive)
}

func registerAchievementRoutes(r *gin.Engine) {
	// Public endpoints (no auth) — visibility gates live inside the handlers.
	r.GET("/api/v1/users/:username/achievements", getUserAchievements)
	r.GET("/api/v1/drives/:id/public", getPublicDrive)

	// Authenticated
	api := r.Group("/api/v1")
	api.Use(authMiddleware())
	{
		api.GET("/me/achievements", getMyAchievements)
	}
}