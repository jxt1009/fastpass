package main

import (
	"time"
)

type User struct {
	ID           uint      `gorm:"primaryKey" json:"id"`
	AppleUserID  string  `gorm:"uniqueIndex" json:"apple_user_id,omitempty"`
	GoogleUserID *string `gorm:"uniqueIndex" json:"google_user_id,omitempty"`
	Email        string    `json:"email"`
	FullName     string    `json:"full_name"`
	Username     string    `gorm:"uniqueIndex;size:50" json:"username"`
	Country      string    `gorm:"size:100" json:"country"`
	
	// Legacy single car fields (kept for backward compatibility)
	CarMake      string    `gorm:"size:100" json:"car_make"`
	CarModel     string    `gorm:"size:100" json:"car_model"`
	CarYear      *int      `json:"car_year"`
	CarTrim      string    `gorm:"size:100" json:"car_trim"`
	
	// New garage support
	Garage       string `gorm:"type:text" json:"garage"`           // JSON array of cars
	SelectedCarID *string `gorm:"size:100" json:"selected_car_id"`  // ID of selected car

	IsPublic     bool   `gorm:"default:true" json:"is_public"`
	AvatarURL    string `gorm:"size:500" json:"avatar_url"`
	// CarStatsData stores a JSON blob of per-car aggregated stats so they
	// survive reinstall and device switches.
	CarStatsData string `gorm:"type:text" json:"car_stats_data"`
	// User display preferences — synced from the app so they restore on new devices.
	UnitSystem   string `gorm:"size:20;default:'imperial'" json:"unit_system"`
	ColorScheme  string `gorm:"size:20;default:'system'" json:"color_scheme"`

	AuthProvider string    `json:"auth_provider"`
	CreatedAt    time.Time `json:"created_at"`
	UpdatedAt    time.Time `json:"updated_at"`
}

type UpdateProfileRequest struct {
	Username      string `json:"username" binding:"required,min=3,max=20"`
	Country       string `json:"country"`
	
	// Legacy fields (still supported)
	CarMake       string `json:"car_make"`
	CarModel      string `json:"car_model"`
	CarYear       *int   `json:"car_year"`
	CarTrim       string `json:"car_trim"`
	
	// New garage fields
	Garage        string  `json:"garage"`          // JSON array of cars
	SelectedCarID *string `json:"selected_car_id"` // ID of selected car
	IsPublic      *bool   `json:"is_public"`        // nil = don't change
}

type AuthResponse struct {
	Token        string `json:"token"`
	RefreshToken string `json:"refresh_token"`
	User         User   `json:"user"`
}

type AppleSignInRequest struct {
	IdentityToken string `json:"identity_token" binding:"required"`
	AuthCode      string `json:"auth_code"`
	FullName      string `json:"full_name"`
	Email         string `json:"email"`
}

type RefreshTokenRequest struct {
	RefreshToken string `json:"refresh_token" binding:"required"`
}

type GoogleSignInRequest struct {
	Code         string `json:"code" binding:"required"`
	CodeVerifier string `json:"code_verifier" binding:"required"`
	RedirectURI  string `json:"redirect_uri" binding:"required"`
}

type UserInfo struct {
	ID       int    `json:"id"`
	Email    string `json:"email"`
	FullName string `json:"full_name"`
}
