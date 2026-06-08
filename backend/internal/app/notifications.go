package app

import (
	"fmt"
	"net/http"
	"strconv"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/gorm"
	"gorm.io/gorm/clause"
)

// Notification is a single in-app feed item for a user. The server
// fans out one of these per follower when an actor unlocks a personal
// best (e.g. sub-6 0-60, century club). The model is additive — old
// clients that don't know about it just ignore the new endpoints.
//
// Indexes:
//   - (user_id, created_at) for the per-user feed
//   - (user_id, read_at) for the unread count
//   - actor_id, drive_id, achievement_id for direct lookups
type Notification struct {
	ID            uint       `gorm:"primaryKey" json:"id"`
	UserID        uint       `gorm:"not null;index:idx_notification_user_created,priority:1;index:idx_notification_user_unread,priority:1" json:"-"`
	Kind          string     `gorm:"size:32;not null;default:'pb_set'" json:"kind"`
	ActorID       *uint      `gorm:"index" json:"-"`
	DriveID       *uint      `gorm:"index" json:"-"`
	AchievementID *string    `gorm:"size:64;index" json:"-"`
	Message       string     `gorm:"size:255;not null" json:"message"`
	ReadAt        *time.Time `gorm:"index:idx_notification_user_unread,priority:2" json:"read_at"`
	CreatedAt     time.Time  `gorm:"not null;index:idx_notification_user_created,priority:2" json:"created_at"`
	UpdatedAt     time.Time  `gorm:"not null" json:"updated_at"`
}

// NotificationActor is the minimal public-side info about who triggered
// the event. Kept tiny so the feed list can be rendered without a
// second round trip per row.
type NotificationActor struct {
	ID        uint   `json:"id"`
	Username  string `json:"username"`
	AvatarURL string `json:"avatar_url"`
}

// NotificationResponse is the wire shape returned by GET /me/notifications.
type NotificationResponse struct {
	ID            uint               `json:"id"`
	Kind          string             `json:"kind"`
	Actor         *NotificationActor `json:"actor"`
	DriveID       *uint              `json:"drive_id"`
	AchievementID *string            `json:"achievement_id"`
	Message       string             `json:"message"`
	ReadAt        *time.Time         `json:"read_at"`
	CreatedAt     time.Time          `json:"created_at"`
}

// NotificationsListResponse is the envelope for the list endpoint.
type NotificationsListResponse struct {
	Notifications []NotificationResponse `json:"notifications"`
	NextCursor    *string                `json:"next_cursor"`
	UnreadCount   int                    `json:"unread_count"`
}

// GetMyNotifications returns the caller's feed, newest first.
// Cursor-based pagination via the `cursor` query param (the id of the
// last item from the previous page; the next page returns rows with
// `id < cursor`).
func GetMyNotifications(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	cursor := c.Query("cursor")
	limit := 50
	if l, err := strconv.Atoi(c.DefaultQuery("limit", "50")); err == nil && l > 0 && l <= 100 {
		limit = l
	}

	var rows []Notification
	q := db.Where("user_id = ?", userID).Order("id desc").Limit(limit + 1)
	if cursor != "" {
		if cur, err := strconv.ParseUint(cursor, 10, 64); err == nil {
			q = q.Where("id < ?", cur)
		}
	}
	if err := q.Find(&rows).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}

	var nextCursor *string
	if len(rows) > limit {
		s := strconv.FormatUint(uint64(rows[limit-1].ID), 10)
		nextCursor = &s
		rows = rows[:limit]
	}

	var unread int64
	db.Model(&Notification{}).Where("user_id = ? AND read_at IS NULL", userID).Count(&unread)

	// Resolve actor info per row in a single batched query.
	actorIDs := map[uint]struct{}{}
	for _, r := range rows {
		if r.ActorID != nil {
			actorIDs[*r.ActorID] = struct{}{}
		}
	}
	userByID := map[uint]User{}
	if len(actorIDs) > 0 {
		ids := make([]uint, 0, len(actorIDs))
		for id := range actorIDs {
			ids = append(ids, id)
		}
		var users []User
		if err := db.Where("id IN ?", ids).Find(&users).Error; err != nil {
			c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
			return
		}
		for _, u := range users {
			userByID[u.ID] = u
		}
	}

	out := make([]NotificationResponse, 0, len(rows))
	for _, r := range rows {
		var actor *NotificationActor
		if r.ActorID != nil {
			if u, ok := userByID[*r.ActorID]; ok {
				actor = &NotificationActor{ID: u.ID, Username: u.Username, AvatarURL: u.AvatarURL}
			}
		}
		out = append(out, NotificationResponse{
			ID:            r.ID,
			Kind:          r.Kind,
			Actor:         actor,
			DriveID:       r.DriveID,
			AchievementID: r.AchievementID,
			Message:       r.Message,
			ReadAt:        r.ReadAt,
			CreatedAt:     r.CreatedAt,
		})
	}

	c.JSON(http.StatusOK, NotificationsListResponse{
		Notifications: out,
		NextCursor:    nextCursor,
		UnreadCount:   int(unread),
	})
}

// MarkNotificationRead marks a single notification as read for the
// current user. Idempotent: already-read rows are silently ignored.
func MarkNotificationRead(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	id := c.Param("id")
	now := time.Now().UTC()
	res := db.Model(&Notification{}).
		Where("id = ? AND user_id = ? AND read_at IS NULL", id, userID).
		Update("read_at", now)
	if res.Error != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": res.Error.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// MarkAllNotificationsRead marks every unread notification for the
// current user as read in a single update.
func MarkAllNotificationsRead(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	now := time.Now().UTC()
	if err := db.Model(&Notification{}).
		Where("user_id = ? AND read_at IS NULL", userID).
		Update("read_at", now).Error; err != nil {
		c.JSON(http.StatusInternalServerError, gin.H{"error": err.Error()})
		return
	}
	c.JSON(http.StatusOK, gin.H{"ok": true})
}

// UnreadNotificationCount returns just the unread count for the bell badge.
func UnreadNotificationCount(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(http.StatusUnauthorized, gin.H{"error": "Unauthorized"})
		return
	}
	var unread int64
	db.Model(&Notification{}).Where("user_id = ? AND read_at IS NULL", userID).Count(&unread)
	c.JSON(http.StatusOK, gin.H{"unread_count": int(unread)})
}

// FanOutPBNotificationForUnlocks walks a list of newly-unlocked
// evaluations and fans out one Notification per follower per unlock
// that has a source drive. It is best-effort: a fan-out failure is
// returned to the caller, which should log and continue (the drive
// save is the primary action; notifications are a nice-to-have).
func FanOutPBNotificationForUnlocks(actor *User, unlocks []evaluationResult) error {
	if actor == nil || len(unlocks) == 0 {
		return nil
	}
	for _, u := range unlocks {
		if u.SourceDriveID == nil {
			continue
		}
		entry := catalogByID(u.AchievementID)
		msg := formatPBMessage(actor.Username, entry)
		if _, err := FanOutPBNotification(db, actor.ID, u.SourceDriveID, &u.AchievementID, msg); err != nil {
			return err
		}
	}
	return nil
}

// FanOutPBNotification inserts one Notification row per follower of
// `actorID` (the user who just hit the PB), skipping the actor
// themselves. Returns the number of rows inserted. Dedup is enforced
// atomically by the unique index `idx_notification_dedupe` on
// (user_id, kind, actor_id, drive_id, achievement_id) combined with
// `INSERT ... ON CONFLICT DO NOTHING`, so concurrent unlock
// evaluations or retries cannot create duplicate feed rows.
func FanOutPBNotification(tx *gorm.DB, actorID uint, driveID *uint, achievementID *string, message string) (int, error) {
	if tx == nil {
		tx = db
	}
	var followerIDs []uint
	if err := tx.Model(&Follow{}).
		Where("following_id = ?", actorID).
		Pluck("follower_id", &followerIDs).Error; err != nil {
		return 0, err
	}
	if len(followerIDs) == 0 {
		return 0, nil
	}

	inserted := 0
	for _, uid := range followerIDs {
		if uid == actorID {
			continue
		}
		n := Notification{
			UserID:        uid,
			Kind:          "pb_set",
			ActorID:       &actorID,
			DriveID:       driveID,
			AchievementID: achievementID,
			Message:       message,
		}
		result := tx.Clauses(clause.OnConflict{DoNothing: true}).Create(&n)
		if result.Error != nil {
			return inserted, result.Error
		}
		inserted += int(result.RowsAffected)
	}
	return inserted, nil
}

// formatPBMessage builds a human-readable notification body. It uses
// the achievement catalog title directly so all PB kinds render the
// same way; the actor username is the prefix the iOS bell renders as
// the headline.
func formatPBMessage(username string, entry *AchievementCatalogEntry) string {
	if entry != nil && entry.Title != "" {
		return fmt.Sprintf("%s just unlocked %s", username, entry.Title)
	}
	return fmt.Sprintf("%s just hit a personal best", username)
}
