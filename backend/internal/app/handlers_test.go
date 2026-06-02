package app

import (
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"testing"
	"time"

	"github.com/gin-gonic/gin"
	"gorm.io/driver/sqlite"
	"gorm.io/gorm"
)

func stringPtrHelper(value string) *string {
	return &value
}

// setupTestDB creates an in-memory SQLite database for handler tests.
func setupTestDB(t *testing.T) {
	t.Helper()
	var err error
	db, err = gorm.Open(sqlite.Open(":memory:"), &gorm.Config{})
	if err != nil {
		t.Fatalf("failed to open test db: %v", err)
	}
	if err := runMigrations(db); err != nil {
		t.Fatalf("failed to migrate test db: %v", err)
	}
}

// makeAuthRouter returns a minimal Gin router with auth middleware applied.
func makeAuthRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	api := r.Group("/api/v1")
	api.Use(authMiddleware())
	{
		api.POST("/drives", createDrive)
		api.GET("/drives", listDrives)
		api.GET("/drives/:id", getDrive)
		api.PUT("/drives/:id", updateDrive)
		api.DELETE("/me", deleteCurrentUser)
		api.GET("/me/achievements", getMyAchievements)
	}
	return r
}

// makePublicRouter returns a router with the no-auth public endpoints.
func makePublicRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	r.GET("/api/v1/users/:username/achievements", getUserAchievements)
	r.GET("/api/v1/drives/:id/public", getPublicDrive)
	return r
}

// tokenForUser generates a JWT for the given user for use in test requests.
func tokenForUser(t *testing.T, user User) string {
	t.Helper()
	tok, err := generateJWT(user)
	if err != nil {
		t.Fatalf("failed to generate test JWT: %v", err)
	}
	return tok
}

func TestDriveOwnership_CannotReadOtherUsersDrive(t *testing.T) {
	jwtSecret = []byte("handler-test-secret-32-bytes-long!!")
	setupTestDB(t)

	// Create two users
	userA := User{Email: "a@test.com", AppleUserID: stringPtrHelper("apple.a"), Username: "usera"}
	userB := User{Email: "b@test.com", AppleUserID: stringPtrHelper("apple.b"), Username: "userb"}
	db.Create(&userA)
	db.Create(&userB)

	// Create a drive belonging to user B
	drive := Drive{UserID: userB.ID, StartTime: time.Now(), EndTime: time.Now(), MaxSpeed: 30}
	db.Create(&drive)

	router := makeAuthRouter()

	// User A tries to GET user B's drive
	req, _ := http.NewRequest("GET", "/api/v1/drives/1", nil)
	req.Header.Set("Authorization", "Bearer "+tokenForUser(t, userA))
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusForbidden && w.Code != http.StatusNotFound {
		t.Errorf("expected 403 or 404 when user A reads user B's drive, got %d", w.Code)
	}
}

func TestDriveOwnership_CannotUpdateOtherUsersDrive(t *testing.T) {
	jwtSecret = []byte("handler-test-secret-32-bytes-long!!")
	setupTestDB(t)

	userA := User{Email: "a2@test.com", AppleUserID: stringPtrHelper("apple.a2"), Username: "usera2"}
	userB := User{Email: "b2@test.com", AppleUserID: stringPtrHelper("apple.b2"), Username: "userb2"}
	db.Create(&userA)
	db.Create(&userB)

	drive := Drive{UserID: userB.ID, StartTime: time.Now(), EndTime: time.Now()}
	db.Create(&drive)

	router := makeAuthRouter()

	body, _ := json.Marshal(map[string]interface{}{"max_speed": 999})
	req, _ := http.NewRequest("PUT", "/api/v1/drives/1", bytes.NewBuffer(body))
	req.Header.Set("Authorization", "Bearer "+tokenForUser(t, userA))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusForbidden && w.Code != http.StatusNotFound {
		t.Errorf("expected 403 or 404 when user A updates user B's drive, got %d", w.Code)
	}
}

func TestDriveOwnership_OwnerCanReadOwnDrive(t *testing.T) {
	jwtSecret = []byte("handler-test-secret-32-bytes-long!!")
	setupTestDB(t)

	user := User{Email: "owner@test.com", AppleUserID: stringPtrHelper("apple.owner"), Username: "owner"}
	db.Create(&user)

	drive := Drive{UserID: user.ID, StartTime: time.Now(), EndTime: time.Now(), MaxSpeed: 55}
	db.Create(&drive)

	router := makeAuthRouter()

	req, _ := http.NewRequest("GET", "/api/v1/drives/1", nil)
	req.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Errorf("expected 200 for owner reading own drive, got %d (body: %s)", w.Code, w.Body.String())
	}
}

func TestListDrives_OnlyReturnsOwnDrives(t *testing.T) {
	jwtSecret = []byte("handler-test-secret-32-bytes-long!!")
	setupTestDB(t)

	userA := User{Email: "list_a@test.com", AppleUserID: stringPtrHelper("apple.list_a"), Username: "lista"}
	userB := User{Email: "list_b@test.com", AppleUserID: stringPtrHelper("apple.list_b"), Username: "listb"}
	db.Create(&userA)
	db.Create(&userB)

	db.Create(&Drive{UserID: userA.ID, StartTime: time.Now(), EndTime: time.Now()})
	db.Create(&Drive{UserID: userA.ID, StartTime: time.Now(), EndTime: time.Now()})
	db.Create(&Drive{UserID: userB.ID, StartTime: time.Now(), EndTime: time.Now()})

	router := makeAuthRouter()

	req, _ := http.NewRequest("GET", "/api/v1/drives", nil)
	req.Header.Set("Authorization", "Bearer "+tokenForUser(t, userA))
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}

	var drives []Drive
	if err := json.NewDecoder(w.Body).Decode(&drives); err != nil {
		t.Fatalf("failed to decode response: %v", err)
	}
	if len(drives) != 2 {
		t.Errorf("expected 2 drives for user A, got %d", len(drives))
	}
	for _, d := range drives {
		if d.UserID != userA.ID {
			t.Errorf("drive %d has wrong user ID: got %d, want %d", d.ID, d.UserID, userA.ID)
		}
	}
}

func TestCreateDrive_RequiresAuth(t *testing.T) {
	jwtSecret = []byte("handler-test-secret-32-bytes-long!!")
	setupTestDB(t)

	router := makeAuthRouter()

	body, _ := json.Marshal(map[string]interface{}{"max_speed": 30})
	req, _ := http.NewRequest("POST", "/api/v1/drives", bytes.NewBuffer(body))
	req.Header.Set("Content-Type", "application/json")
	// No Authorization header
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Errorf("expected 401 with no auth header, got %d", w.Code)
	}
}

func TestAuthMiddleware_RejectsRefreshTokens(t *testing.T) {
	jwtSecret = []byte("handler-test-secret-32-bytes-long!!")
	setupTestDB(t)

	user := User{Email: "refresh-only@test.com", Username: "refreshonly"}
	db.Create(&user)

	router := makeAuthRouter()

	refreshToken, err := generateRefreshToken(user)
	if err != nil {
		t.Fatalf("failed to generate refresh token: %v", err)
	}

	req, _ := http.NewRequest("GET", "/api/v1/drives", nil)
	req.Header.Set("Authorization", "Bearer "+refreshToken)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401 for refresh token on API route, got %d", w.Code)
	}
}

func TestDeleteCurrentUser_RemovesOwnedData(t *testing.T) {
	jwtSecret = []byte("handler-test-secret-32-bytes-long!!")
	setupTestDB(t)

	wd, err := os.Getwd()
	if err != nil {
		t.Fatalf("failed to get working directory: %v", err)
	}
	tempDir := t.TempDir()
	if err := os.Chdir(tempDir); err != nil {
		t.Fatalf("failed to change working directory: %v", err)
	}
	defer func() {
		if err := os.Chdir(wd); err != nil {
			t.Fatalf("failed to restore working directory: %v", err)
		}
	}()

	user := User{Email: "delete@test.com", Username: "delete-me", AuthProvider: "google"}
	follower := User{Email: "follower@test.com", Username: "follower", AuthProvider: "google"}
	db.Create(&user)
	db.Create(&follower)
	db.Create(&Drive{UserID: user.ID, StartTime: time.Now(), EndTime: time.Now()})
	db.Create(&Follow{FollowerID: follower.ID, FollowingID: user.ID})
	db.Create(&Follow{FollowerID: user.ID, FollowingID: follower.ID})
	avatarPath := filepath.Join("uploads", "avatars", "1.png")
	if err := os.MkdirAll(filepath.Dir(avatarPath), 0o755); err != nil {
		t.Fatalf("failed to create avatar directory: %v", err)
	}
	if err := os.WriteFile(avatarPath, []byte("avatar"), 0o644); err != nil {
		t.Fatalf("failed to create avatar fixture: %v", err)
	}

	router := makeAuthRouter()

	req, _ := http.NewRequest("DELETE", "/api/v1/me", nil)
	req.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200 deleting account, got %d (body: %s)", w.Code, w.Body.String())
	}

	var remainingUsers int64
	var remainingDrives int64
	var remainingFollows int64
	db.Model(&User{}).Where("id = ?", user.ID).Count(&remainingUsers)
	db.Model(&Drive{}).Where("user_id = ?", user.ID).Count(&remainingDrives)
	db.Model(&Follow{}).Where("follower_id = ? OR following_id = ?", user.ID, user.ID).Count(&remainingFollows)

	if remainingUsers != 0 {
		t.Fatalf("expected deleted user to be removed, found %d rows", remainingUsers)
	}
	if remainingDrives != 0 {
		t.Fatalf("expected deleted user's drives to be removed, found %d rows", remainingDrives)
	}
	if remainingFollows != 0 {
		t.Fatalf("expected deleted user's follows to be removed, found %d rows", remainingFollows)
	}
	if _, err := os.Stat(avatarPath); !os.IsNotExist(err) {
		t.Fatalf("expected avatar file to be removed, stat err = %v", err)
	}
}

func TestPublicPages_AreServedByBackend(t *testing.T) {
	gin.SetMode(gin.TestMode)
	router := gin.New()
	registerPublicPageRoutes(router)

	tests := []struct {
		path        string
		wantSnippet string
	}{
		{path: "/app", wantSnippet: "<title>FastTrack — Performance Driving App</title>"},
		{path: "/privacy", wantSnippet: "<title>FastTrack Privacy Policy</title>"},
		{path: "/terms", wantSnippet: "<title>FastTrack Terms of Service</title>"},
	}

	for _, tt := range tests {
		req, _ := http.NewRequest("GET", tt.path, nil)
		rec := httptest.NewRecorder()
		router.ServeHTTP(rec, req)

		if rec.Code != http.StatusOK {
			t.Fatalf("%s: expected 200, got %d", tt.path, rec.Code)
		}
		if got := rec.Header().Get("Content-Type"); got != "text/html; charset=utf-8" {
			t.Fatalf("%s: expected html content type, got %q", tt.path, got)
		}
		if !bytes.Contains(rec.Body.Bytes(), []byte(tt.wantSnippet)) {
			t.Fatalf("%s: response missing %q", tt.path, tt.wantSnippet)
		}
	}
}

// ─── Achievement tests ──────────────────────────────────────────────────────

type createDriveResponse struct {
	Drive                json.RawMessage        `json:"drive"`
	UnlockedAchievements []UnlockedAchievement  `json:"unlocked_achievements"`
}

type achievementsResponse struct {
	Catalog  []AchievementCatalogEntry `json:"catalog"`
	Unlocked []UnlockedAchievement     `json:"unlocked"`
}

func postDrive(t *testing.T, router *gin.Engine, token string, payload map[string]interface{}) createDriveResponse {
	t.Helper()
	body, _ := json.Marshal(payload)
	req, _ := http.NewRequest("POST", "/api/v1/drives", bytes.NewBuffer(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201 on create drive, got %d: %s", w.Code, w.Body.String())
	}
	var resp createDriveResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode create drive response: %v", err)
	}
	return resp
}

func TestUserAchievements_AreUnlockedOnDriveSave(t *testing.T) {
	jwtSecret = []byte("achievement-test-secret-32-bytes-long!!")
	setupTestDB(t)

	user := User{Email: "ach@test.com", Username: "achiever", AuthProvider: "google"}
	db.Create(&user)

	router := makeAuthRouter()
	token := tokenForUser(t, user)

	// First drive — max_speed 50 m/s (~112 mph), triggers sub_6/sub_5/speed_50/speed_100.
	_ = postDrive(t, router, token, map[string]interface{}{
		"start_time":   time.Now().Add(-time.Hour),
		"end_time":     time.Now(),
		"start_lat":    37.0,
		"start_lng":    -122.0,
		"end_lat":      37.01,
		"end_lng":      -122.0,
		"distance":     1000.0,
		"duration":     120.0,
		"max_speed":    50.0,
		"min_speed":    0.0,
		"avg_speed":    8.0,
		"best_060_time": 4.2, // triggers sub_6_club and sub_5_club
	})

	// Fetch /me/achievements
	req, _ := http.NewRequest("GET", "/api/v1/me/achievements", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp achievementsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("failed to decode achievements: %v", err)
	}
	if len(resp.Catalog) == 0 {
		t.Fatalf("expected non-empty catalog")
	}
	gotIDs := map[string]UnlockedAchievement{}
	for _, a := range resp.Unlocked {
		gotIDs[a.AchievementID] = a
	}
	for _, expected := range []string{"first_drive", "sub_6_club", "sub_5_club", "speed_50", "speed_100"} {
		if _, ok := gotIDs[expected]; !ok {
			t.Errorf("expected achievement %q to be unlocked", expected)
		}
	}
	// sub_5_club should have a source drive id
	if a, ok := gotIDs["sub_5_club"]; ok {
		if a.SourceDriveID == nil || *a.SourceDriveID == 0 {
			t.Errorf("expected sub_5_club.source_drive_id to be set")
		}
		if a.SourceKind != SourceKindBestZeroToSixty {
			t.Errorf("expected sub_5_club.source_kind = %q, got %q", SourceKindBestZeroToSixty, a.SourceKind)
		}
	}
}

func TestPublicAchievements_HiddenForPrivateUser(t *testing.T) {
	jwtSecret = []byte("public-ach-test-secret-32-bytes-long!")
	setupTestDB(t)

	user := User{Email: "priv@test.com", Username: "privateuser", AuthProvider: "google"}
	db.Create(&user)
	// IsPublic uses a `default:true` GORM tag, which means GORM will treat
	// the zero-valued `false` as "use the default". Force an explicit update
	// to flip the user to private for this test.
	db.Model(&user).Update("is_public", false)

	// Insert a manually-unlocked achievement
	db.Create(&UserAchievement{
		UserID:        user.ID,
		AchievementID: "first_drive",
		UnlockedAt:    time.Now().UTC(),
		SourceKind:    SourceKindDriveCount,
		SourceValue:   1,
	})

	router := makePublicRouter()
	req, _ := http.NewRequest("GET", "/api/v1/users/privateuser/achievements", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404 for private user, got %d", w.Code)
	}
}

func TestPublicAchievements_VisibleForPublicUser(t *testing.T) {
	jwtSecret = []byte("public-ach-visible-test-32-bytes!!")
	setupTestDB(t)

	user := User{Email: "pub@test.com", Username: "publicuser", AuthProvider: "google", IsPublic: true}
	db.Create(&user)

	db.Create(&UserAchievement{
		UserID:        user.ID,
		AchievementID: "speed_100",
		UnlockedAt:    time.Now().UTC(),
		SourceKind:    SourceKindMaxSpeed,
		SourceValue:   50.0,
	})

	router := makePublicRouter()
	req, _ := http.NewRequest("GET", "/api/v1/users/publicuser/achievements", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var resp achievementsResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(resp.Unlocked) != 1 || resp.Unlocked[0].AchievementID != "speed_100" {
		t.Errorf("expected one speed_100 unlock, got %+v", resp.Unlocked)
	}
	if len(resp.Catalog) == 0 {
		t.Errorf("expected catalog to be returned")
	}
}

func TestPublicDrive_OnlyForPublicUser(t *testing.T) {
	jwtSecret = []byte("public-drive-test-secret-32-bytes!!")
	setupTestDB(t)

	private := User{Email: "pdpriv@test.com", Username: "pdpriv", AuthProvider: "google"}
	public := User{Email: "pdpub@test.com", Username: "pdpub", AuthProvider: "google"}
	db.Create(&private)
	db.Create(&public)
	// Force private user to actually be private (see note in
	// TestPublicAchievements_HiddenForPrivateUser).
	db.Model(&private).Update("is_public", false)

	privateDrive := Drive{UserID: private.ID, StartTime: time.Now(), EndTime: time.Now()}
	publicDrive := Drive{UserID: public.ID, StartTime: time.Now(), EndTime: time.Now()}
	db.Create(&privateDrive)
	db.Create(&publicDrive)

	router := makePublicRouter()

	// Private drive should 404
	req, _ := http.NewRequest("GET", fmt.Sprintf("/api/v1/drives/%d/public", privateDrive.ID), nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Errorf("expected 404 for private drive, got %d", w.Code)
	}

	// Public drive should 200
	req2, _ := http.NewRequest("GET", fmt.Sprintf("/api/v1/drives/%d/public", publicDrive.ID), nil)
	w2 := httptest.NewRecorder()
	router.ServeHTTP(w2, req2)
	if w2.Code != http.StatusOK {
		t.Errorf("expected 200 for public drive, got %d", w2.Code)
	}
}

func TestAchievementEvaluation_RecordsPBZeroSixtySourceDrive(t *testing.T) {
	jwtSecret = []byte("pb-060-test-secret-32-bytes-long!!")
	setupTestDB(t)

	user := User{Email: "pb@test.com", Username: "pbdrive", AuthProvider: "google"}
	db.Create(&user)

	router := makeAuthRouter()
	token := tokenForUser(t, user)

	// First drive: 6.0s
	resp1 := postDrive(t, router, token, map[string]interface{}{
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
		"best_060_time": 6.0,
	})

	var d1 map[string]interface{}
	_ = json.Unmarshal(resp1.Drive, &d1)
	drive1ID := uint(d1["id"].(float64))

	// Fetch /me/achievements and check sub_6_club source drive
	req, _ := http.NewRequest("GET", "/api/v1/me/achievements", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	var ach1 achievementsResponse
	_ = json.Unmarshal(w.Body.Bytes(), &ach1)
	var sub6 *UnlockedAchievement
	for i := range ach1.Unlocked {
		if ach1.Unlocked[i].AchievementID == "sub_6_club" {
			sub6 = &ach1.Unlocked[i]
			break
		}
	}
	if sub6 == nil {
		t.Fatalf("expected sub_6_club to be unlocked on first drive")
	}
	if sub6.SourceDriveID == nil || *sub6.SourceDriveID != drive1ID {
		t.Errorf("expected sub_6_club.source_drive_id == %d, got %v", drive1ID, sub6.SourceDriveID)
	}

	// Second drive: 7.5s (slower) — should NOT change the PB source drive.
	resp2 := postDrive(t, router, token, map[string]interface{}{
		"start_time":    time.Now().Add(-time.Hour),
		"end_time":      time.Now(),
		"start_lat":     37.0,
		"start_lng":     -122.0,
		"end_lat":       37.01,
		"end_lng":       -122.0,
		"distance":      1000.0,
		"duration":      120.0,
		"max_speed":     30.0,
		"min_speed":     0.0,
		"avg_speed":     8.0,
		"best_060_time": 7.5,
	})

	_ = resp2
	req2, _ := http.NewRequest("GET", "/api/v1/me/achievements", nil)
	req2.Header.Set("Authorization", "Bearer "+token)
	w2 := httptest.NewRecorder()
	router.ServeHTTP(w2, req2)
	var ach2 achievementsResponse
	_ = json.Unmarshal(w2.Body.Bytes(), &ach2)
	for _, a := range ach2.Unlocked {
		if a.AchievementID == "sub_6_club" {
			if a.SourceDriveID == nil || *a.SourceDriveID != drive1ID {
				t.Errorf("expected sub_6_club.source_drive_id to remain %d (PB drive), got %v", drive1ID, a.SourceDriveID)
			}
		}
	}
}

func TestAchievementEvaluation_ZeroToSixtyAttemptsRoundTrip(t *testing.T) {
	jwtSecret = []byte("attempts-test-secret-32-bytes-long!!")
	setupTestDB(t)

	user := User{Email: "att@test.com", Username: "attempts", AuthProvider: "google"}
	db.Create(&user)

	router := makeAuthRouter()
	token := tokenForUser(t, user)

	attempts := []ZeroToSixtyAttempt{
		{
			StartIndex: 0, EndIndex: 12,
			StartTimestamp: 1.0, EndTimestamp: 6.0,
			ElapsedSeconds: 5.0,
			StartLatitude: 37.0, StartLongitude: -122.0,
			EndLatitude: 37.005, EndLongitude: -122.0,
		},
		{
			StartIndex: 20, EndIndex: 40,
			StartTimestamp: 60.0, EndTimestamp: 67.5,
			ElapsedSeconds: 7.5,
			StartLatitude: 37.01, StartLongitude: -122.0,
			EndLatitude: 37.02, EndLongitude: -122.0,
		},
	}
	resp := postDrive(t, router, token, map[string]interface{}{
		"start_time":    time.Now().Add(-time.Hour),
		"end_time":      time.Now(),
		"start_lat":     37.0,
		"start_lng":     -122.0,
		"end_lat":       37.02,
		"end_lng":       -122.0,
		"distance":      2000.0,
		"duration":      300.0,
		"max_speed":     30.0,
		"min_speed":     0.0,
		"avg_speed":     8.0,
		"best_060_time": 5.0,
		"zero_to_sixty_attempts": attempts,
	})

	var d map[string]interface{}
	_ = json.Unmarshal(resp.Drive, &d)
	driveID := uint(d["id"].(float64))

	// Read back via GET /drives/:id
	req, _ := http.NewRequest("GET", fmt.Sprintf("/api/v1/drives/%d", driveID), nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}
	var read Drive
	if err := json.Unmarshal(w.Body.Bytes(), &read); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if len(read.ZeroToSixtyAttempts) != 2 {
		t.Fatalf("expected 2 attempts, got %d", len(read.ZeroToSixtyAttempts))
	}
	if read.ZeroToSixtyAttempts[0].ElapsedSeconds != 5.0 {
		t.Errorf("expected first attempt elapsed = 5.0, got %v", read.ZeroToSixtyAttempts[0].ElapsedSeconds)
	}
	if read.ZeroToSixtyAttempts[1].StartIndex != 20 {
		t.Errorf("expected second attempt start_index = 20, got %d", read.ZeroToSixtyAttempts[1].StartIndex)
	}
}

func TestAchievementEvaluation_ConsecutiveDayStreakUnlocks(t *testing.T) {
	jwtSecret = []byte("streak-test-secret-32-bytes-long!!!!")
	setupTestDB(t)

	user := User{Email: "streak@test.com", Username: "streaker", AuthProvider: "google"}
	db.Create(&user)
	token := tokenForUser(t, user)
	router := makeAuthRouter()

	// Build 3 drives on consecutive UTC days: today, yesterday, two days ago.
	now := time.Now().UTC().Truncate(24 * time.Hour).Add(12 * time.Hour)
	for offset := 0; offset < 3; offset++ {
		start := now.AddDate(0, 0, -offset)
		drive := Drive{
			UserID:        user.ID,
			StartTime:     start,
			EndTime:       start.Add(10 * time.Minute),
			StartLatitude: 37.0,
			StartLongitude: -122.0,
			EndLatitude:   37.001,
			EndLongitude:  -122.0,
			Distance:      1500,
			Duration:      600,
			MaxSpeed:      20,
		}
		if err := db.Create(&drive).Error; err != nil {
			t.Fatalf("seed drive: %v", err)
		}
	}

	// Re-evaluate (createDrive path) by saving another drive and asking
	// the server to evaluate as part of the handler.
	seed := map[string]interface{}{
		"start_time":      now.Add(48 * time.Hour).Format(time.RFC3339),
		"end_time":        now.Add(48 * time.Hour).Add(10 * time.Minute).Format(time.RFC3339),
		"start_latitude":  37.0,
		"start_longitude": -122.0,
		"end_latitude":    37.001,
		"end_longitude":   -122.0,
		"distance":        1500,
		"duration":        600,
		"max_speed":       20,
	}
	body, _ := json.Marshal(seed)
	req, _ := http.NewRequest("POST", "/api/v1/drives", bytes.NewReader(body))
	req.Header.Set("Authorization", "Bearer "+token)
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusCreated {
		t.Fatalf("expected 201, got %d: %s", w.Code, w.Body.String())
	}

	var resp struct {
		Unlocked []UnlockedAchievement `json:"unlocked_achievements"`
	}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	ids := map[string]bool{}
	for _, u := range resp.Unlocked {
		ids[u.AchievementID] = true
	}
	if !ids["streak_3"] {
		t.Errorf("expected streak_3 to be unlocked; got %v", ids)
	}
}
