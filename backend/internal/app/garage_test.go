package app

import (
	"reflect"
	"testing"
)

func TestParseGarage(t *testing.T) {
	tests := []struct {
		name    string
		blob    string
		want    []GarageCar
		wantErr bool
	}{
		{
			name: "empty string",
			blob: "",
			want: []GarageCar{},
		},
		{
			name: "whitespace only",
			blob: "   \n\t  ",
			want: []GarageCar{},
		},
		{
			name: "two cars with photos",
			blob: `[{"id":"a","make":"Honda","photo_url":"https://x/a.jpg"},{"id":"b","make":"BMW","photo_url":"https://x/b.jpg"}]`,
			want: []GarageCar{
				{ID: "a", PhotoURL: "https://x/a.jpg"},
				{ID: "b", PhotoURL: "https://x/b.jpg"},
			},
		},
		{
			name: "car without photo_url",
			blob: `[{"id":"a","make":"Honda"}]`,
			want: []GarageCar{{ID: "a", PhotoURL: ""}},
		},
		{
			name:    "malformed JSON",
			blob:    `[{"id":"a"`,
			wantErr: true,
		},
	}
	for _, tc := range tests {
		t.Run(tc.name, func(t *testing.T) {
			got, err := ParseGarage(tc.blob)
			if (err != nil) != tc.wantErr {
				t.Fatalf("ParseGarage() error = %v, wantErr %v", err, tc.wantErr)
			}
			if !tc.wantErr && !reflect.DeepEqual(got, tc.want) {
				t.Errorf("ParseGarage() = %+v, want %+v", got, tc.want)
			}
		})
	}
}

func TestIndexGaragePhotoURLs(t *testing.T) {
	cars := []GarageCar{
		{ID: "a", PhotoURL: "https://x/a.jpg"},
		{ID: "b", PhotoURL: "https://x/b.jpg"},
		{ID: "c", PhotoURL: ""},
		{ID: "", PhotoURL: "ignored"}, // empty id → skipped
	}
	got := IndexGaragePhotoURLs(cars)
	want := map[string]string{
		"a": "https://x/a.jpg",
		"b": "https://x/b.jpg",
		"c": "",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("IndexGaragePhotoURLs() = %+v, want %+v", got, want)
	}
}

func TestBuildUserGarageIndex(t *testing.T) {
	t.Run("valid blob", func(t *testing.T) {
		idx, err := BuildUserGarageIndex(`[{"id":"a","photo_url":"https://x/a.jpg"}]`)
		if err != nil {
			t.Fatalf("unexpected error: %v", err)
		}
		if idx["a"] != "https://x/a.jpg" {
			t.Errorf("idx[a] = %q, want %q", idx["a"], "https://x/a.jpg")
		}
	})
	t.Run("malformed blob returns error", func(t *testing.T) {
		_, err := BuildUserGarageIndex(`not json`)
		if err == nil {
			t.Error("expected error for malformed JSON, got nil")
		}
	})
}

// Helper: seed two users and exercise the leaderboard SQL against
// the in-memory SQLite. Uses the same DB that the rest of the test
// suite shares (handler tests use SQLite; production uses Postgres —
// this is the project's established pattern).
//
// IMPORTANT: this test exercises the population helper directly,
// not the full HTTP stack, so we don't depend on the wider handler
// test harness shape. (If a leaderboard_test.go already exists, the
// same assertions can be moved there; the helper is the testable
// surface either way.)
func TestPopulateLeaderboardCarPhotos(t *testing.T) {
	setupTestDB(t)
	// Three entries: user 1 with a car that has a photo, user 1
	// again with a different car (no photo), user 2 with a car
	// that has a photo.
	carA := "car-a"
	carB := "car-b"
	carC := "car-c"
	photoA := "https://x/a.jpg"
	photoC := "https://x/c.jpg"

	// Seed the users table with garage JSON blobs.
	db.Create(&User{
		ID:       1001,
		Username: "user-1001",
		Garage:   `[{"id":"car-a","photo_url":"https://x/a.jpg"},{"id":"car-b","photo_url":""}]`,
		IsPublic: true,
	})
	db.Create(&User{
		ID:       1002,
		Username: "user-1002",
		Garage:   `[{"id":"car-c","photo_url":"https://x/c.jpg"}]`,
		IsPublic: true,
	})

	entries := []LeaderboardEntry{
		{Rank: 1, UserID: 1001, CarID: &carA},
		{Rank: 2, UserID: 1001, CarID: &carB},
		{Rank: 3, UserID: 1002, CarID: &carC},
		{Rank: 4, UserID: 1003, CarID: nil}, // no car, no lookup
	}
	populateLeaderboardCarPhotos(&entries)

	if entries[0].CarPhotoURL == nil || *entries[0].CarPhotoURL != photoA {
		t.Errorf("entries[0].CarPhotoURL = %v, want %q", entries[0].CarPhotoURL, photoA)
	}
	if entries[1].CarPhotoURL != nil {
		t.Errorf("entries[1].CarPhotoURL = %v, want nil (car-b has no photo)", entries[1].CarPhotoURL)
	}
	if entries[2].CarPhotoURL == nil || *entries[2].CarPhotoURL != photoC {
		t.Errorf("entries[2].CarPhotoURL = %v, want %q", entries[2].CarPhotoURL, photoC)
	}
	if entries[3].CarPhotoURL != nil {
		t.Errorf("entries[3].CarPhotoURL = %v, want nil (no carID)", entries[3].CarPhotoURL)
	}
}

func TestPopulateLeaderboardCarPhotos_MalformedGarageIsSkipped(t *testing.T) {
	setupTestDB(t)
	db.Create(&User{ID: 2001, Username: "user-2001", Garage: "not json at all", IsPublic: true})
	db.Create(&User{ID: 2002, Username: "user-2002", Garage: `[{"id":"x","photo_url":"https://x/x.jpg"}]`, IsPublic: true})

	carX := "x"
	carY := "y"
	entries := []LeaderboardEntry{
		{Rank: 1, UserID: 2001, CarID: &carY}, // user 2001 garage is malformed
		{Rank: 2, UserID: 2002, CarID: &carX}, // user 2002 is fine
	}
	populateLeaderboardCarPhotos(&entries)

	if entries[0].CarPhotoURL != nil {
		t.Errorf("entries[0].CarPhotoURL = %v, want nil (malformed garage)", entries[0].CarPhotoURL)
	}
	if entries[1].CarPhotoURL == nil || *entries[1].CarPhotoURL != "https://x/x.jpg" {
		t.Errorf("entries[1].CarPhotoURL = %v, want %q", entries[1].CarPhotoURL, "https://x/x.jpg")
	}
}

func TestPopulateLeaderboardCarPhotos_EmptyAndNilSafe(t *testing.T) {
	// nil slice: no-op, no panic.
	populateLeaderboardCarPhotos(nil)
	// empty slice: no-op, no panic.
	empty := []LeaderboardEntry{}
	populateLeaderboardCarPhotos(&empty)
	if len(empty) != 0 {
		t.Errorf("empty input grew to %d entries", len(empty))
	}
}
