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
}

func startServer(r *gin.Engine, buildVersion, buildCommit string) {
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	slog.Info("server starting", "port", port, "version", buildVersion, "commit", buildCommit)
	r.Run(":" + port)
}
