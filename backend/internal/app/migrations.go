package app

import (
	"fmt"
	"time"

	"gorm.io/gorm"
)

type schemaMigrationRecord struct {
	Version     string    `gorm:"primaryKey;size:64"`
	Description string    `gorm:"size:255;not null"`
	AppliedAt   time.Time `gorm:"not null"`
}

func (schemaMigrationRecord) TableName() string {
	return "schema_migrations"
}

type schemaMigration struct {
	version     string
	description string
	up          func(tx *gorm.DB) error
}

var schemaMigrations = []schemaMigration{
	{
		version:     "2026053101",
		description: "create core tables",
		up: func(tx *gorm.DB) error {
			for _, model := range []any{&User{}, &Drive{}, &Follow{}} {
				if tx.Migrator().HasTable(model) {
					continue
				}
				if err := tx.Migrator().CreateTable(model); err != nil {
					return err
				}
			}
			return nil
		},
	},
	{
		version:     "2026053102",
		description: "ensure user columns and indexes",
		up: func(tx *gorm.DB) error {
			userColumns := []string{
				"GoogleUserID",
				"Garage",
				"SelectedCarID",
				"IsPublic",
				"AvatarURL",
				"CarStatsData",
				"UnitSystem",
				"ColorScheme",
			}

			for _, col := range userColumns {
				if err := addColumnIfMissing(tx, &User{}, col); err != nil {
					return err
				}
			}

			for _, field := range []string{"AppleUserID", "GoogleUserID", "Username"} {
				if err := addIndexIfMissing(tx, &User{}, field); err != nil {
					return err
				}
			}

			if err := addIndexByNameIfMissing(tx, &Follow{}, "idx_follow_pair"); err != nil {
				return err
			}

			return nil
		},
	},
	{
		version:     "2026053103",
		description: "rename drives best060_time column",
		up: func(tx *gorm.DB) error {
			legacyExists := tx.Migrator().HasColumn(&Drive{}, "best060_time")
			currentExists := tx.Migrator().HasColumn(&Drive{}, "best_060_time")
			if legacyExists && !currentExists {
				if err := tx.Migrator().RenameColumn(&Drive{}, "best060_time", "best_060_time"); err != nil {
					return err
				}
			}
			return nil
		},
	},
	{
		version:     "2026053104",
		description: "ensure drive columns",
		up: func(tx *gorm.DB) error {
			driveColumns := []string{
				"CarID",
				"CarMake",
				"CarModel",
				"CarYear",
				"CarTrim",
				"CarNickname",
				"StoppedTime",
				"LeftTurns",
				"RightTurns",
				"BrakeEvents",
				"LaneChanges",
				"MaxAcceleration",
				"MaxDeceleration",
				"PeakGForce",
				"TopCornerSpeed",
				"Best060Time",
				"UpdatedAt",
			}

			for _, col := range driveColumns {
				if err := addColumnIfMissing(tx, &Drive{}, col); err != nil {
					return err
				}
			}
			return nil
		},
	},
	{
		version:     "2026053105",
		description: "backfill users is_public",
		up: func(tx *gorm.DB) error {
			return tx.Exec("UPDATE users SET is_public = true WHERE NOT is_public").Error
		},
	},
	{
		version:     "2026060101",
		description: "add zero_to_sixty_attempts + user_achievements",
		up: func(tx *gorm.DB) error {
			if err := addColumnIfMissing(tx, &Drive{}, "ZeroToSixtyAttempts"); err != nil {
				return err
			}
			if !tx.Migrator().HasTable(&UserAchievement{}) {
				if err := tx.Migrator().CreateTable(&UserAchievement{}); err != nil {
					return err
				}
			}
			if err := addIndexByNameIfMissing(tx, &UserAchievement{}, "idx_user_achievement"); err != nil {
				return err
			}
			return nil
		},
	},
	{
		version:     "2026060601",
		description: "add notifications table for follower PB events",
		up: func(tx *gorm.DB) error {
			if !tx.Migrator().HasTable(&Notification{}) {
				if err := tx.Migrator().CreateTable(&Notification{}); err != nil {
					return err
				}
			}
			if err := addIndexByNameIfMissing(tx, &Notification{}, "idx_notification_user_created"); err != nil {
				return err
			}
			if err := addIndexByNameIfMissing(tx, &Notification{}, "idx_notification_user_unread"); err != nil {
				return err
			}
			return nil
		},
	},
	{
		version:     "2026060602",
		description: "add unique index for notification dedupe",
		up: func(tx *gorm.DB) error {
			return tx.Exec(`
				CREATE UNIQUE INDEX IF NOT EXISTS idx_notification_dedupe
				ON notifications (user_id, kind, actor_id, drive_id, achievement_id)
			`).Error
		},
	},
	{
		version:     "2026061401",
		description: "add fused_max_speed and gps_max_speed columns to drives",
		up: func(tx *gorm.DB) error {
			driveColumns := []string{"FusedMaxSpeed", "GpsMaxSpeed"}
			for _, col := range driveColumns {
				if err := addColumnIfMissing(tx, &Drive{}, col); err != nil {
					return err
				}
			}
			return nil
		},
	},
}

func runMigrations(db *gorm.DB) error {
	if err := ensureSchemaMigrationsTable(db); err != nil {
		return err
	}

	for _, migration := range schemaMigrations {
		applied, err := migrationApplied(db, migration.version)
		if err != nil {
			return err
		}
		if applied {
			continue
		}

		if err := db.Transaction(func(tx *gorm.DB) error {
			if err := migration.up(tx); err != nil {
				return err
			}
			return tx.Create(&schemaMigrationRecord{
				Version:     migration.version,
				Description: migration.description,
				AppliedAt:   time.Now().UTC(),
			}).Error
		}); err != nil {
			return fmt.Errorf("migration %s failed: %w", migration.version, err)
		}
	}

	return nil
}

func ensureSchemaMigrationsTable(db *gorm.DB) error {
	if db.Migrator().HasTable(&schemaMigrationRecord{}) {
		return nil
	}
	return db.Migrator().CreateTable(&schemaMigrationRecord{})
}

func migrationApplied(db *gorm.DB, version string) (bool, error) {
	var count int64
	err := db.Model(&schemaMigrationRecord{}).Where("version = ?", version).Count(&count).Error
	return count > 0, err
}

func addColumnIfMissing(tx *gorm.DB, model any, field string) error {
	if tx.Migrator().HasColumn(model, field) {
		return nil
	}
	return tx.Migrator().AddColumn(model, field)
}

func addIndexIfMissing(tx *gorm.DB, model any, field string) error {
	if tx.Migrator().HasIndex(model, field) {
		return nil
	}
	return tx.Migrator().CreateIndex(model, field)
}

func addIndexByNameIfMissing(tx *gorm.DB, model any, indexName string) error {
	if tx.Migrator().HasIndex(model, indexName) {
		return nil
	}
	return tx.Migrator().CreateIndex(model, indexName)
}
