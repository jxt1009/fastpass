package main

import (
	"time"
)

type Drive struct {
	ID             uint      `gorm:"primaryKey" json:"id"`
	UserID         uint      `json:"user_id"`                     // Foreign key to users table
	User           User      `gorm:"foreignKey:UserID" json:"-"` // Relationship
	StartTime      time.Time `json:"start_time"`
	EndTime        time.Time `json:"end_time"`
	StartLatitude  float64   `json:"start_latitude"`
	StartLongitude float64   `json:"start_longitude"`
	EndLatitude    float64   `json:"end_latitude"`
	EndLongitude   float64   `json:"end_longitude"`
	Distance       float64   `json:"distance"`                          // meters
	Duration       float64   `json:"duration"`                          // seconds
	MaxSpeed       float64   `json:"max_speed"`                         // meters per second
	AvgSpeed       float64   `json:"avg_speed"`                         // meters per second
	RouteData      string    `gorm:"type:text" json:"route_data"`       // JSON array of coordinates
	CreatedAt      time.Time `json:"created_at"`
	UpdatedAt      time.Time `json:"updated_at"`
}
