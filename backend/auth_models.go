package main

import (
	"time"
)

type User struct {
	ID            uint      `gorm:"primaryKey" json:"id"`
	AppleUserID   string    `gorm:"uniqueIndex" json:"apple_user_id"`
	Email         string    `json:"email"`
	FullName      string    `json:"full_name"`
	CreatedAt     time.Time `json:"created_at"`
	UpdatedAt     time.Time `json:"updated_at"`
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
