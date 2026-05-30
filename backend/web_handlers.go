package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"html/template"
	"math"
	"net/http"
	"net/url"
	"strings"

	"github.com/gin-gonic/gin"
)

var (
	leaderboardTmpl *template.Template
	profileTmpl     *template.Template
)

func initWebTemplates() {
	funcMap := template.FuncMap{
		"formatSpeed": func(ms float64) string {
			return fmt.Sprintf("%.1f", ms*2.23694)
		},
		"formatDistance": func(m float64) string {
			return fmt.Sprintf("%.1f", m/1609.34)
		},
		"format060": func(s *float64) string {
			if s == nil {
				return "—"
			}
			return fmt.Sprintf("%.1fs", *s)
		},
		"upper": func(s string) string {
			if len(s) == 0 {
				return ""
			}
			return strings.ToUpper(s[:1]) + s[1:]
		},
	}

	leaderboardTmpl = template.Must(
		template.New("leaderboard.html").Funcs(funcMap).ParseFiles(
			"templates/layout.html",
			"templates/leaderboard.html",
		),
	)
	profileTmpl = template.Must(
		template.New("profile.html").Funcs(funcMap).ParseFiles(
			"templates/layout.html",
			"templates/profile.html",
		),
	)
}

type GarageCar struct {
	ID       string `json:"id"`
	Make     string `json:"make"`
	Model    string `json:"model"`
	Year     int    `json:"year"`
	Trim     string `json:"trim"`
	Nickname string `json:"nickname"`
}

type SocialEntry struct {
	Username string `json:"username"`
	Country  string `json:"country"`
}

func renderProfile(c *gin.Context) {
	username := c.Param("username")

	var user User
	if err := db.Where("username = ? AND is_public = true", username).First(&user).Error; err != nil {
		var buf bytes.Buffer
		if err := profileTmpl.ExecuteTemplate(&buf, "profile.html", gin.H{
			"not_found": true,
		}); err != nil {
			c.String(http.StatusInternalServerError, err.Error())
			return
		}
		c.Data(http.StatusNotFound, "text/html; charset=utf-8", buf.Bytes())
		return
	}

	// Check for authenticated user via Authorization header
	currentUserID, currentUsername, jwtToken := resolveWebAuth(c)
	isOwnProfile := currentUsername == username
	isFollowed := false
	if currentUserID > 0 && !isOwnProfile {
		var count int64
		db.Model(&Follow{}).Where("follower_id = ? AND following_id = ?", currentUserID, user.ID).Count(&count)
		isFollowed = count > 0
	}

	type driveStats struct {
		TopSpeed      float64  `gorm:"column:top_speed"`
		TotalDistance float64  `gorm:"column:total_distance"`
		DriveCount    int      `gorm:"column:drive_count"`
		Best060Time   *float64 `gorm:"column:best_060_time"`
	}
	var stats driveStats
	db.Raw(`
		SELECT COALESCE(MAX(max_speed),0) AS top_speed,
		       COALESCE(SUM(distance),0)  AS total_distance,
		       COUNT(id)                  AS drive_count,
		       MIN(best_060_time)         AS best_060_time
		FROM drives WHERE user_id = ?`, user.ID).Scan(&stats)

	var followerCount, followingCount int64
	db.Model(&Follow{}).Where("following_id = ?", user.ID).Count(&followerCount)
	db.Model(&Follow{}).Where("follower_id = ?", user.ID).Count(&followingCount)

	var followers []SocialEntry
	db.Raw(`
		SELECT u.username, u.country FROM follows f
		JOIN users u ON u.id = f.follower_id
		WHERE f.following_id = ?
		ORDER BY f.created_at DESC LIMIT 100`, user.ID).Scan(&followers)

	var following []SocialEntry
	db.Raw(`
		SELECT u.username, u.country FROM follows f
		JOIN users u ON u.id = f.following_id
		WHERE f.follower_id = ?
		ORDER BY f.created_at DESC LIMIT 100`, user.ID).Scan(&following)

	var garage []GarageCar
	if user.Garage != "" {
		json.Unmarshal([]byte(user.Garage), &garage)
	}
	if garage == nil {
		garage = []GarageCar{}
	}

	// Convert absolute avatar URL to relative for the template so the
	// browser fetches from the same server that serves the page.
	relativeAvatarURL := user.AvatarURL
	if parsed, err := url.Parse(user.AvatarURL); err == nil && parsed.Host != "" {
		relativeAvatarURL = parsed.Path
	}

	var buf bytes.Buffer
	if err := profileTmpl.ExecuteTemplate(&buf, "profile.html", gin.H{
		"user": gin.H{
			"Username":  user.Username,
			"FullName":  user.FullName,
			"Country":   user.Country,
			"AvatarURL": relativeAvatarURL,
			"CreatedAt": user.CreatedAt.Format("Jan 2006"),
			"Garage":    garage,
		},
		"stats": gin.H{
			"TopSpeed":      math.Round(stats.TopSpeed*100) / 100,
			"DriveCount":    stats.DriveCount,
			"TotalDistance": math.Round(stats.TotalDistance*100) / 100,
			"Best060Time":   stats.Best060Time,
		},
		"follower_count":       int(followerCount),
		"following_count":      int(followingCount),
		"followers":            followers,
		"following":            following,
		"is_authenticated":     currentUserID > 0,
		"is_own_profile":       isOwnProfile,
		"is_followed_by_me":    isFollowed,
		"current_user":         currentUsername,
		"jwt_token":            jwtToken,
	}); err != nil {
		c.String(http.StatusInternalServerError, err.Error())
		return
	}
	c.Data(http.StatusOK, "text/html; charset=utf-8", buf.Bytes())
}

// resolveWebAuth attempts to authenticate the current user from the Authorization
// header. Returns the user ID, username, and raw JWT token string (or zero/empty).
func resolveWebAuth(c *gin.Context) (uint, string, string) {
	authHeader := c.GetHeader("Authorization")
	if authHeader == "" {
		return 0, "", ""
	}
	tokenString, err := extractBearerToken(authHeader)
	if err != nil {
		return 0, "", ""
	}
	claims, err := validateJWT(tokenString)
	if err != nil {
		return 0, "", ""
	}
	if err := requireTokenType(claims, tokenTypeAccess); err != nil {
		return 0, "", ""
	}

	var user User
	if err := db.First(&user, claims.UserID).Error; err != nil {
		return 0, "", ""
	}
	return user.ID, user.Username, tokenString
}

func renderLeaderboard(c *gin.Context) {
	var buf bytes.Buffer
	if err := leaderboardTmpl.ExecuteTemplate(&buf, "leaderboard.html", nil); err != nil {
		c.String(http.StatusInternalServerError, err.Error())
		return
	}
	c.Data(http.StatusOK, "text/html; charset=utf-8", buf.Bytes())
}
