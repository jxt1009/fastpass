package app

import (
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
)

// makeNotificationsRouter returns a router exposing the /api/v1/me/notifications
// endpoints with auth middleware, for use in HTTP-level tests.
func makeNotificationsRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	api := r.Group("/api/v1")
	api.Use(authMiddleware())
	{
		api.GET("/me/notifications", GetMyNotifications)
		api.GET("/me/notifications/unread-count", UnreadNotificationCount)
		api.POST("/me/notifications/:id/read", MarkNotificationRead)
		api.POST("/me/notifications/read-all", MarkAllNotificationsRead)
	}
	return r
}

// seedFollow inserts a Follow{follower -> following} row.
func seedFollow(t *testing.T, followerID, followingID uint) {
	t.Helper()
	if err := db.Create(&Follow{FollowerID: followerID, FollowingID: followingID}).Error; err != nil {
		t.Fatalf("seed follow: %v", err)
	}
}

// seedNotification inserts a single Notification row directly.
func seedNotification(t *testing.T, userID, actorID uint, driveID *uint, achievementID, message string, readAt *time.Time) Notification {
	t.Helper()
	n := Notification{
		UserID:        userID,
		Kind:          "pb_set",
		ActorID:       &actorID,
		DriveID:       driveID,
		AchievementID: &achievementID,
		Message:       message,
		ReadAt:        readAt,
	}
	if err := db.Create(&n).Error; err != nil {
		t.Fatalf("seed notification: %v", err)
	}
	return n
}

// ptr is a tiny helper for taking the address of a string/uint literal.
func notifPtr[T any](v T) *T { return &v }

func TestFanOutPBNotification_SkipsSelf(t *testing.T) {
	jwtSecret = []byte("fanout-skip-self-secret-32-bytes!!")
	setupTestDB(t)

	actor := User{Email: "actor@fanout.com", Username: "actor", AuthProvider: "google"}
	follower := User{Email: "follower@fanout.com", Username: "follower", AuthProvider: "google"}
	db.Create(&actor)
	db.Create(&follower)
	// follower follows actor
	seedFollow(t, follower.ID, actor.ID)
	// actor (impossibly) follows themselves — defensive: should still be skipped
	seedFollow(t, actor.ID, actor.ID)

	driveID := uint(42)
	achID := "sub_6_club"
	inserted, err := FanOutPBNotification(db, actor.ID, &driveID, &achID, "actor just unlocked Sub-6-Second Club")
	if err != nil {
		t.Fatalf("fan-out: %v", err)
	}
	if inserted != 1 {
		t.Errorf("expected 1 inserted (for follower only), got %d", inserted)
	}

	var rows []Notification
	db.Where("user_id = ?", follower.ID).Find(&rows)
	if len(rows) != 1 {
		t.Errorf("expected 1 row for follower, got %d", len(rows))
	}
	if len(rows) > 0 && (rows[0].ActorID == nil || *rows[0].ActorID != actor.ID) {
		t.Errorf("expected actor_id = %d, got %v", actor.ID, rows[0].ActorID)
	}

	var actorRows int64
	db.Model(&Notification{}).Where("user_id = ?", actor.ID).Count(&actorRows)
	if actorRows != 0 {
		t.Errorf("expected 0 rows for actor (self-fanout skipped), got %d", actorRows)
	}
}

func TestFanOutPBNotification_Dedupes(t *testing.T) {
	jwtSecret = []byte("fanout-dedupe-secret-32-bytes!!!!")
	setupTestDB(t)

	actor := User{Email: "actor2@fanout.com", Username: "actor2", AuthProvider: "google"}
	follower := User{Email: "follower2@fanout.com", Username: "follower2", AuthProvider: "google"}
	db.Create(&actor)
	db.Create(&follower)
	seedFollow(t, follower.ID, actor.ID)

	driveID := uint(100)
	achID := "speed_100"
	msg := "actor2 just unlocked Century Club"

	first, err := FanOutPBNotification(db, actor.ID, &driveID, &achID, msg)
	if err != nil {
		t.Fatalf("first fan-out: %v", err)
	}
	if first != 1 {
		t.Errorf("first call: expected 1 inserted, got %d", first)
	}

	second, err := FanOutPBNotification(db, actor.ID, &driveID, &achID, msg)
	if err != nil {
		t.Fatalf("second fan-out: %v", err)
	}
	if second != 0 {
		t.Errorf("second call: expected 0 inserted (deduped), got %d", second)
	}

	var total int64
	db.Model(&Notification{}).Count(&total)
	if total != 1 {
		t.Errorf("expected exactly 1 row in notifications table, got %d", total)
	}
}

func TestFanOutPBNotification_InsertsForMultipleFollowers(t *testing.T) {
	jwtSecret = []byte("fanout-multi-secret-32-bytes!!!!!")
	setupTestDB(t)

	actor := User{Email: "actor3@fanout.com", Username: "actor3", AuthProvider: "google"}
	f1 := User{Email: "f1@fanout.com", Username: "f1", AuthProvider: "google"}
	f2 := User{Email: "f2@fanout.com", Username: "f2", AuthProvider: "google"}
	f3 := User{Email: "f3@fanout.com", Username: "f3", AuthProvider: "google"}
	db.Create(&actor)
	db.Create(&f1)
	db.Create(&f2)
	db.Create(&f3)
	seedFollow(t, f1.ID, actor.ID)
	seedFollow(t, f2.ID, actor.ID)
	seedFollow(t, f3.ID, actor.ID)

	driveID := uint(7)
	achID := "first_drive"
	inserted, err := FanOutPBNotification(db, actor.ID, &driveID, &achID, "actor3 just unlocked First Drive")
	if err != nil {
		t.Fatalf("fan-out: %v", err)
	}
	if inserted != 3 {
		t.Errorf("expected 3 inserted (one per follower), got %d", inserted)
	}

	var count int64
	db.Model(&Notification{}).Where("actor_id = ?", actor.ID).Count(&count)
	if count != 3 {
		t.Errorf("expected 3 rows total for actor, got %d", count)
	}
}

func TestFanOutPBNotification_NoFollowers(t *testing.T) {
	jwtSecret = []byte("fanout-nobody-secret-32-bytes!!!!")
	setupTestDB(t)

	actor := User{Email: "alone@fanout.com", Username: "alone", AuthProvider: "google"}
	db.Create(&actor)

	inserted, err := FanOutPBNotification(db, actor.ID, notifPtr(uint(1)), notifPtr("sub_6_club"), "msg")
	if err != nil {
		t.Fatalf("fan-out: %v", err)
	}
	if inserted != 0 {
		t.Errorf("expected 0 inserted for user with no followers, got %d", inserted)
	}
}

func TestUnreadNotificationCount(t *testing.T) {
	jwtSecret = []byte("unread-count-secret-32-bytes!!!!!!")
	setupTestDB(t)

	user := User{Email: "u@unread.com", Username: "u", AuthProvider: "google"}
	actor := User{Email: "a@unread.com", Username: "a", AuthProvider: "google"}
	db.Create(&user)
	db.Create(&actor)

	seedNotification(t, user.ID, actor.ID, notifPtr(uint(1)), "sub_6_club", "m1", nil)
	seedNotification(t, user.ID, actor.ID, notifPtr(uint(2)), "speed_100", "m2", nil)
	readAt := time.Now().UTC()
	seedNotification(t, user.ID, actor.ID, notifPtr(uint(3)), "first_drive", "m3", &readAt)

	router := makeNotificationsRouter()
	req, _ := http.NewRequest("GET", "/api/v1/me/notifications/unread-count", nil)
	req.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp struct {
		UnreadCount int `json:"unread_count"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.UnreadCount != 2 {
		t.Errorf("expected unread_count = 2, got %d", resp.UnreadCount)
	}
}

func TestMarkNotificationRead(t *testing.T) {
	jwtSecret = []byte("mark-read-secret-32-bytes!!!!!!!!!")
	setupTestDB(t)

	user := User{Email: "u2@mark.com", Username: "u2", AuthProvider: "google"}
	actor := User{Email: "a2@mark.com", Username: "a2", AuthProvider: "google"}
	db.Create(&user)
	db.Create(&actor)

	n1 := seedNotification(t, user.ID, actor.ID, notifPtr(uint(11)), "sub_6_club", "m1", nil)
	n2 := seedNotification(t, user.ID, actor.ID, notifPtr(uint(12)), "speed_100", "m2", nil)

	router := makeNotificationsRouter()
	markURL := fmt.Sprintf("/api/v1/me/notifications/%d/read", n1.ID)
	req, _ := http.NewRequest("POST", markURL, nil)
	req.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	// n1 should now have read_at set, n2 should still be unread.
	var updated Notification
	if err := db.First(&updated, n1.ID).Error; err != nil {
		t.Fatalf("read n1: %v", err)
	}
	if updated.ReadAt == nil {
		t.Errorf("expected n1.read_at to be set")
	}

	var other Notification
	if err := db.First(&other, n2.ID).Error; err != nil {
		t.Fatalf("read n2: %v", err)
	}
	if other.ReadAt != nil {
		t.Errorf("expected n2.read_at to remain nil, got %v", other.ReadAt)
	}

	// Unread count should now be 1
	countReq, _ := http.NewRequest("GET", "/api/v1/me/notifications/unread-count", nil)
	countReq.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	countW := httptest.NewRecorder()
	router.ServeHTTP(countW, countReq)
	var countResp struct {
		UnreadCount int `json:"unread_count"`
	}
	_ = json.Unmarshal(countW.Body.Bytes(), &countResp)
	if countResp.UnreadCount != 1 {
		t.Errorf("expected unread_count = 1 after marking one, got %d", countResp.UnreadCount)
	}

	// Marking again is idempotent (no error, no change).
	markReq2, _ := http.NewRequest("POST", markURL, nil)
	markReq2.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	markW2 := httptest.NewRecorder()
	router.ServeHTTP(markW2, markReq2)
	if markW2.Code != http.StatusOK {
		t.Errorf("second mark: expected 200, got %d", markW2.Code)
	}
}

func TestMarkAllNotificationsRead(t *testing.T) {
	jwtSecret = []byte("mark-all-secret-32-bytes!!!!!!!!!!")
	setupTestDB(t)

	user := User{Email: "u3@markall.com", Username: "u3", AuthProvider: "google"}
	actor := User{Email: "a3@markall.com", Username: "a3", AuthProvider: "google"}
	db.Create(&user)
	db.Create(&actor)

	seedNotification(t, user.ID, actor.ID, notifPtr(uint(21)), "sub_6_club", "m1", nil)
	seedNotification(t, user.ID, actor.ID, notifPtr(uint(22)), "speed_100", "m2", nil)
	seedNotification(t, user.ID, actor.ID, notifPtr(uint(23)), "first_drive", "m3", nil)

	router := makeNotificationsRouter()
	req, _ := http.NewRequest("POST", "/api/v1/me/notifications/read-all", nil)
	req.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	var unread int64
	db.Model(&Notification{}).Where("user_id = ? AND read_at IS NULL", user.ID).Count(&unread)
	if unread != 0 {
		t.Errorf("expected 0 unread after mark-all, got %d", unread)
	}

	var read int64
	db.Model(&Notification{}).Where("user_id = ? AND read_at IS NOT NULL", user.ID).Count(&read)
	if read != 3 {
		t.Errorf("expected 3 read rows, got %d", read)
	}
}

func TestGetMyNotifications_Pagination(t *testing.T) {
	jwtSecret = []byte("notif-paging-secret-32-bytes!!!!!!")
	setupTestDB(t)

	user := User{Email: "pager@notif.com", Username: "pager", AuthProvider: "google"}
	actor := User{Email: "actorp@notif.com", Username: "actorp", AuthProvider: "google"}
	db.Create(&user)
	db.Create(&actor)

	// Insert 4 notifications with deterministic ordering by id (autoincrement).
	for i := 1; i <= 4; i++ {
		seedNotification(t, user.ID, actor.ID, notifPtr(uint(i)), "sub_6_club",
			fmt.Sprintf("msg-%d", i), nil)
	}

	router := makeNotificationsRouter()

	// Page 1
	req1, _ := http.NewRequest("GET", "/api/v1/me/notifications?limit=2", nil)
	req1.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	w1 := httptest.NewRecorder()
	router.ServeHTTP(w1, req1)
	if w1.Code != http.StatusOK {
		t.Fatalf("page 1: expected 200, got %d: %s", w1.Code, w1.Body.String())
	}
	var page1 NotificationsListResponse
	if err := json.Unmarshal(w1.Body.Bytes(), &page1); err != nil {
		t.Fatalf("decode page 1: %v", err)
	}
	if len(page1.Notifications) != 2 {
		t.Errorf("page 1: expected 2 notifications, got %d", len(page1.Notifications))
	}
	if page1.NextCursor == nil || *page1.NextCursor == "" {
		t.Errorf("page 1: expected non-nil next_cursor, got %v", page1.NextCursor)
	}
	if page1.UnreadCount != 4 {
		t.Errorf("page 1: expected unread_count=4, got %d", page1.UnreadCount)
	}

	// Page 2 (using cursor)
	req2, _ := http.NewRequest("GET", "/api/v1/me/notifications?limit=2&cursor="+*page1.NextCursor, nil)
	req2.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	w2 := httptest.NewRecorder()
	router.ServeHTTP(w2, req2)
	if w2.Code != http.StatusOK {
		t.Fatalf("page 2: expected 200, got %d: %s", w2.Code, w2.Body.String())
	}
	var page2 NotificationsListResponse
	if err := json.Unmarshal(w2.Body.Bytes(), &page2); err != nil {
		t.Fatalf("decode page 2: %v", err)
	}
	if len(page2.Notifications) != 2 {
		t.Errorf("page 2: expected 2 notifications, got %d", len(page2.Notifications))
	}
	if page2.NextCursor != nil {
		t.Errorf("page 2: expected nil next_cursor (last page), got %v", *page2.NextCursor)
	}

	// Pages should be disjoint and together cover all 4 rows.
	seen := map[uint]bool{}
	for _, n := range page1.Notifications {
		seen[n.ID] = true
	}
	for _, n := range page2.Notifications {
		if seen[n.ID] {
			t.Errorf("page 2 id %d appeared on both pages", n.ID)
		}
		seen[n.ID] = true
	}
	if len(seen) != 4 {
		t.Errorf("expected pages to cover all 4 rows, got %d unique", len(seen))
	}
}

func TestGetMyNotifications_ActorAndMessageResolved(t *testing.T) {
	jwtSecret = []byte("notif-actor-secret-32-bytes!!!!!!")
	setupTestDB(t)

	user := User{Email: "viewer@notif.com", Username: "viewer", AuthProvider: "google"}
	actor := User{Email: "thedoer@notif.com", Username: "thedoer", AuthProvider: "google", AvatarURL: "/uploads/avatars/thedoer.png"}
	db.Create(&user)
	db.Create(&actor)

	seedNotification(t, user.ID, actor.ID, notifPtr(uint(99)), "sub_6_club", "thedoer just unlocked Sub-6-Second Club", nil)

	router := makeNotificationsRouter()
	req, _ := http.NewRequest("GET", "/api/v1/me/notifications?limit=10", nil)
	req.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp NotificationsListResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp.Notifications) != 1 {
		t.Fatalf("expected 1 notification, got %d", len(resp.Notifications))
	}
	n := resp.Notifications[0]
	if n.Actor == nil {
		t.Fatalf("expected actor to be resolved, got nil")
	}
	if n.Actor.ID != actor.ID {
		t.Errorf("expected actor.id = %d, got %d", actor.ID, n.Actor.ID)
	}
	if n.Actor.Username != "thedoer" {
		t.Errorf("expected actor.username = thedoer, got %q", n.Actor.Username)
	}
	if n.Actor.AvatarURL != "/uploads/avatars/thedoer.png" {
		t.Errorf("expected actor.avatar_url to match, got %q", n.Actor.AvatarURL)
	}
	if !strings.Contains(n.Message, "thedoer") {
		t.Errorf("expected message to contain username, got %q", n.Message)
	}
	if n.AchievementID == nil || *n.AchievementID != "sub_6_club" {
		t.Errorf("expected achievement_id = sub_6_club, got %v", n.AchievementID)
	}
	if n.DriveID == nil || *n.DriveID != 99 {
		t.Errorf("expected drive_id = 99, got %v", n.DriveID)
	}
}

// TestNotifications_AreFannedOutOnDriveCreate exercises the full
// end-to-end path through POST /api/v1/drives: the actor saves a drive
// that triggers a PB unlock, and the follower's feed grows by one.
func TestNotifications_AreFannedOutOnDriveCreate(t *testing.T) {
	jwtSecret = []byte("e2e-fanout-secret-32-bytes!!!!!!!")
	setupTestDB(t)

	actor := User{Email: "a@e2e.com", Username: "speedster", AuthProvider: "google"}
	follower := User{Email: "f@e2e.com", Username: "watcher", AuthProvider: "google"}
	db.Create(&actor)
	db.Create(&follower)
	seedFollow(t, follower.ID, actor.ID)

	router := makeAuthRouter()
	token := tokenForUser(t, actor)

	// First drive — sub-6 0-60 → unlocks sub_6_club + first_drive + ...
	resp := postDrive(t, router, token, map[string]interface{}{
		"start_time":    time.Now().Add(-2 * time.Hour),
		"end_time":      time.Now().Add(-time.Hour),
		"start_lat":     37.0,
		"start_lng":     -122.0,
		"end_lat":       37.01,
		"end_lng":       -122.0,
		"distance":      1000.0,
		"duration":      120.0,
		"max_speed":     30.0,
		"min_speed":     0.0,
		"avg_speed":     8.0,
		"best_060_time": 5.4,
	})
	var d map[string]interface{}
	_ = json.Unmarshal(resp.Drive, &d)
	driveID := uint(d["id"].(float64))

	// Follower should have one notification referencing this drive.
	var rows []Notification
	if err := db.Where("user_id = ?", follower.ID).Find(&rows).Error; err != nil {
		t.Fatalf("query: %v", err)
	}
	if len(rows) == 0 {
		t.Fatalf("expected at least one notification for follower, got 0")
	}
	found := false
	for _, n := range rows {
		if n.DriveID == nil || *n.DriveID != driveID {
			continue
		}
		if n.AchievementID == nil || *n.AchievementID != "sub_6_club" {
			continue
		}
		if n.ActorID == nil || *n.ActorID != actor.ID {
			continue
		}
		if !strings.Contains(n.Message, "speedster") {
			t.Errorf("expected message to contain actor username, got %q", n.Message)
		}
		found = true
		break
	}
	if !found {
		t.Errorf("expected follower notification for sub_6_club on drive %d, got: %+v", driveID, rows)
	}

	// Actor should NOT have a self-notification.
	var actorCount int64
	db.Model(&Notification{}).Where("user_id = ?", actor.ID).Count(&actorCount)
	if actorCount != 0 {
		t.Errorf("expected 0 self-notifications for actor, got %d", actorCount)
	}
}
