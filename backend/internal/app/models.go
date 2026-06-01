package app

import (
	"time"
)

type Follow struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	FollowerID  uint      `gorm:"uniqueIndex:idx_follow_pair;not null" json:"follower_id"`
	FollowingID uint      `gorm:"uniqueIndex:idx_follow_pair;not null" json:"following_id"`
	CreatedAt   time.Time `json:"created_at"`
}

// ZeroToSixtyAttempt records one 0-60 mph launch within a single drive.
// A drive may have multiple attempts (e.g. a user launching repeatedly at a light).
type ZeroToSixtyAttempt struct {
	StartIndex     int     `json:"start_index"`
	EndIndex       int     `json:"end_index"`
	StartTimestamp float64 `json:"start_ts"`
	EndTimestamp   float64 `json:"end_ts"`
	ElapsedSeconds float64 `json:"elapsed_s"`
	StartLatitude  float64 `json:"start_lat"`
	StartLongitude float64 `json:"start_lng"`
	EndLatitude    float64 `json:"end_lat"`
	EndLongitude   float64 `json:"end_lng"`
	// Legacy is true for attempts backfilled from a pre-existing best_060_time
	// when no detailed attempt data is available.
	Legacy bool `json:"legacy"`
}

type Drive struct {
	ID              uint      `gorm:"primaryKey" json:"id"`
	UserID          uint      `json:"user_id"`
	User            User      `gorm:"foreignKey:UserID" json:"-"`
	StartTime       time.Time `json:"start_time"`
	EndTime         time.Time `json:"end_time"`
	StartLatitude   float64   `json:"start_latitude"`
	StartLongitude  float64   `json:"start_longitude"`
	EndLatitude     float64   `json:"end_latitude"`
	EndLongitude    float64   `json:"end_longitude"`
	Distance        float64   `json:"distance"`
	Duration        float64   `json:"duration"`
	MaxSpeed        float64   `json:"max_speed"`
	MinSpeed        float64   `json:"min_speed"`
	AvgSpeed        float64   `json:"avg_speed"`
	RouteData       string    `gorm:"type:text" json:"route_data"`

	// Car information
	CarID       *string `json:"car_id"`
	CarMake     *string `json:"car_make"`
	CarModel    *string `json:"car_model"`
	CarYear     *int    `json:"car_year"`
	CarTrim     *string `json:"car_trim"`
	CarNickname *string `json:"car_nickname"`

	// Extended stats
	StoppedTime     float64 `json:"stopped_time"`
	LeftTurns       int     `json:"left_turns"`
	RightTurns      int     `json:"right_turns"`
	BrakeEvents     int     `json:"brake_events"`
	LaneChanges     int     `json:"lane_changes"`
	MaxAcceleration float64 `json:"max_acceleration"`
	MaxDeceleration float64 `json:"max_deceleration"`
	PeakGForce      float64 `json:"peak_g_force"`
	TopCornerSpeed  float64 `json:"top_corner_speed"`
	Best060Time     *float64 `gorm:"column:best_060_time" json:"best_060_time"`

	// ZeroToSixtyAttempts stores every 0-60 launch detected during the drive.
	// Persisted as a JSON blob via GORM's serializer:json.
	ZeroToSixtyAttempts []ZeroToSixtyAttempt `gorm:"serializer:json" json:"zero_to_sixty_attempts"`

	CreatedAt time.Time `json:"created_at"`
	UpdatedAt time.Time `json:"updated_at"`
}

// UserAchievement records one unlocked achievement for a user. The catalog
// itself (titles, icons, requirements) is defined in achievements.go and
// shared with iOS via the API. The (UserID, AchievementID) pair is unique.
type UserAchievement struct {
	ID            uint      `gorm:"primaryKey" json:"id"`
	UserID        uint      `gorm:"uniqueIndex:idx_user_achievement;not null" json:"user_id"`
	AchievementID string    `gorm:"uniqueIndex:idx_user_achievement;size:64;not null" json:"achievement_id"`
	UnlockedAt    time.Time `json:"unlocked_at"`
	SourceDriveID *uint     `json:"source_drive_id"`
	SourceKind    string    `gorm:"size:32" json:"source_kind"`
	SourceValue   float64   `json:"source_value"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
}
