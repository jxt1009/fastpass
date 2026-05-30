package main

import (
	"bytes"
	"encoding/json"
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

func stringPtr(value string) *string {
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
	if err := db.AutoMigrate(&User{}, &Drive{}, &Follow{}); err != nil {
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
	}
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
	userA := User{Email: "a@test.com", AppleUserID: stringPtr("apple.a"), Username: "usera"}
	userB := User{Email: "b@test.com", AppleUserID: stringPtr("apple.b"), Username: "userb"}
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

	userA := User{Email: "a2@test.com", AppleUserID: stringPtr("apple.a2"), Username: "usera2"}
	userB := User{Email: "b2@test.com", AppleUserID: stringPtr("apple.b2"), Username: "userb2"}
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

	user := User{Email: "owner@test.com", AppleUserID: stringPtr("apple.owner"), Username: "owner"}
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

	userA := User{Email: "list_a@test.com", AppleUserID: stringPtr("apple.list_a"), Username: "lista"}
	userB := User{Email: "list_b@test.com", AppleUserID: stringPtr("apple.list_b"), Username: "listb"}
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
		{path: "/", wantSnippet: "<title>FastTrack — Performance Driving App</title>"},
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
