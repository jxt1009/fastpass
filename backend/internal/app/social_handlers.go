package app

import (
	"fmt"
	"net/http"
	"strings"
	"time"

	"github.com/gin-gonic/gin"
)

// ─── Response types ──────────────────────────────────────────────────────────

type LeaderboardEntry struct {
	Rank        int     `json:"rank"`
	UserID      uint    `json:"user_id"`
	Username    string  `json:"username"`
	Country     string  `json:"country"`
	AvatarURL   string  `json:"avatar_url"`
	Value       float64 `json:"value"`
	CarID       *string `json:"car_id"`
	CarKey      string  `json:"car_key"`
	CarMake     string  `json:"car_make"`
	CarModel    string  `json:"car_model"`
	CarYear     *int    `json:"car_year"`
	CarTrim     *string `json:"car_trim"`
	CarNickname *string `json:"car_nickname"`
	CarPhotoURL *string `json:"car_photo_url"`
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
	Garage         string    `json:"garage"`           // JSON array of cars
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

// startOfLast7Days returns the cutoff timestamp for the rolling "last 7 days"
// period: 00:00:00 UTC seven days before the current UTC date.
func startOfLast7Days() time.Time {
	now := time.Now().UTC()
	cutoff := now.AddDate(0, 0, -7)
	return time.Date(cutoff.Year(), cutoff.Month(), cutoff.Day(), 0, 0, 0, 0, time.UTC)
}

// startOfLast24Hours returns the cutoff timestamp for the "last 24 hours"
// period: now minus 24 hours.
func startOfLast24Hours() time.Time {
	return time.Now().UTC().Add(-24 * time.Hour)
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
//	category: top_speed | best_060 | total_distance             (default: top_speed)
//	scope:    global | following                               (default: global)
//	period:   last_24h | last_7_days | all_time                (default: all_time)
//
// One user can appear on the leaderboard up to three times — once per car.
// The synthetic car_key groups drives by car_id when present, otherwise by
// LOWER(TRIM(car_make)) || '|' || LOWER(TRIM(car_model)).
func getLeaderboard(c *gin.Context) {
	currentUserID, _ := getUserID(c)

	category := c.DefaultQuery("category", "top_speed")
	scope := c.DefaultQuery("scope", "global")
	period := c.DefaultQuery("period", "all_time")

	type aggConfig struct {
		expr       string
		order      string // direction only: "DESC" or "ASC", applied to both the row_number ordering and the outer ORDER BY
		extraWhere string
	}

	aggMap := map[string]aggConfig{
		"top_speed":      {expr: "MAX(d.max_speed)", order: "DESC", extraWhere: ""},
		"total_distance": {expr: "SUM(d.distance)", order: "DESC", extraWhere: ""},
		"best_060":       {expr: "MIN(d.best_060_time)", order: "ASC", extraWhere: "AND d.best_060_time IS NOT NULL"},
	}

	agg, ok := aggMap[category]
	if !ok {
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid category; use top_speed, best_060, or total_distance"})
		return
	}

	// Period filter
	var periodWhere string
	args := []interface{}{}
	switch period {
	case "all_time":
		// no time bound
	case "last_7_days":
		periodWhere = "AND d.start_time >= ?"
		args = append(args, startOfLast7Days())
	case "last_24h":
		periodWhere = "AND d.start_time >= ?"
		args = append(args, startOfLast24Hours())
	default:
		c.JSON(http.StatusBadRequest, gin.H{"error": "invalid period; use last_24h, last_7_days, or all_time"})
		return
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
		carWhere += " AND LOWER(COALESCE(d.car_make, '')) = LOWER(?)"
		args = append(args, carMakeFilter)
	}
	if carModelFilter != "" {
		carWhere += " AND LOWER(COALESCE(d.car_model, '')) = LOWER(?)"
		args = append(args, carModelFilter)
	}

	type rawRow struct {
		UserID      uint    `gorm:"column:user_id"`
		Username    string  `gorm:"column:username"`
		Country     string  `gorm:"column:country"`
		AvatarURL   string  `gorm:"column:avatar_url"`
		Value       float64 `gorm:"column:value"`
		CarID       *string `gorm:"column:car_id"`
		CarKey      string  `gorm:"column:car_key"`
		CarMake     string  `gorm:"column:car_make"`
		CarModel    string  `gorm:"column:car_model"`
		CarYear     *int    `gorm:"column:car_year"`
		CarTrim     *string `gorm:"column:car_trim"`
		CarNickname *string `gorm:"column:car_nickname"`
	}

	sqlQuery := fmt.Sprintf(`
		SELECT r.user_id, u.username, u.country, u.avatar_url,
		       r.value, r.car_id, r.car_key,
		       r.car_make, r.car_model, r.car_year, r.car_trim, r.car_nickname
		FROM (
		  SELECT
		    d.user_id,
		    COALESCE(d.car_id, LOWER(TRIM(COALESCE(d.car_make, ''))) || '|' || LOWER(TRIM(COALESCE(d.car_model, '')))) AS car_key,
		    MAX(d.car_id) AS car_id,
		    MAX(COALESCE(d.car_make, '')) AS car_make,
		    MAX(COALESCE(d.car_model, '')) AS car_model,
		    MAX(d.car_year) AS car_year,
		    MAX(d.car_trim) AS car_trim,
		    MAX(d.car_nickname) AS car_nickname,
		    %s AS value,
		    ROW_NUMBER() OVER (PARTITION BY d.user_id ORDER BY %s %s) AS rn
		  FROM drives d
		  WHERE 1=1 %s %s %s %s
		  GROUP BY d.user_id, car_key
		) r
		JOIN users u ON u.id = r.user_id
		WHERE u.is_public = true AND r.rn <= 3 AND r.value IS NOT NULL
		ORDER BY r.value %s
		LIMIT 50`,
		agg.expr, agg.expr, agg.order,
		agg.extraWhere, periodWhere, scopeWhere, carWhere,
		agg.order)

	var rows []rawRow
	db.Raw(sqlQuery, args...).Scan(&rows)

	entries := make([]LeaderboardEntry, len(rows))
	for i, r := range rows {
		entries[i] = LeaderboardEntry{
			Rank:        i + 1,
			UserID:      r.UserID,
			Username:    r.Username,
			Country:     r.Country,
			AvatarURL:   r.AvatarURL,
			Value:       r.Value,
			CarID:       r.CarID,
			CarKey:      r.CarKey,
			CarMake:     r.CarMake,
			CarModel:    r.CarModel,
			CarYear:     r.CarYear,
			CarTrim:     r.CarTrim,
			CarNickname: r.CarNickname,
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
		Garage:         user.Garage,
	})
}

// ─── Car Models by Make ──────────────────────────────────────────────────────

// getCarModels handles GET /api/v1/cars/models?make=XXX
// Returns distinct car models for a given make from the drives table.
func getCarModels(c *gin.Context) {
	make := strings.TrimSpace(c.Query("make"))
	if make == "" {
		c.JSON(http.StatusOK, []string{})
		return
	}

	var models []string
	db.Raw(`
		SELECT DISTINCT car_model FROM drives
		WHERE LOWER(car_make) = LOWER(?)
		  AND car_model != ''
		ORDER BY car_model`, make).Scan(&models)

	if models == nil {
		models = []string{}
	}
	c.JSON(http.StatusOK, models)
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

	entries := make([]FollowUserEntry, 0)
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

	entries := make([]FollowUserEntry, 0)
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
