package main

import (
	"time"
)

type Follow struct {
	ID          uint      `gorm:"primaryKey" json:"id"`
	FollowerID  uint      `gorm:"uniqueIndex:idx_follow_pair;not null" json:"follower_id"`
	FollowingID uint      `gorm:"uniqueIndex:idx_follow_pair;not null" json:"following_id"`
	CreatedAt   time.Time `json:"created_at"`
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
	StoppedTime     float64   `json:"stopped_time"`
	LeftTurns       int       `json:"left_turns"`
	RightTurns      int       `json:"right_turns"`
	BrakeEvents     int       `json:"brake_events"`
	LaneChanges     int       `json:"lane_changes"`
	MaxAcceleration float64   `json:"max_acceleration"`
	MaxDeceleration float64   `json:"max_deceleration"`
	PeakGForce      float64   `json:"peak_g_force"`
	TopCornerSpeed  float64   `json:"top_corner_speed"`
	Best060Time     *float64  `gorm:"column:best_060_time" json:"best_060_time"`
	CreatedAt       time.Time `json:"created_at"`
	UpdatedAt       time.Time `json:"updated_at"`
}
