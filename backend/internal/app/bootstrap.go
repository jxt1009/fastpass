package app

import (
	"log/slog"
	"os"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/postgres"
	"gorm.io/gorm"
)

func configureLogging() {
	logger := slog.New(slog.NewJSONHandler(os.Stdout, &slog.HandlerOptions{Level: slog.LevelInfo}))
	slog.SetDefault(logger)
}

func initDatabase() {
	// Database connection — DATABASE_URL must be set (no insecure fallback).
	// Example (with SSL): host=db user=postgres ****** dbname=fasttrack port=5432 sslmode=require
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		slog.Error("DATABASE_URL environment variable is required")
		os.Exit(1)
	}

	var err error
	db, err = gorm.Open(postgres.Open(dsn), &gorm.Config{})
	if err != nil {
		slog.Error("failed to connect to database", "error", err)
		os.Exit(1)
	}

	if err := runMigrations(db); err != nil {
		slog.Error("failed to run database migrations", "error", err)
		os.Exit(1)
	}
}

func startServer(r *gin.Engine, buildVersion, buildCommit string) {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	slog.Info("server starting", "port", port, "version", buildVersion, "commit", buildCommit)
	r.Run(":" + port)
}
