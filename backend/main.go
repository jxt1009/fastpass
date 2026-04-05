package main

import (
	"log/slog"
	"os"

	"github.com/gin-gonic/gin"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

var db *gorm.DB

// Injected at build time via -ldflags
var (
	buildVersion = "dev"
	buildCommit  = "unknown"
)

func main() {
	var err error

	// Structured JSON logging for Loki ingestion
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)

	initJWTSecret()

	// Database connection — DATABASE_URL must be set (no insecure fallback).
	// Example (with SSL): host=db user=postgres password=<secret> dbname=triprank port=5432 sslmode=require
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		slog.Error("DATABASE_URL environment variable is required")
		os.Exit(1)
	}
	
	db, err = gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		slog.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}
	
	// Auto-migrate models
	db.AutoMigrate(&User{}, &Drive{}, &Follow{})
	// Rename best060_time → best_060_time if GORM previously auto-generated the name without underscores.
	db.Exec(`DO $$ BEGIN
		IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_name='drives' AND column_name='best060_time') THEN
			ALTER TABLE drives RENAME COLUMN best060_time TO best_060_time;
		END IF;
	END $$;`)
	// Backfill: any user created before is_public column was added gets false (Go zero value).
	// Since privacy is a new feature, safely default all existing accounts to public.
	db.Exec("UPDATE users SET is_public = true WHERE NOT is_public")
	
	// Setup router
	r := gin.New()
	r.Use(gin.Recovery())
	r.Use(requestIDMiddleware())
	r.Use(requestLoggerMiddleware())
	r.Use(metricsMiddleware())
	// Limit request bodies to 12 MB (avatar upload is the largest expected payload)
	r.MaxMultipartMemory = 12 << 20

	// Prometheus metrics scrape endpoint (internal only — not exposed via Ingress)
	r.GET("/metrics", gin.WrapH(promhttp.Handler()))

	// Health check
	r.GET("/health", func(c *gin.Context) {
		c.JSON(200, gin.H{"status": "ok"})
	})
	
	// Serve uploaded avatars as static files
	r.Static("/uploads", "./uploads")

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
		api.PUT("/profile/avatar", uploadAvatar)
		api.GET("/stats", getCarStats)
		api.PUT("/stats", putCarStats)
		api.PUT("/display-settings", putDisplaySettings)
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

	slog.Info("server starting", "port", port, "version", buildVersion, "commit", buildCommit)
	r.Run(":" + port)
}
