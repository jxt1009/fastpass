# Worktree B — Issue #81: Leaderboard car photo Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Populate `car_photo_url` in the `/api/v1/leaderboard` response from each row's matching `User.Garage` entry so the iOS leaderboard rows render the selected car photo instead of the placeholder icon.

**Architecture:** Add a `garage.go` helper in the backend that parses the existing `User.Garage` JSON text column and returns a per-(userID, carID) → photoURL index. In `getLeaderboard`, run a single batched `SELECT id, garage FROM users WHERE id IN (...)` over the unique userIDs in the response page, then copy each row's `car_photo_url` onto its `LeaderboardEntry`. iOS needs no changes — the field is already declared on the struct and decoded on the client.

**Tech Stack:** Go 1.x, GORM, PostgreSQL (prod) / SQLite (test), iOS Swift (read-only consumer).

---

## File Structure

### Create

- `backend/internal/app/garage.go` — parse-and-index helper for the `User.Garage` JSON blob
- `backend/internal/app/garage_test.go` — table-driven unit tests for the parser
- `docs/superpowers/plans/2026-06-10-leaderboard-photo-runbook.md` — short ops runbook (added to the existing plan collection; not a code change, just an index entry)

### Modify

- `backend/internal/app/social_handlers.go` — populate `entry.CarPhotoURL` via the new helper

No iOS changes. No migrations. No new dependencies.

---

## Task 1: Add a Garage index helper

**Files:**
- Create: `backend/internal/app/garage.go`

- [ ] **Step 1: Create `garage.go` with the parser and indexer**

Create the file `backend/internal/app/garage.go`:

```go
package app

import (
	"bytes"
	"encoding/json"
	"errors"
)

// GarageCar mirrors the JSON shape of one element of the User.Garage array.
// Only the fields we currently read are declared; add more here as needed.
type GarageCar struct {
	ID       string `json:"id"`
	PhotoURL string `json:"photo_url"`
}

// ParseGarage unmarshals the User.Garage text column into a slice of cars.
// Returns an empty slice (no error) for empty/whitespace input, an error
// for malformed JSON, and propagates unmarshal errors for type mismatches.
func ParseGarage(blob string) ([]GarageCar, error) {
	raw := []byte(blob)
	if len(bytes.TrimSpace(raw)) == 0 {
		raw = []byte("[]")
	}
	var cars []GarageCar
	if err := json.Unmarshal(raw, &cars); err != nil {
		return nil, err
	}
	return cars, nil
}

// IndexGaragePhotoURLs returns a map keyed by GarageCar.ID whose values are
// each car's photo_url ("" if absent). The index is built in O(n) over
// `cars`. This is the shape we want for the leaderboard lookup: a single
// map per user that we can query by carID in O(1).
func IndexGaragePhotoURLs(cars []GarageCar) map[string]string {
	out := make(map[string]string, len(cars))
	for _, c := range cars {
		if c.ID == "" {
			continue
		}
		out[c.ID] = c.PhotoURL
	}
	return out
}

// BuildUserGarageIndex is a convenience that combines ParseGarage and
// IndexGaragePhotoURLs. A malformed garage blob produces a nil index and
// an error; callers should treat that as "no photo available" for the
// affected user and continue.
func BuildUserGarageIndex(blob string) (map[string]string, error) {
	cars, err := ParseGarage(blob)
	if err != nil {
		return nil, err
	}
	return IndexGaragePhotoURLs(cars), nil
}

// ErrGarageBlobInvalid is returned by ParseGarage when the blob is not
// valid JSON. (Currently unused externally but reserved for callers that
// want to distinguish malformed JSON from other parse failures.)
var ErrGarageBlobInvalid = errors.New("garage blob is not valid JSON")
```

- [ ] **Step 2: Build to verify it compiles**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-81-leaderboard-photo
CGO_ENABLED=1 go build ./...
```

Expected: clean build, no errors. (`ErrGarageBlobInvalid` is declared for future use; that's fine — `go vet` will not flag it as unused inside a non-test file.)

- [ ] **Step 3: Commit**

```bash
git add backend/internal/app/garage.go
git commit -m "feat(backend): add garage JSON parser and photoURL indexer"
```

---

## Task 2: Add unit tests for the parser

**Files:**
- Create: `backend/internal/app/garage_test.go`

- [ ] **Step 1: Write the failing tests**

Create `backend/internal/app/garage_test.go`:

```go
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
```

- [ ] **Step 2: Run tests to verify they pass**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-81-leaderboard-photo
CGO_ENABLED=1 go test ./internal/app/ -run "TestParseGarage|TestIndexGaragePhotoURLs|TestBuildUserGarageIndex" -v
```

Expected: 3 test functions, all pass; subtests under `TestParseGarage` (5 total: empty, whitespace, two-cars, no-photo, malformed) all pass.

- [ ] **Step 3: Commit**

```bash
git add backend/internal/app/garage_test.go
git commit -m "test(backend): cover garage parser, indexer, and convenience helper"
```

---

## Task 3: Wire the leaderboard handler to populate `car_photo_url`

**Files:**
- Modify: `backend/internal/app/social_handlers.go:219-238` (the entries construction loop, plus the surrounding `getLeaderboard` function)

- [ ] **Step 1: Read the current shape of the response loop**

Confirm that the loop at `social_handlers.go:219-238` still looks like the version you read at planning time. It builds `entries` from `rows` and JSON-encodes the result. We do not change the SQL; we add a post-pass that walks `entries` and populates `CarPhotoURL`.

- [ ] **Step 2: Add the batched garage lookup after the existing loop**

In `social_handlers.go`, replace the block from `entries := make(...)` through `c.JSON(http.StatusOK, entries)` with the version below. The diff is contained — it leaves the existing loop intact and appends a `// Populate car_photo_url` section before the response write.

```go
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

	// Populate car_photo_url from each row's user's Garage JSON. The
	// per-user garage is opaque text, so we batch-load the unique
	// userIDs in the page and parse once per user. A malformed garage
	// for one user does not poison the rest of the response — we
	// simply skip that user's photo.
	populateLeaderboardCarPhotos(&entries)

	c.JSON(http.StatusOK, entries)
```

- [ ] **Step 3: Add the `populateLeaderboardCarPhotos` helper at the bottom of `social_handlers.go`**

Append (after the last existing function in the file) the following helper:

```go
// populateLeaderboardCarPhotos does a single batched SELECT for the
// unique userIDs present in `entries`, parses each user's garage JSON
// blob, and writes the matching car.photo_url onto every entry that
// references that user. It is safe to call on an empty entries slice.
func populateLeaderboardCarPhotos(entries *[]LeaderboardEntry) {
	if entries == nil || len(*entries) == 0 {
		return
	}

	// Collect unique userIDs that have a carID (we only need garages
	// for rows that could carry a photo).
	seen := make(map[uint]struct{}, len(*entries))
	userIDs := make([]uint, 0, len(*entries))
	for _, e := range *entries {
		if e.CarID == nil || *e.CarID == "" {
			continue
		}
		if _, ok := seen[e.UserID]; ok {
			continue
		}
		seen[e.UserID] = struct{}{}
		userIDs = append(userIDs, e.UserID)
	}
	if len(userIDs) == 0 {
		return
	}

	// Single batched SELECT — limit is the leaderboard page size (50)
	// and a user appears up to 3 times, so this is at most 50 IDs.
	type userGarageRow struct {
		ID     uint   `gorm:"column:id"`
		Garage string `gorm:"column:garage"`
	}
	var rows []userGarageRow
	db.Table("users").Select("id, garage").Where("id IN ?", userIDs).Scan(&rows)

	// Build userID -> carID -> photoURL index.
	photoIndex := make(map[uint]map[string]string, len(rows))
	for _, r := range rows {
		idx, err := BuildUserGarageIndex(r.Garage)
		if err != nil {
			// Malformed garage: skip this user. Don't poison the
			// whole response — other users still get photos.
			continue
		}
		photoIndex[r.ID] = idx
	}

	// Stamp the field on every matching entry. We use a local
	// variable so we can take its address; the response only emits
	// the field when non-nil, preserving the existing null vs. URL
	// behavior the iOS app already handles.
	for i, e := range *entries {
		if e.CarID == nil {
			continue
		}
		idx, ok := photoIndex[e.UserID]
		if !ok {
			continue
		}
		url, ok := idx[*e.CarID]
		if !ok || url == "" {
			continue
		}
		(*entries)[i].CarPhotoURL = &url
	}
}
```

- [ ] **Step 4: Build to verify it compiles**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-81-leaderboard-photo
CGO_ENABLED=1 go build ./...
```

Expected: clean build.

- [ ] **Step 5: Run the full backend test suite**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-81-leaderboard-photo
CGO_ENABLED=1 go test ./... -timeout 60s
```

Expected: all existing tests pass, new garage tests pass.

- [ ] **Step 6: Add an end-to-end handler test for the photo population**

This is the integration test that locks the fix. Append to `backend/internal/app/garage_test.go` (or a new file `leaderboard_photo_test.go` if you prefer — the test imports test-only helpers, so it must stay in the `app` package):

```go
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
		ID:      1001,
		Garage:  `[{"id":"car-a","photo_url":"https://x/a.jpg"},{"id":"car-b","photo_url":""}]`,
		IsPublic: true,
	})
	db.Create(&User{
		ID:      1002,
		Garage:  `[{"id":"car-c","photo_url":"https://x/c.jpg"}]`,
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
	db.Create(&User{ID: 2001, Garage: "not json at all", IsPublic: true})
	db.Create(&User{ID: 2002, Garage: `[{"id":"x","photo_url":"https://x/x.jpg"}]`, IsPublic: true})

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
```

- [ ] **Step 7: Run the new tests to verify they pass**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-81-leaderboard-photo
CGO_ENABLED=1 go test ./internal/app/ -run "TestPopulateLeaderboardCarPhotos" -v
```

Expected: all 3 sub-tests pass.

- [ ] **Step 8: Run the full backend suite once more**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-81-leaderboard-photo
CGO_ENABLED=1 go test ./... -timeout 60s
```

Expected: all tests pass.

- [ ] **Step 9: Commit**

```bash
git add backend/internal/app/social_handlers.go backend/internal/app/garage_test.go
git commit -m "feat(backend): populate car_photo_url on leaderboard response from User.Garage

The LeaderboardEntry struct has always declared car_photo_url, but
the SQL query and construction loop never set it. This adds a
single batched SELECT for the page's unique userIDs, parses each
user's garage JSON, and stamps the matching car.photo_url onto
every row. A malformed garage for one user does not poison the
rest of the response. iOS already decodes the field and renders
it via CarThumbnail; no client changes required."
```

---

## Task 4: Verify the iOS side needs no changes

**Files:** none

- [ ] **Step 1: Confirm the iOS decoder and view already handle the field**

Run:
```bash
cd /Users/jtoper/DEV/fasttrack/.worktrees/issue-81-leaderboard-photo
grep -n "carPhotoUrl\|car_photo_url" ios/FastTrack/FastTrack/Models/SocialModels.swift
grep -n "carPhotoUrl" ios/FastTrack/FastTrack/Views/SocialView.swift
```

Expected: the model declares `carPhotoUrl: String?` with `CodingKeys: car_photo_url`, and `LeaderboardRow` calls `CarThumbnail(urlString: entry.carPhotoUrl, size: 40)`. Both already exist; nothing to change.

- [ ] **Step 2: Confirm `CarThumbnail` renders the URL when present**

In `SocialView.swift`, confirm that `CarThumbnail(urlString: size:)` shows `AsyncImage` for non-nil/non-empty URLs and the placeholder `car.fill` SF symbol for nil/empty. It already does (per the planning investigation); no edit needed.

- [ ] **Step 3: Commit nothing** — verification only.

---

## Task 5: Commit the spec reference into the worktree

**Files:**
- Modify: `docs/superpowers/plans/` (index note added by the implementing agent — optional)

- [ ] **Step 1: Optional — add a one-line entry to `docs/superpowers/plans/README.md` if it exists**

If a `README.md` exists in `docs/superpowers/plans/`, add a one-line link to the new plan file. If it doesn't exist, skip this step (don't create a new doc just to hold one link).

---

## Verification

- [ ] **Final test pass:** `CGO_ENABLED=1 go test ./... -timeout 60s` clean
- [ ] **Build:** `CGO_ENABLED=1 go build ./...` clean
- [ ] **Manual smoke (optional, requires staging):** `curl /api/v1/leaderboard` against staging, confirm one of the rows has a non-null `car_photo_url` matching the user's garage

## Definition of done

- All four tasks committed with conventional-commit messages
- `go test ./...` and `go build ./...` clean
- iOS app needs no rebuild — existing App Store release will start showing car photos on the next launch once the backend deploys
