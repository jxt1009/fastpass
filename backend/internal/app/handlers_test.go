package app

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"image"
	"image/color"
	"image/png"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strconv"
	"strings"
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
		api.DELETE("/drives/:id", deleteDrive)
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

// makeGaragePhotoRouter returns a router that includes the new car-photo
// routes, for use in TestUploadCarPhoto_* and TestDeleteCarPhoto_*.
func makeGaragePhotoRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	api := r.Group("/api/v1")
	api.Use(authMiddleware())
	{
		api.GET("/me", getCurrentUser)
		api.PUT("/garage/cars/:carId/photo", uploadCarPhoto)
		api.DELETE("/garage/cars/:carId/photo", deleteCarPhoto)
	}
	return r
}

// tinyPNG returns the bytes of a 1x1 fully-opaque red PNG. Used to drive
// image.DecodeConfig on the upload path.
func tinyPNG(t *testing.T) []byte {
	t.Helper()
	img := image.NewRGBA(image.Rect(0, 0, 1, 1))
	img.Set(0, 0, color.RGBA{R: 255, A: 255})
	var buf bytes.Buffer
	if err := png.Encode(&buf, img); err != nil {
		t.Fatalf("encode tiny PNG: %v", err)
	}
	return buf.Bytes()
}

// seedUserWithCar creates a user whose garage JSON contains a single car
// with the given carID, and returns the user.
func seedUserWithCar(t *testing.T, email, username, carID string) User {
	t.Helper()
	garageBlob := fmt.Sprintf(`[{"id":%q,"make":"Honda","model":"Civic","year":2018,"trim":"","nickname":"Daily"}]`, carID)
	user := User{
		Email:    email,
		Username: username,
		AuthProvider: "google",
		Garage:   garageBlob,
	}
	if err := db.Create(&user).Error; err != nil {
		t.Fatalf("seed user: %v", err)
	}
	return user
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

func TestUpdateDrive_UnlockedAchievementsIsArrayNotNull(t *testing.T) {
	jwtSecret = []byte("update-envelope-secret-32-bytes!!!")
	setupTestDB(t)

	user := User{Email: "upd_envelope@test.com", Username: "updenvelope", AuthProvider: "google"}
	db.Create(&user)

	drive := Drive{UserID: user.ID, StartTime: time.Now(), EndTime: time.Now(), MaxSpeed: 25}
	db.Create(&drive)

	// Pre-insert UserAchievement rows so the update doesn't trigger
	// any new unlocks. The point of this test is wire-shape — the
	// `unlocked_achievements` field must serialize as `[]`, not `null`,
	// even when there are no new unlocks to report. (The field's
	// semantic is "the current unlocked set", used by iOS to sync;
	// an empty set is the valid "nothing new" signal.)
	preInserted := []string{"first_drive", "speed_50"}
	for _, aid := range preInserted {
		db.Create(&UserAchievement{
			UserID:        user.ID,
			AchievementID: aid,
			UnlockedAt:    time.Now().Add(-time.Hour),
		})
	}

	router := makeAuthRouter()
	body, _ := json.Marshal(map[string]interface{}{"max_speed": 30})
	req, _ := http.NewRequest("PUT", "/api/v1/drives/"+strconv.Itoa(int(drive.ID)), bytes.NewBuffer(body))
	req.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d: %s", w.Code, w.Body.String())
	}

	// The envelope must contain "unlocked_achievements" as a JSON array,
	// never null — clients expect a single decode path that mirrors
	// createDrive.
	bodyStr := w.Body.String()
	if strings.Contains(bodyStr, `"unlocked_achievements":null`) {
		t.Errorf("unlocked_achievements must never serialize as null, got body: %s", bodyStr)
	}

	// And confirm the typed decode works the same way createDrive does.
	var resp createDriveResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	if resp.UnlockedAchievements == nil {
		t.Fatalf("expected non-nil slice for unlocked_achievements, got nil")
	}

	// Both pre-inserted achievements should be reflected back.
	gotIDs := map[string]bool{}
	for _, a := range resp.UnlockedAchievements {
		gotIDs[a.AchievementID] = true
	}
	for _, want := range preInserted {
		if !gotIDs[want] {
			t.Errorf("expected %q in unlocked_achievements, got %v", want, gotIDs)
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
		{path: "/privacy", wantSnippet: "<title>FastTrack Privacy Policy</title>"},
		{path: "/terms", wantSnippet: "<title>FastTrack Terms of Service</title>"},
	}

	// /app was retired — verify it redirects to /
	req, _ := http.NewRequest("GET", "/app", nil)
	rec := httptest.NewRecorder()
	router.ServeHTTP(rec, req)
	if rec.Code != http.StatusMovedPermanently {
		t.Fatalf("/app: expected 301, got %d", rec.Code)
	}
	if loc := rec.Header().Get("Location"); loc != "/" {
		t.Fatalf("/app: expected Location: /, got %q", loc)
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

// ─── Leaderboard tests ─────────────────────────────────────────────────────

// makeLeaderboardRouter returns a router exposing /api/v1/leaderboard with
// the same optional auth middleware the production router uses.
func makeLeaderboardRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	api := r.Group("/api/v1")
	api.Use(optionalAuthMiddleware())
	api.GET("/leaderboard", getLeaderboard)
	return r
}

// lbStringPtr is a test-local helper for taking the address of a string literal.
func lbStringPtr(s string) *string { return &s }

// lbIntPtr is a test-local helper for taking the address of an int literal.
func lbIntPtr(i int) *int { return &i }

// fetchLeaderboard issues a GET against the leaderboard endpoint and decodes
// the JSON response into a slice of LeaderboardEntry.
func fetchLeaderboard(t *testing.T, router *gin.Engine, query string) []LeaderboardEntry {
	t.Helper()
	req, _ := http.NewRequest("GET", "/api/v1/leaderboard?"+query, nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body: %s)", w.Code, w.Body.String())
	}
	var entries []LeaderboardEntry
	if err := json.NewDecoder(w.Body).Decode(&entries); err != nil {
		t.Fatalf("failed to decode leaderboard response: %v", err)
	}
	return entries
}

// fetchLeaderboardStatus issues a GET and returns the status code (used for
// validation-error tests).
func fetchLeaderboardStatus(t *testing.T, router *gin.Engine, query string) int {
	t.Helper()
	req, _ := http.NewRequest("GET", "/api/v1/leaderboard?"+query, nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	return w.Code
}

// seedLeaderboardDrive is a convenience for inserting a drive with the
// fields the leaderboard cares about.
func seedLeaderboardDrive(userID uint, start time.Time, maxSpeed, distance float64, best060 *float64,
	carID, carMake, carModel *string, carYear *int, carNickname *string) Drive {
	d := Drive{
		UserID:      userID,
		StartTime:   start,
		EndTime:     start.Add(time.Minute),
		MaxSpeed:    maxSpeed,
		Distance:    distance,
		Best060Time: best060,
		CarID:       carID,
		CarMake:     carMake,
		CarModel:    carModel,
		CarYear:     carYear,
		CarNickname: carNickname,
	}
	if err := db.Create(&d).Error; err != nil {
		panic(err)
	}
	return d
}

func TestLeaderboard_OneUserMultipleCarsAppearAsSeparateRows(t *testing.T) {
	jwtSecret = []byte("lb-multicar-test-secret-32-bytes!!!")
	setupTestDB(t)

	user := User{Email: "multi@test.com", Username: "multicar", AuthProvider: "google"}
	db.Create(&user)

	now := time.Now().UTC()
	seedLeaderboardDrive(user.ID, now.Add(-48*time.Hour), 50, 1000, nil,
		lbStringPtr("c1"), lbStringPtr("BMW"), lbStringPtr("M3"), lbIntPtr(2020), lbStringPtr("Beemer"))
	seedLeaderboardDrive(user.ID, now.Add(-48*time.Hour), 70, 2000, nil,
		lbStringPtr("c2"), lbStringPtr("Audi"), lbStringPtr("A4"), lbIntPtr(2022), lbStringPtr("Audy"))

	router := makeLeaderboardRouter()
	entries := fetchLeaderboard(t, router, "category=top_speed&period=all_time&scope=global")

	if len(entries) != 2 {
		t.Fatalf("expected 2 rows for one user with 2 cars, got %d: %+v", len(entries), entries)
	}
	if entries[0].CarID == nil || *entries[0].CarID != "c2" {
		t.Errorf("expected rank-1 car_id=c2, got %v", entries[0].CarID)
	}
	if entries[1].CarID == nil || *entries[1].CarID != "c1" {
		t.Errorf("expected rank-2 car_id=c1, got %v", entries[1].CarID)
	}
	if entries[0].CarKey != "c2" {
		t.Errorf("expected car_key=c2 for rank-1, got %q", entries[0].CarKey)
	}
}

func TestLeaderboard_LegacyDrivesWithoutCarID_GroupedByMakeModel(t *testing.T) {
	jwtSecret = []byte("lb-legacy-test-secret-32-bytes!!!!")
	setupTestDB(t)

	user := User{Email: "legacy@test.com", Username: "legacy", AuthProvider: "google"}
	db.Create(&user)

	now := time.Now().UTC()
	// Three drives for the same car (no car_id, just make/model)
	seedLeaderboardDrive(user.ID, now.Add(-72*time.Hour), 50, 1000, nil,
		nil, lbStringPtr("BMW"), lbStringPtr("M3"), lbIntPtr(2020), nil)
	seedLeaderboardDrive(user.ID, now.Add(-48*time.Hour), 60, 1500, nil,
		nil, lbStringPtr("BMW"), lbStringPtr("M3"), nil, nil)
	seedLeaderboardDrive(user.ID, now.Add(-24*time.Hour), 55, 1200, nil,
		nil, lbStringPtr("BMW"), lbStringPtr("M3"), lbIntPtr(2020), lbStringPtr("Beemer"))

	router := makeLeaderboardRouter()
	entries := fetchLeaderboard(t, router, "category=top_speed&period=all_time&scope=global")

	if len(entries) != 1 {
		t.Fatalf("expected 1 row for legacy drives grouped by make/model, got %d: %+v", len(entries), entries)
	}
	if entries[0].CarID != nil {
		t.Errorf("expected car_id=nil, got %v", *entries[0].CarID)
	}
	if entries[0].CarKey != "bmw|m3" {
		t.Errorf("expected car_key=bmw|m3, got %q", entries[0].CarKey)
	}
	if entries[0].CarMake != "BMW" || entries[0].CarModel != "M3" {
		t.Errorf("expected make=BMW model=M3, got %q %q", entries[0].CarMake, entries[0].CarModel)
	}
}

func TestLeaderboard_PeriodLast24Hours(t *testing.T) {
	jwtSecret = []byte("lb-24h-test-secret-32-bytes!!!!!!")
	setupTestDB(t)

	user := User{Email: "p24h@test.com", Username: "p24h", AuthProvider: "google"}
	db.Create(&user)

	now := time.Now().UTC()
	// 23h ago: included
	seedLeaderboardDrive(user.ID, now.Add(-23*time.Hour), 50, 1000, nil,
		lbStringPtr("c1"), lbStringPtr("BMW"), lbStringPtr("M3"), nil, nil)
	// 25h ago: excluded
	seedLeaderboardDrive(user.ID, now.Add(-25*time.Hour), 80, 2000, nil,
		lbStringPtr("c2"), lbStringPtr("Audi"), lbStringPtr("A4"), nil, nil)

	router := makeLeaderboardRouter()
	entries := fetchLeaderboard(t, router, "category=top_speed&period=last_24h&scope=global")

	if len(entries) != 1 {
		t.Fatalf("expected 1 row in last 24h window, got %d: %+v", len(entries), entries)
	}
	if entries[0].CarID == nil || *entries[0].CarID != "c1" {
		t.Errorf("expected only the 23h-old drive (c1), got car_id=%v", entries[0].CarID)
	}
}

func TestLeaderboard_PeriodLast7Days(t *testing.T) {
	jwtSecret = []byte("lb-7d-test-secret-32-bytes!!!!!!!")
	setupTestDB(t)

	user := User{Email: "p7d@test.com", Username: "p7d", AuthProvider: "google"}
	db.Create(&user)

	now := time.Now().UTC()
	// 5 days ago: included
	seedLeaderboardDrive(user.ID, now.Add(-5*24*time.Hour), 50, 1000, nil,
		lbStringPtr("c1"), lbStringPtr("BMW"), lbStringPtr("M3"), nil, nil)
	// 10 days ago: excluded
	seedLeaderboardDrive(user.ID, now.Add(-10*24*time.Hour), 80, 2000, nil,
		lbStringPtr("c2"), lbStringPtr("Audi"), lbStringPtr("A4"), nil, nil)

	router := makeLeaderboardRouter()
	entries := fetchLeaderboard(t, router, "category=top_speed&period=last_7_days&scope=global")

	if len(entries) != 1 {
		t.Fatalf("expected 1 row in last-7-days window, got %d: %+v", len(entries), entries)
	}
	if entries[0].CarID == nil || *entries[0].CarID != "c1" {
		t.Errorf("expected only the 5d-old drive (c1), got car_id=%v", entries[0].CarID)
	}
}

func TestLeaderboard_DriveCountCategoryRejected(t *testing.T) {
	jwtSecret = []byte("lb-dc-test-secret-32-bytes!!!!!!!!!")
	setupTestDB(t)

	router := makeLeaderboardRouter()
	code := fetchLeaderboardStatus(t, router, "category=drive_count&period=all_time&scope=global")
	if code != http.StatusBadRequest {
		t.Errorf("expected 400 for drive_count category, got %d", code)
	}
}

func TestLeaderboard_WeekCategoryRejected(t *testing.T) {
	jwtSecret = []byte("lb-week-test-secret-32-bytes!!!!!!!!")
	setupTestDB(t)

	router := makeLeaderboardRouter()
	code := fetchLeaderboardStatus(t, router, "category=top_speed&period=week&scope=global")
	if code != http.StatusBadRequest {
		t.Errorf("expected 400 for period=week, got %d", code)
	}
}

func TestLeaderboard_CapAt3CarsPerUser(t *testing.T) {
	jwtSecret = []byte("lb-cap3-test-secret-32-bytes!!!!!!!")
	setupTestDB(t)

	user := User{Email: "cap@test.com", Username: "capthree", AuthProvider: "google"}
	db.Create(&user)

	now := time.Now().UTC()
	// 5 distinct cars for the same user
	for i, speed := range []float64{50, 60, 70, 80, 90} {
		cid := fmt.Sprintf("c%d", i+1)
		seedLeaderboardDrive(user.ID, now.Add(-time.Duration(i+1)*time.Hour), speed, 1000, nil,
			&cid, nil, nil, nil, nil)
	}

	router := makeLeaderboardRouter()
	entries := fetchLeaderboard(t, router, "category=top_speed&period=all_time&scope=global")

	if len(entries) != 3 {
		t.Fatalf("expected exactly 3 rows per user cap, got %d: %+v", len(entries), entries)
	}
	// Ordered by value DESC: c5(90), c4(80), c3(70)
	wantOrder := []string{"c5", "c4", "c3"}
	for i, want := range wantOrder {
		if entries[i].CarID == nil || *entries[i].CarID != want {
			t.Errorf("rank %d: expected car_id=%s, got %v", i, want, entries[i].CarID)
		}
	}
}

func TestLeaderboard_PrivateUsersExcluded(t *testing.T) {
	jwtSecret = []byte("lb-priv-test-secret-32-bytes!!!!!!!!")
	setupTestDB(t)

	pub := User{Email: "pub@test.com", Username: "publiclb", AuthProvider: "google", IsPublic: true}
	priv := User{Email: "priv@test.com", Username: "privatelb", AuthProvider: "google"}
	db.Create(&pub)
	db.Create(&priv)
	// Force private user to actually be private (GORM default quirk).
	db.Model(&priv).Update("is_public", false)

	now := time.Now().UTC()
	// Public user has a strong drive
	seedLeaderboardDrive(pub.ID, now.Add(-time.Hour), 50, 1000, nil,
		lbStringPtr("c1"), lbStringPtr("BMW"), lbStringPtr("M3"), nil, nil)
	// Private user has a stronger drive — should be filtered out
	seedLeaderboardDrive(priv.ID, now.Add(-time.Hour), 200, 5000, nil,
		lbStringPtr("c2"), lbStringPtr("Audi"), lbStringPtr("A4"), nil, nil)

	router := makeLeaderboardRouter()
	entries := fetchLeaderboard(t, router, "category=top_speed&period=all_time&scope=global")

	if len(entries) != 1 {
		t.Fatalf("expected 1 row (private user excluded), got %d: %+v", len(entries), entries)
	}
	if entries[0].Username != "publiclb" {
		t.Errorf("expected publiclb in the result, got %q", entries[0].Username)
	}
}

// ─── Per-car photo upload tests ──────────────────────────────────────────────

func TestUploadCarPhoto_RoundTrips(t *testing.T) {
	jwtSecret = []byte("carphoto-test-secret-32-bytes-long!")
	setupTestDB(t)

	// Run uploads from a temp working directory so the writes are isolated.
	wd, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	tempDir := t.TempDir()
	if err := os.Chdir(tempDir); err != nil {
		t.Fatalf("chdir: %v", err)
	}
	defer func() { _ = os.Chdir(wd) }()

	const carID = "11111111-1111-1111-1111-111111111111"
	user := seedUserWithCar(t, "carphoto@test.com", "carphoto-user", carID)

	router := makeGaragePhotoRouter()
	pngBytes := tinyPNG(t)
	body, _ := json.Marshal(map[string]string{
		"image_data": base64.StdEncoding.EncodeToString(pngBytes),
	})
	req, _ := http.NewRequest("PUT", "/api/v1/garage/cars/"+carID+"/photo", bytes.NewBuffer(body))
	req.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body: %s)", w.Code, w.Body.String())
	}
	var resp CarPhotoResponse
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if resp.PhotoURL == "" {
		t.Fatalf("expected non-empty photo_url in response")
	}
	if !strings.Contains(resp.PhotoURL, "/uploads/garage_cars/") {
		t.Errorf("expected photo_url to be in /uploads/garage_cars/, got %q", resp.PhotoURL)
	}
	if !strings.Contains(resp.PhotoURL, carID) {
		t.Errorf("expected photo_url to contain carID %q, got %q", carID, resp.PhotoURL)
	}

	// File should be on disk under our tempDir's uploads/garage_cars/.
	// Resolve by listing the dir — the filename is salted with a UUID so we
	// can't predict it directly from the URL.
	entries, err := os.ReadDir(filepath.Join("uploads", "garage_cars"))
	if err != nil {
		t.Fatalf("read garage_cars dir: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("expected 1 file in garage_cars/, got %d", len(entries))
	}
	if !strings.HasSuffix(entries[0].Name(), ".png") {
		t.Errorf("expected .png file, got %q", entries[0].Name())
	}

	// GET /me should return the updated garage JSON with photo_url set.
	getReq, _ := http.NewRequest("GET", "/api/v1/me", nil)
	getReq.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	getW := httptest.NewRecorder()
	router.ServeHTTP(getW, getReq)
	if getW.Code != http.StatusOK {
		t.Fatalf("GET /me: expected 200, got %d (body: %s)", getW.Code, getW.Body.String())
	}
	var meResp User
	if err := json.Unmarshal(getW.Body.Bytes(), &meResp); err != nil {
		t.Fatalf("decode /me: %v", err)
	}
	if !strings.Contains(meResp.Garage, `"photo_url"`) {
		t.Errorf("expected /me garage to contain photo_url, got %q", meResp.Garage)
	}
	if !strings.Contains(meResp.Garage, resp.PhotoURL) {
		t.Errorf("expected /me garage to contain %q, got %q", resp.PhotoURL, meResp.Garage)
	}
}

func TestUploadCarPhoto_NilData400(t *testing.T) {
	jwtSecret = []byte("carphoto-nil-secret-32-bytes-long!!")
	setupTestDB(t)

	const carID = "22222222-2222-2222-2222-222222222222"
	user := seedUserWithCar(t, "carphoto-nil@test.com", "carphoto-nil", carID)

	router := makeGaragePhotoRouter()

	// Body with image_data explicitly empty.
	body, _ := json.Marshal(map[string]string{"image_data": ""})
	req, _ := http.NewRequest("PUT", "/api/v1/garage/cars/"+carID+"/photo", bytes.NewBuffer(body))
	req.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("empty image_data: expected 400, got %d (body: %s)", w.Code, w.Body.String())
	}

	// No body at all — the `binding:"required"` tag should also fire.
	req2, _ := http.NewRequest("PUT", "/api/v1/garage/cars/"+carID+"/photo", nil)
	req2.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	req2.Header.Set("Content-Type", "application/json")
	w2 := httptest.NewRecorder()
	router.ServeHTTP(w2, req2)
	if w2.Code != http.StatusBadRequest {
		t.Fatalf("missing body: expected 400, got %d (body: %s)", w2.Code, w2.Body.String())
	}
}

func TestUploadCarPhoto_RejectsOversizeImage(t *testing.T) {
	jwtSecret = []byte("carphoto-big-secret-32-bytes-long!!")
	setupTestDB(t)

	wd, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	tempDir := t.TempDir()
	if err := os.Chdir(tempDir); err != nil {
		t.Fatalf("chdir: %v", err)
	}
	defer func() { _ = os.Chdir(wd) }()

	const carID = "33333333-3333-3333-3333-333333333333"
	user := seedUserWithCar(t, "carphoto-big@test.com", "carphoto-big", carID)

	router := makeGaragePhotoRouter()

	// 9 MB of arbitrary bytes — well above the 8 MB cap.
	oversize := bytes.Repeat([]byte("A"), 9*1024*1024)
	body, _ := json.Marshal(map[string]string{
		"image_data": base64.StdEncoding.EncodeToString(oversize),
	})
	req, _ := http.NewRequest("PUT", "/api/v1/garage/cars/"+carID+"/photo", bytes.NewBuffer(body))
	req.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusRequestEntityTooLarge {
		t.Fatalf("oversize image: expected 413, got %d (body: %s)", w.Code, w.Body.String())
	}
}

func TestDeleteCarPhoto_RemovesFileAndField(t *testing.T) {
	jwtSecret = []byte("carphoto-del-secret-32-bytes-long!!")
	setupTestDB(t)

	wd, err := os.Getwd()
	if err != nil {
		t.Fatalf("getwd: %v", err)
	}
	tempDir := t.TempDir()
	if err := os.Chdir(tempDir); err != nil {
		t.Fatalf("chdir: %v", err)
	}
	defer func() { _ = os.Chdir(wd) }()

	const carID = "44444444-4444-4444-4444-444444444444"
	user := seedUserWithCar(t, "carphoto-del@test.com", "carphoto-del", carID)

	router := makeGaragePhotoRouter()

	// Upload a photo first.
	pngBytes := tinyPNG(t)
	body, _ := json.Marshal(map[string]string{
		"image_data": base64.StdEncoding.EncodeToString(pngBytes),
	})
	req, _ := http.NewRequest("PUT", "/api/v1/garage/cars/"+carID+"/photo", bytes.NewBuffer(body))
	req.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	req.Header.Set("Content-Type", "application/json")
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("upload: expected 200, got %d (body: %s)", w.Code, w.Body.String())
	}
	var resp CarPhotoResponse
	_ = json.Unmarshal(w.Body.Bytes(), &resp)
	entries, err := os.ReadDir(filepath.Join("uploads", "garage_cars"))
	if err != nil {
		t.Fatalf("read garage_cars dir: %v", err)
	}
	if len(entries) != 1 {
		t.Fatalf("expected 1 file in garage_cars/, got %d", len(entries))
	}
	localPath := filepath.Join("uploads", "garage_cars", entries[0].Name())

	// Delete the photo.
	delReq, _ := http.NewRequest("DELETE", "/api/v1/garage/cars/"+carID+"/photo", nil)
	delReq.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	delW := httptest.NewRecorder()
	router.ServeHTTP(delW, delReq)
	if delW.Code != http.StatusNoContent {
		t.Fatalf("delete: expected 204, got %d (body: %s)", delW.Code, delW.Body.String())
	}

	// File should be gone.
	if _, err := os.Stat(localPath); !os.IsNotExist(err) {
		t.Fatalf("expected photo file to be removed, stat err = %v", err)
	}

	// /me garage should no longer contain the URL.
	getReq, _ := http.NewRequest("GET", "/api/v1/me", nil)
	getReq.Header.Set("Authorization", "Bearer "+tokenForUser(t, user))
	getW := httptest.NewRecorder()
	router.ServeHTTP(getW, getReq)
	if getW.Code != http.StatusOK {
		t.Fatalf("GET /me: expected 200, got %d", getW.Code)
	}
	var meResp User
	_ = json.Unmarshal(getW.Body.Bytes(), &meResp)
	if strings.Contains(meResp.Garage, resp.PhotoURL) {
		t.Errorf("expected /me garage to not contain %q, got %q", resp.PhotoURL, meResp.Garage)
	}
	// Per the implementation contract: the field is set to "" (not removed)
	// so the round-trip is simple. iOS treats empty and missing equivalently.
	if !strings.Contains(meResp.Garage, `"photo_url":""`) {
		t.Errorf("expected /me garage to contain empty photo_url after delete, got %q", meResp.Garage)
	}
}

// ─── Public profile tests ──────────────────────────────────────────────────

// makeProfileRouter returns a router exposing GET /api/v1/users/:username with
// the optional-auth middleware that mirrors the production setup.
func makeProfileRouter() *gin.Engine {
	gin.SetMode(gin.TestMode)
	r := gin.New()
	api := r.Group("/api/v1")
	api.Use(optionalAuthMiddleware())
	api.GET("/users/:username", getPublicProfile)
	return r
}

func TestPublicProfile_IncludesCarStatsData(t *testing.T) {
	jwtSecret = []byte("profile-stats-test-secret-32-bytes!")
	setupTestDB(t)

	user := User{
		Email:        "statsuser@test.com",
		Username:     "statsuser",
		AuthProvider: "google",
		IsPublic:     true,
		Garage:       `[{"id":"c1","make":"Toyota","model":"Supra","year":2020}]`,
		CarStatsData: `{"c1":{"carId":"c1","totalDrives":5,"bestTopSpeed":60.0}}`,
	}
	db.Create(&user)

	router := makeProfileRouter()
	req, _ := http.NewRequest("GET", "/api/v1/users/statsuser", nil)
	w := httptest.NewRecorder()
	router.ServeHTTP(w, req)

	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d (body: %s)", w.Code, w.Body.String())
	}

	var resp map[string]interface{}
	if err := json.Unmarshal(w.Body.Bytes(), &resp); err != nil {
		t.Fatalf("decode: %v", err)
	}
	carStatsData, ok := resp["car_stats_data"]
	if !ok {
		t.Fatalf("expected car_stats_data field in public profile response, got keys: %v", resp)
	}
	if carStatsData != user.CarStatsData {
		t.Errorf("expected car_stats_data=%q, got %q", user.CarStatsData, carStatsData)
	}
}

func TestResolveBaseURL_TrimsTrailingSlash(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"", "https://fast.toper.dev"},
		{"https://fast.toper.dev", "https://fast.toper.dev"},
		{"https://fast.toper.dev/", "https://fast.toper.dev"},
		{"https://fast.toper.dev///", "https://fast.toper.dev"},
		{"http://localhost:8080/", "http://localhost:8080"},
	}
	for _, tc := range cases {
		t.Setenv("BASE_URL", tc.in)
		if got := resolveBaseURL(); got != tc.want {
			t.Errorf("resolveBaseURL() with BASE_URL=%q = %q, want %q", tc.in, got, tc.want)
		}
	}
}

// ─── deleteDrive tests ─────────────────────────────────────────────────────

func TestDeleteDrive_Unauthorized(t *testing.T) {
	jwtSecret = []byte("delete-drive-401-test-secret-32-by!")
	setupTestDB(t)
	r := makeAuthRouter()
	req := httptest.NewRequest("DELETE", "/api/v1/drives/1", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusUnauthorized {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestDeleteDrive_BadID(t *testing.T) {
	jwtSecret = []byte("delete-drive-400-test-secret-32-by!")
	setupTestDB(t)
	r := makeAuthRouter()
	user := User{Email: "dd400@test.com", Username: "dd400", AuthProvider: "google"}
	if err := db.Create(&user).Error; err != nil {
		t.Fatalf("seed user: %v", err)
	}
	token := tokenForUser(t, user)
	req := httptest.NewRequest("DELETE", "/api/v1/drives/notanint", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusBadRequest {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestDeleteDrive_NotFound(t *testing.T) {
	jwtSecret = []byte("delete-drive-404-test-secret-32-by!")
	setupTestDB(t)
	r := makeAuthRouter()
	user := User{Email: "dd404@test.com", Username: "dd404", AuthProvider: "google"}
	if err := db.Create(&user).Error; err != nil {
		t.Fatalf("seed user: %v", err)
	}
	token := tokenForUser(t, user)
	req := httptest.NewRequest("DELETE", "/api/v1/drives/999", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

func TestDeleteDrive_WrongOwner(t *testing.T) {
	jwtSecret = []byte("delete-drive-wng-test-secret-32-by!")
	setupTestDB(t)
	r := makeAuthRouter()
	// Owner user, drive belongs to owner.
	owner := User{Email: "ddowner@test.com", Username: "ddowner", AuthProvider: "google"}
	if err := db.Create(&owner).Error; err != nil {
		t.Fatalf("seed owner: %v", err)
	}
	drive := Drive{UserID: owner.ID, StartTime: time.Now(), EndTime: time.Now(), MaxSpeed: 30}
	if err := db.Create(&drive).Error; err != nil {
		t.Fatalf("seed drive: %v", err)
	}
	// Requesting user is someone else.
	intruder := User{Email: "ddintruder@test.com", Username: "ddintruder", AuthProvider: "google"}
	if err := db.Create(&intruder).Error; err != nil {
		t.Fatalf("seed intruder: %v", err)
	}
	token := tokenForUser(t, intruder)
	req := httptest.NewRequest("DELETE", fmt.Sprintf("/api/v1/drives/%d", drive.ID), nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusNotFound {
		t.Fatalf("expected 404 (no leak), got %d", w.Code)
	}
	if err := db.First(&Drive{}, drive.ID).Error; err != nil {
		t.Fatalf("drive should still exist after wrong-owner delete attempt, got err=%v", err)
	}
}

func TestDeleteDrive_HappyPath(t *testing.T) {
	jwtSecret = []byte("delete-drive-ok-test-secret-32-by!!")
	setupTestDB(t)
	r := makeAuthRouter()
	user := User{Email: "ddok@test.com", Username: "ddok", AuthProvider: "google"}
	if err := db.Create(&user).Error; err != nil {
		t.Fatalf("seed user: %v", err)
	}
	drive := Drive{UserID: user.ID, StartTime: time.Now(), EndTime: time.Now(), MaxSpeed: 30}
	if err := db.Create(&drive).Error; err != nil {
		t.Fatalf("seed drive: %v", err)
	}
	token := tokenForUser(t, user)
	req := httptest.NewRequest("DELETE", fmt.Sprintf("/api/v1/drives/%d", drive.ID), nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d body=%s", w.Code, w.Body.String())
	}
	if !strings.Contains(w.Body.String(), `"ok":true`) {
		t.Fatalf("expected ok:true in body, got %s", w.Body.String())
	}
	if err := db.First(&Drive{}, drive.ID).Error; err == nil {
		t.Fatalf("drive should be gone after delete")
	}
}

func TestDeleteDrive_NullsAchievementSource(t *testing.T) {
	jwtSecret = []byte("delete-drive-ach-test-secret-32-by!")
	setupTestDB(t)
	r := makeAuthRouter()
	user := User{Email: "ddach@test.com", Username: "ddach", AuthProvider: "google"}
	if err := db.Create(&user).Error; err != nil {
		t.Fatalf("seed user: %v", err)
	}
	drive := Drive{UserID: user.ID, StartTime: time.Now(), EndTime: time.Now(), MaxSpeed: 30}
	if err := db.Create(&drive).Error; err != nil {
		t.Fatalf("seed drive: %v", err)
	}
	driveID := drive.ID
	ua := UserAchievement{
		UserID:        user.ID,
		AchievementID: "test",
		SourceDriveID: &driveID,
	}
	if err := db.Create(&ua).Error; err != nil {
		t.Fatalf("seed: %v", err)
	}
	token := tokenForUser(t, user)
	req := httptest.NewRequest("DELETE", fmt.Sprintf("/api/v1/drives/%d", driveID), nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", w.Code)
	}
	var got UserAchievement
	if err := db.First(&got, ua.ID).Error; err != nil {
		t.Fatalf("achievement row missing: %v", err)
	}
	if got.SourceDriveID != nil {
		t.Fatalf("expected SourceDriveID nil, got %v", *got.SourceDriveID)
	}
}
