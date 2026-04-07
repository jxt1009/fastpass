package main

import (
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// ─── Response types ──────────────────────────────────────────────────────────

type LeaderboardEntry struct {
	Rank      int     `json:"rank"`
	UserID    uint    `json:"user_id"`
	Username  string  `json:"username"`
	Country   string  `json:"country"`
	AvatarURL string  `json:"avatar_url"`
	Value     float64 `json:"value"`
	CarMake   string  `json:"car_make"`
	CarModel  string  `json:"car_model"`
}

type PublicProfileResponse struct {
	Username       string    `json:"username"`
	FullName       string    `json:"full_name"`
	Country        string    `json:"country"`
	AvatarURL      string    `json:"avatar_url"`
	MemberSince    time.Time `json:"member_since"`
	TopSpeed       float64   `json:"top_speed"`       // m/s
	TotalDistance  float64   `json:"total_distance"`  // meters
	DriveCount     int       `json:"drive_count"`
	Best060Time    *float64  `json:"best_060_time"`   // seconds; nil if never reached 60 mph
	FollowerCount  int       `json:"follower_count"`
	FollowingCount int       `json:"following_count"`
	IsFollowedByMe bool      `json:"is_followed_by_me"`
}

type FollowUserEntry struct {
	UserID   uint   `json:"user_id"   gorm:"column:user_id"`
	Username string `json:"username"  gorm:"column:username"`
	Country  string `json:"country"   gorm:"column:country"`
}

type UserSearchResult struct {
	UserID         uint   `json:"user_id"          gorm:"column:user_id"`
	Username       string `json:"username"         gorm:"column:username"`
	FullName       string `json:"full_name"        gorm:"column:full_name"`
	Country        string `json:"country"          gorm:"column:country"`
	AvatarURL      string `json:"avatar_url"       gorm:"column:avatar_url"`
	IsFollowedByMe bool   `json:"is_followed_by_me"`
}

// ─── Helpers ─────────────────────────────────────────────────────────────────

// startOfCurrentWeek returns 00:00:00 UTC on the most recent Monday.
func startOfCurrentWeek() time.Time {
	now := time.Now().UTC()
	weekday := int(now.Weekday())
	if weekday == 0 {
		weekday = 7 // treat Sunday as day 7
	}
	monday := now.AddDate(0, 0, -(weekday - 1))
	return time.Date(monday.Year(), monday.Month(), monday.Day(), 0, 0, 0, 0, time.UTC)
}

// placeholders returns n comma-separated "?" tokens for use in SQL IN clauses.
func placeholders(n int) string {
	if n == 0 {
		return "NULL"
	}
	return strings.Repeat("?,", n)[:n*2-1]
}

// ─── Leaderboard ─────────────────────────────────────────────────────────────

// getLeaderboard handles GET /api/v1/leaderboard
// Query params:
//
//	category: top_speed | total_distance | best_060 | drive_count  (default: top_speed)
//	scope:    global | following                                     (default: global)
//	period:   week | all_time                                        (default: all_time)
func getLeaderboard(c *gin.Context) {
	currentUserID, _ := getUserID(c)

	category := c.DefaultQuery("category", "top_speed")
	scope := c.DefaultQuery("scope", "global")
	period := c.DefaultQuery("period", "all_time")

	type aggConfig struct {
		expr       string
		order      string
		extraWhere string
	}

	aggMap := map[string]aggConfig{
		"top_speed":      {expr: "MAX(d.max_speed)", order: "value DESC"},
		"total_distance": {expr: "SUM(d.distance)", order: "value DESC"},
		"best_060":       {expr: "MIN(d.best_060_time)", order: "value ASC", extraWhere: "AND d.best_060_time IS NOT NULL"},
		"drive_count":    {expr: "COUNT(d.id)", order: "value DESC"},
	}

	agg, ok := aggMap[category]
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid category; use top_speed, total_distance, best_060, or drive_count"})
		return
	}

	args := []interface{}{}

	// Period filter
	periodWhere := ""
	if period == "week" {
		periodWhere = "AND d.start_time >= ?"
		args = append(args, startOfCurrentWeek())
	}

	// Scope filter — restrict to people the current user follows (+ themselves)
	scopeWhere := ""
	if scope == "following" && currentUserID > 0 {
		var followingIDs []uint
		db.Model(&Follow{}).Where("follower_id = ?", currentUserID).Pluck("following_id", &followingIDs)
		followingIDs = append(followingIDs, currentUserID)

		scopeWhere = fmt.Sprintf("AND d.user_id IN (%s)", placeholders(len(followingIDs)))
		for _, id := range followingIDs {
			args = append(args, id)
		}
	}

	// Optional car filter
	carMakeFilter := strings.TrimSpace(c.Query("car_make"))
	carModelFilter := strings.TrimSpace(c.Query("car_model"))
	carWhere := ""
	if carMakeFilter != "" {
		carWhere += " AND LOWER(d.car_make) = LOWER(?)"
		args = append(args, carMakeFilter)
	}
	if carModelFilter != "" {
		carWhere += " AND LOWER(d.car_model) = LOWER(?)"
		args = append(args, carModelFilter)
	}

	type rawRow struct {
		UserID    uint    `gorm:"column:user_id"`
		Username  string  `gorm:"column:username"`
		Country   string  `gorm:"column:country"`
		AvatarURL string  `gorm:"column:avatar_url"`
		Value     float64 `gorm:"column:value"`
		CarMake   string  `gorm:"column:car_make"`
		CarModel  string  `gorm:"column:car_model"`
	}

	// For each user, also surface which car achieved their best value.
	// We use a subquery to find the drive that produced the aggregate value.
	sqlQuery := fmt.Sprintf(`
		SELECT d.user_id, u.username, u.country, u.avatar_url,
		       %s AS value,
		       COALESCE((
		           SELECT d2.car_make FROM drives d2
		           WHERE d2.user_id = d.user_id %s %s %s
		           ORDER BY %s LIMIT 1
		       ), '') AS car_make,
		       COALESCE((
		           SELECT d2.car_model FROM drives d2
		           WHERE d2.user_id = d.user_id %s %s %s
		           ORDER BY %s LIMIT 1
		       ), '') AS car_model
		FROM drives d
		JOIN users u ON d.user_id = u.id
		WHERE u.is_public = true %s %s %s %s
		GROUP BY d.user_id, u.username, u.country, u.avatar_url
		ORDER BY %s
		LIMIT 50`,
		agg.expr,
		// subquery for car_make
		agg.extraWhere, periodWhere, carWhere, agg.order,
		// subquery for car_model
		agg.extraWhere, periodWhere, carWhere, agg.order,
		// main WHERE
		agg.extraWhere, periodWhere, scopeWhere, carWhere,
		agg.order)

	// args are reused for main query; subqueries need same period/car args
	// Build full args: [subquery1 args] + [subquery2 args] + [main args]
	subArgs := []interface{}{}
	if period == "week" {
		subArgs = append(subArgs, startOfCurrentWeek())
	}
	if carMakeFilter != "" {
		subArgs = append(subArgs, carMakeFilter)
	}
	if carModelFilter != "" {
		subArgs = append(subArgs, carModelFilter)
	}
	fullArgs := append(subArgs, subArgs...)
	fullArgs = append(fullArgs, args...)

	var rows []rawRow
	db.Raw(sqlQuery, fullArgs...).Scan(&rows)

	entries := make([]LeaderboardEntry, len(rows))
	for i, r := range rows {
		entries[i] = LeaderboardEntry{
			Rank:      i + 1,
			UserID:    r.UserID,
			Username:  r.Username,
			Country:   r.Country,
			AvatarURL: r.AvatarURL,
			Value:     r.Value,
			CarMake:   r.CarMake,
			CarModel:  r.CarModel,
		}
	}

	c.JSON(http.StatusOK, entries)
}

// ─── Public Profile ───────────────────────────────────────────────────────────

// getPublicProfile handles GET /api/v1/users/:username
func getPublicProfile(c *gin.Context) {
	currentUserID, _ := getUserID(c)
	username := c.Param("username")

	var user User
	if err := db.Where("username = ? AND is_public = true", username).First(&user).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	// Aggregate drive stats
	type statsRow struct {
		TopSpeed      float64  `gorm:"column:top_speed"`
		TotalDistance float64  `gorm:"column:total_distance"`
		DriveCount    int      `gorm:"column:drive_count"`
		Best060Time   *float64 `gorm:"column:best_060_time"`
	}
	var stats statsRow
	db.Raw(`
		SELECT
			COALESCE(MAX(max_speed), 0)    AS top_speed,
			COALESCE(SUM(distance), 0)     AS total_distance,
			COUNT(id)                      AS drive_count,
			MIN(best_060_time)             AS best_060_time
		FROM drives
		WHERE user_id = ?`, user.ID).Scan(&stats)

	// Follower / following counts
	var followerCount, followingCount int64
	db.Model(&Follow{}).Where("following_id = ?", user.ID).Count(&followerCount)
	db.Model(&Follow{}).Where("follower_id = ?", user.ID).Count(&followingCount)

	// Is the requesting user already following this profile?
	isFollowed := false
	if currentUserID > 0 {
		var count int64
		db.Model(&Follow{}).Where("follower_id = ? AND following_id = ?", currentUserID, user.ID).Count(&count)
		isFollowed = count > 0
	}

	c.JSON(http.StatusOK, PublicProfileResponse{
		Username:       user.Username,
		FullName:       user.FullName,
		Country:        user.Country,
		AvatarURL:      user.AvatarURL,
		MemberSince:    user.CreatedAt,
		TopSpeed:       stats.TopSpeed,
		TotalDistance:  stats.TotalDistance,
		DriveCount:     stats.DriveCount,
		Best060Time:    stats.Best060Time,
		FollowerCount:  int(followerCount),
		FollowingCount: int(followingCount),
		IsFollowedByMe: isFollowed,
	})
}

// ─── Follow / Unfollow ────────────────────────────────────────────────────────

// followUser handles POST /api/v1/users/:username/follow
func followUser(c *gin.Context) {
	currentUserID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	username := c.Param("username")

	var target User
	if err := db.Where("username = ? AND is_public = true", username).First(&target).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	if target.ID == currentUserID {
		c.JSON(http.StatusBadRequest, gin.H{"error": "Cannot follow yourself"})
		return
	}

	follow := Follow{FollowerID: currentUserID, FollowingID: target.ID}
	db.Where(Follow{FollowerID: currentUserID, FollowingID: target.ID}).FirstOrCreate(&follow)

	c.JSON(http.StatusOK, gin.H{"message": "following"})
}

// unfollowUser handles DELETE /api/v1/users/:username/follow
func unfollowUser(c *gin.Context) {
	currentUserID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}

	username := c.Param("username")

	var target User
	if err := db.Where("username = ?", username).First(&target).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return
	}

	db.Where("follower_id = ? AND following_id = ?", currentUserID, target.ID).Delete(&Follow{})

	c.JSON(http.StatusOK, gin.H{"message": "unfollowed"})
}

// ─── User search ─────────────────────────────────────────────────────────────

// searchUsers handles GET /api/v1/users/search?q=...
// Returns up to 20 public users whose username or full_name contains the query.
func searchUsers(c *gin.Context) {
	callerID, _ := c.Get("userID")

	q := strings.TrimSpace(c.Query("q"))
	if len(q) < 2 {
		c.JSON(http.StatusOK, []UserSearchResult{})
		return
	}

	pattern := "%" + strings.ToLower(q) + "%"

	type rawRow struct {
		UserID    uint   `gorm:"column:user_id"`
		Username  string `gorm:"column:username"`
		FullName  string `gorm:"column:full_name"`
		Country   string `gorm:"column:country"`
		AvatarURL string `gorm:"column:avatar_url"`
	}

	var rows []rawRow
	db.Raw(`
		SELECT id AS user_id, username, full_name, country, avatar_url
		FROM users
		WHERE is_public = true
		  AND (LOWER(username) LIKE ? OR LOWER(full_name) LIKE ?)
		ORDER BY username
		LIMIT 20`, pattern, pattern).Scan(&rows)

	// Resolve follow status for the caller
	var followedIDs []uint
	if callerID != nil {
		db.Raw(`SELECT following_id FROM follows WHERE follower_id = ?`, callerID).
			Pluck("following_id", &followedIDs)
	}
	followSet := make(map[uint]bool, len(followedIDs))
	for _, id := range followedIDs {
		followSet[id] = true
	}

	results := make([]UserSearchResult, len(rows))
	for i, r := range rows {
		results[i] = UserSearchResult{
			UserID:         r.UserID,
			Username:       r.Username,
			FullName:       r.FullName,
			Country:        r.Country,
			AvatarURL:      r.AvatarURL,
			IsFollowedByMe: followSet[r.UserID],
		}
	}

	c.JSON(http.StatusOK, results)
}

// ─── Follower / Following lists ───────────────────────────────────────────────

// getFollowers handles GET /api/v1/users/:username/followers
func getFollowers(c *gin.Context) {
	user, ok := lookupPublicUser(c)
	if !ok {
		return
	}

	var entries []FollowUserEntry
	db.Raw(`
		SELECT u.id AS user_id, u.username, u.country
		FROM follows f
		JOIN users u ON f.follower_id = u.id
		WHERE f.following_id = ?
		ORDER BY f.created_at DESC
		LIMIT 100`, user.ID).Scan(&entries)

	c.JSON(http.StatusOK, entries)
}

// getFollowing handles GET /api/v1/users/:username/following
func getFollowing(c *gin.Context) {
	user, ok := lookupPublicUser(c)
	if !ok {
		return
	}

	var entries []FollowUserEntry
	db.Raw(`
		SELECT u.id AS user_id, u.username, u.country
		FROM follows f
		JOIN users u ON f.following_id = u.id
		WHERE f.follower_id = ?
		ORDER BY f.created_at DESC
		LIMIT 100`, user.ID).Scan(&entries)

	c.JSON(http.StatusOK, entries)
}

// lookupPublicUser is a shared helper that resolves :username and writes a 404 on failure.
func lookupPublicUser(c *gin.Context) (User, bool) {
	var user User
	if err := db.Where("username = ? AND is_public = true", c.Param("username")).First(&user).Error; err != nil {
		c.JSON(http.StatusNotFound, gin.H{"error": "User not found"})
		return User{}, false
	}
	return user, true
}
