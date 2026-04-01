package main

import (
	"log"
	"os"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

var db *gorm.DB

func main() {
	var err error
	
	// Database connection
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		dsn = "host=localhost user=postgres password=postgres dbname=triprank port=5432 sslmode=disable"
	}
	
	db, err = gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		log.Fatal("Failed to connect to database:", err)
	}
	
	// Auto-migrate models
	db.AutoMigrate(&User{}, &Drive{}, &Follow{})
	
	// Setup router
	r := gin.Default()
	
	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})
	
	// Auth routes (no auth required)
	auth := r.Group("/api/v1/auth")
	{
		auth.POST("/apple", appleSignIn)
		auth.POST("/google", handleGoogleSignIn)
		auth.POST("/refresh", refreshToken)
	}
	
	// API routes (auth required)
	api := r.Group("/api/v1")
	api.Use(authMiddleware())
	{
		api.GET("/me", getCurrentUser)
		api.PUT("/profile", updateProfile)
		api.POST("/drives", createDrive)
		api.GET("/drives", listDrives)
		api.GET("/drives/:id", getDrive)
		api.PUT("/drives/:id", updateDrive)

		// Social
		api.GET("/users/search", searchUsers)
		api.GET("/leaderboard", getLeaderboard)
		api.GET("/users/:username", getPublicProfile)
		api.POST("/users/:username/follow", followUser)
		api.DELETE("/users/:username/follow", unfollowUser)
		api.GET("/users/:username/followers", getFollowers)
		api.GET("/users/:username/following", getFollowing)
	}
	
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	
	log.Printf("Server starting on port %s", port)
	r.Run(":" + port)
}
