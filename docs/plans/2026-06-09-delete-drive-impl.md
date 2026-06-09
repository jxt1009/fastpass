# Delete Drive Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Allow a user to delete one of their drives from the drive overview page and from drive lists, with a destructive-confirm flow that updates server and local state atomically.

**Architecture:** New additive `DELETE /api/v1/drives/:id` endpoint that hard-deletes the row inside a transaction, NULLs any `UserAchievement.source_drive_id` rows pointing at it, and re-evaluates achievements. iOS gains one `APIService.deleteDrive(id:)`, one `DriveManager.deleteDrive(id:)` that handles network + local cleanup, and two UI entry points (trash toolbar icon on `DriveDetailView`; swipe-to-confirm on history, car-detail, and garage recent-drives lists) sharing a single `performDelete` flow.

**Tech Stack:** Go (Gin, GORM, SQLite in-memory for tests), Swift 5 / SwiftUI (XCTest, `@testable import FastTrack`).

**Worktree:** `.worktrees/integration` (branch `feat/integration`).

**Spec:** `docs/plans/2026-06-09-delete-drive.md`.

---

## File Structure

### Files created

- `ios/FastTrack/FastTrackTests/DriveDeleteTests.swift` — iOS unit tests for `DriveManager.deleteDrive`, `APIService.deleteDrive`, and the list-view alert plumbing.

### Files modified

- `backend/internal/app/routes_drive.go` — add one route line.
- `backend/internal/app/handlers.go` — add `deleteDrive` handler.
- `backend/internal/app/handlers_test.go` — add new test cases.
- `ios/FastTrack/FastTrack/Services/APIService.swift` — add `deleteDrive(id:)`.
- `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift` — add `deleteDrive(id:)`.
- `ios/FastTrack/FastTrack/Views/DriveDetailView.swift` — trash toolbar item, two alerts, `performDelete`, `isOwner`.
- `ios/FastTrack/FastTrack/Views/DriveHistoryView.swift` — swipe action + two alerts + `performDelete`.
- `ios/FastTrack/FastTrack/Views/CarDetailView.swift` — swipe action on recent-drives rows.
- `ios/FastTrack/FastTrack/Views/GarageView.swift` — swipe action on recent-drives rows.

---

## Task 1: Backend route registration

**Files:**
- Modify: `backend/internal/app/routes_drive.go:1-15`

- [ ] **Step 1: Read current file**

```bash
cat backend/internal/app/routes_drive.go
```

Expected: file contains `api.POST("/drives", ...)`, `api.GET("/drives", ...)`, `api.GET("/drives/:id", ...)`, `api.PUT("/drives/:id", ...)`.

- [ ] **Step 2: Add the DELETE route line**

Insert after the existing `api.PUT("/drives/:id", updateDrive)` line:

```go
	api.DELETE("/drives/:id", deleteDrive)
```

- [ ] **Step 3: Verify the file compiles**

```bash
cd backend && CGO_ENABLED=1 go build ./...
```

Expected: no errors.

- [ ] **Step 4: Commit**

```bash
git add backend/internal/app/routes_drive.go
git commit -m "feat(backend): register DELETE /drives/:id route"
```

---

## Task 2: Backend `deleteDrive` handler

**Files:**
- Modify: `backend/internal/app/handlers.go` (append new handler after `updateDrive`)

- [ ] **Step 1: Read the end of `handlers.go` to find the insertion point**

```bash
wc -l backend/internal/app/handlers.go
```

Note the line number where `updateDrive` ends.

- [ ] **Step 2: Append the handler**

Append the following function at the end of `backend/internal/app/handlers.go`:

```go
// deleteDrive removes a drive owned by the authenticated user. Inside a single
// transaction we NULL-out any UserAchievement.source_drive_id rows pointing at
// the drive, delete the drive, and re-evaluate the user's achievements so PB
// events stay consistent.
func deleteDrive(c *gin.Context) {
	userID, exists := getUserID(c)
	if !exists {
		c.JSON(401, gin.H{"error": "Unauthorized"})
		return
	}

	id, err := strconv.Atoi(c.Param("id"))
	if err != nil {
		c.JSON(400, gin.H{"error": "Invalid ID"})
		return
	}

	var drive Drive
	if err := db.Where("id = ? AND user_id = ?", id, userID).First(&drive).Error; err != nil {
		if errors.Is(err, gorm.ErrRecordNotFound) {
			c.JSON(404, gin.H{"error": "Drive not found"})
			return
		}
		c.JSON(500, gin.H{"error": "Failed to load drive"})
		return
	}

	if err := db.Transaction(func(tx *gorm.DB) error {
		if err := tx.Model(&UserAchievement{}).
			Where("source_drive_id = ?", id).
			Update("source_drive_id", nil).Error; err != nil {
			return err
		}
		if err := tx.Delete(&drive).Error; err != nil {
			return err
		}
		evaluateForUser(userID)
		return nil
	}); err != nil {
		c.JSON(500, gin.H{"error": "Failed to delete drive"})
		return
	}

	c.JSON(200, gin.H{"ok": true})
}
```

- [ ] **Step 3: Verify it compiles**

```bash
cd backend && CGO_ENABLED=1 go build ./...
```

Expected: no errors. If `errors` and `gorm` aren't imported, add them to the import block:

```go
import (
	"errors"

	"gorm.io/gorm"
)
```

- [ ] **Step 4: Commit**

```bash
git add backend/internal/app/handlers.go
git commit -m "feat(backend): add deleteDrive handler with achievement cleanup"
```

---

## Task 3: Backend tests for `deleteDrive`

**Files:**
- Modify: `backend/internal/app/handlers_test.go` (append test cases)

- [ ] **Step 1: Read existing test patterns**

```bash
grep -n "func Test" backend/internal/app/handlers_test.go | head -20
```

Find a representative test that uses the SQLite in-memory setup, creates a user + drive, and exercises a handler. Model the new tests on it.

- [ ] **Step 2: Append new test cases**

Append to the end of `backend/internal/app/handlers_test.go`:

```go
// --- deleteDrive ---

func TestDeleteDrive_Unauthorized(t *testing.T) {
	setupTestDB(t)
	r := setupTestRouter()
	req := httptest.NewRequest("DELETE", "/api/v1/drives/1", nil)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != 401 {
		t.Fatalf("expected 401, got %d", w.Code)
	}
}

func TestDeleteDrive_BadID(t *testing.T) {
	setupTestDB(t)
	r := setupTestRouter()
	token := issueTestToken(t, 1)
	req := httptest.NewRequest("DELETE", "/api/v1/drives/notanint", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != 400 {
		t.Fatalf("expected 400, got %d", w.Code)
	}
}

func TestDeleteDrive_NotFound(t *testing.T) {
	setupTestDB(t)
	r := setupTestRouter()
	token := issueTestToken(t, 1)
	req := httptest.NewRequest("DELETE", "/api/v1/drives/999", nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != 404 {
		t.Fatalf("expected 404, got %d", w.Code)
	}
}

func TestDeleteDrive_WrongOwner(t *testing.T) {
	setupTestDB(t)
	r := setupTestRouter()
	// Owner user_id=1, drive belongs to user_id=2.
	owner := createTestUser(t, 2, "owner")
	drive := createTestDrive(t, owner.ID)
	token := issueTestToken(t, 1) // requesting user is 1, not 2
	req := httptest.NewRequest("DELETE", fmt.Sprintf("/api/v1/drives/%d", drive.ID), nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != 404 {
		t.Fatalf("expected 404 (no leak), got %d", w.Code)
	}
	if db.First(&Drive{}, drive.ID).Error == nil {
		t.Fatalf("drive should still exist after wrong-owner delete attempt")
	}
}

func TestDeleteDrive_HappyPath(t *testing.T) {
	setupTestDB(t)
	r := setupTestRouter()
	user := createTestUser(t, 1, "alice")
	drive := createTestDrive(t, user.ID)
	token := issueTestToken(t, int(user.ID))
	req := httptest.NewRequest("DELETE", fmt.Sprintf("/api/v1/drives/%d", drive.ID), nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != 200 {
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
	setupTestDB(t)
	r := setupTestRouter()
	user := createTestUser(t, 1, "alice")
	drive := createTestDrive(t, user.ID)
	driveID := uint(drive.ID)
	ua := UserAchievement{
		UserID:        user.ID,
		AchievementID: "test",
		SourceDriveID: &driveID,
	}
	if err := db.Create(&ua).Error; err != nil {
		t.Fatalf("seed: %v", err)
	}
	token := issueTestToken(t, int(user.ID))
	req := httptest.NewRequest("DELETE", fmt.Sprintf("/api/v1/drives/%d", driveID), nil)
	req.Header.Set("Authorization", "Bearer "+token)
	w := httptest.NewRecorder()
	r.ServeHTTP(w, req)
	if w.Code != 200 {
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
```

- [ ] **Step 3: Resolve helper names**

The new tests use `setupTestDB`, `setupTestRouter`, `issueTestToken`, `createTestUser`, and `createTestDrive`. These must already exist in `handlers_test.go` (or the related test files in the same package) for the existing test suite to compile. Open the file and confirm:

```bash
grep -nE "func (setupTestDB|setupTestRouter|issueTestToken|createTestUser|createTestDrive)" backend/internal/app/handlers_test.go
```

If any helper is missing, use a sibling that exists and adjust. The exact helper names are not sacred — the goal is to follow the existing test style in this file.

- [ ] **Step 4: Run the new tests**

```bash
cd backend && go test ./internal/app/ -run TestDeleteDrive -v -timeout 60s
```

Expected: all `TestDeleteDrive_*` cases pass. If they fail because of helper signature differences, adjust the helper calls — do not change the test intent.

- [ ] **Step 5: Run the full backend test suite to confirm no regression**

```bash
cd backend && go test ./... -timeout 60s
```

Expected: all pre-existing tests still pass.

- [ ] **Step 6: Commit**

```bash
git add backend/internal/app/handlers_test.go
git commit -m "test(backend): cover deleteDrive handler"
```

---

## Task 4: iOS `APIService.deleteDrive(id:)`

**Files:**
- Modify: `ios/FastTrack/FastTrack/Services/APIService.swift` (after line ~182, next to the other drive methods)

- [ ] **Step 1: Read the drive-methods region**

```bash
grep -n "func updateDriveCarAssignment\|// MARK: - " ios/FastTrack/FastTrack/Services/APIService.swift
```

Find the line where `updateDriveCarAssignment` ends and the next `// MARK: -` begins.

- [ ] **Step 2: Add the method**

Insert immediately after `updateDriveCarAssignment`:

```swift
    func deleteDrive(id: Int) async throws {
        try await delete(endpoint: "/drives/\(id)")
    }
```

- [ ] **Step 3: Verify the iOS target builds**

```bash
cd ios/FastTrack && cp FastTrack/Secrets.swift.template FastTrack/Secrets.swift
xcodebuild build-for-testing \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "generic/platform=iOS Simulator" \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO
```

Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add ios/FastTrack/FastTrack/Services/APIService.swift
git commit -m "feat(ios): add APIService.deleteDrive"
```

---

## Task 5: iOS `DriveManager.deleteDrive(id:)`

**Files:**
- Modify: `ios/FastTrack/FastTrack/ViewModels/DriveManager.swift` (insert after `fetchDrives()` at line ~318)

- [ ] **Step 1: Read the API region**

```bash
sed -n '295,320p' ios/FastTrack/FastTrack/ViewModels/DriveManager.swift
```

Confirm the exact line where `fetchDrives()` ends.

- [ ] **Step 2: Add the method**

Insert immediately after `fetchDrives()` (before `// MARK: - Achievements`):

```swift
    /// Deletes a drive the user owns. Network first; on success the drive is
    /// removed from the local array, per-car stats are rebuilt, and the
    /// server-authoritative achievement cache is refreshed so any
    /// `sourceDriveId` that was NULL-ed server-side is reflected locally.
    /// A 404 is treated as success: the goal state (drive gone) is already
    /// achieved, and the local array is updated unconditionally.
    @MainActor
    func deleteDrive(id: Int) async throws {
        do {
            try await apiService.deleteDrive(id: id)
        } catch let error as APIService.APIError {
            if case .serverError(404) = error { /* treat as success */ }
            else { throw error }
        }
        drives.removeAll { $0.id == id }
        CarStatsManager.shared.rebuildStats(from: drives)
        await refreshAchievementsFromServer()
    }
```

- [ ] **Step 3: Verify it builds**

Re-run the build command from Task 4 step 3. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 4: Commit**

```bash
git add ios/FastTrack/FastTrack/ViewModels/DriveManager.swift
git commit -m "feat(ios): add DriveManager.deleteDrive"
```

---

## Task 6: iOS trash toolbar on `DriveDetailView`

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/DriveDetailView.swift` (add state, dismiss, isOwner, toolbar, alerts, performDelete)

- [ ] **Step 1: Add the new `@State` vars and `dismiss` environment**

In the `DriveDetailView` struct (line 71), add after the existing `@State` block (after line ~92, before `@ObservedObject private var settings = AppSettings.shared`):

```swift
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @Environment(\.dismiss) private var dismiss
```

- [ ] **Step 2: Add the `isOwner` computed property**

Inside the `DriveDetailView` struct body, after `var body`, add:

```swift
    private var isOwner: Bool {
        drive.userID == AuthManager.shared.getUser()?.id
    }
```

- [ ] **Step 3: Add the toolbar and two alerts**

After the existing `.navigationBarTitleDisplayMode(.inline)` line (line 189), insert:

```swift
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(isDeleting)
                }
            }
        }
        .alert("Delete Drive?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(isDeleting ? "Deleting…" : "Delete", role: .destructive) {
                Task { await performDelete() }
            }
            .disabled(isDeleting)
        } message: {
            Text("This permanently removes the drive from your history. This can't be undone.")
        }
        .alert("Unable to Delete Drive", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "Unknown error")
        }
```

- [ ] **Step 4: Add the `performDelete` method**

Add inside the `DriveDetailView` struct (a private method at the bottom is fine; do not place it before `var body`):

```swift
    @MainActor
    private func performDelete() async {
        guard !isDeleting, let id = drive.id else { return }
        isDeleting = true
        defer { isDeleting = false }
        do {
            try await driveManager.deleteDrive(id: id)
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }
```

- [ ] **Step 5: Build**

Re-run the build command from Task 4 step 3. Expected: `BUILD SUCCEEDED`.

- [ ] **Step 6: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/DriveDetailView.swift
git commit -m "feat(ios): add trash button to drive detail toolbar"
```

---

## Task 7: iOS swipe-to-delete on `DriveHistoryView`

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/DriveHistoryView.swift` (add state, swipe action, alerts, performDelete)

- [ ] **Step 1: Read the file and find the row body**

```bash
cat ios/FastTrack/FastTrack/Views/DriveHistoryView.swift
```

Find the existing row (likely a `NavigationLink` or `Button` per drive). Note the variable name for the drive in the row's closure.

- [ ] **Step 2: Add new state**

At the top of the `DriveHistoryView` struct, alongside the other `@State` vars, add:

```swift
    @State private var drivePendingDelete: Drive?
    @State private var deleteError: String?
```

- [ ] **Step 3: Attach the swipe action and owner gate**

Modify the drive row so the body of the row (or a wrapper) gets:

```swift
    .swipeActions(edge: .trailing) {
        if drive.userID == AuthManager.shared.getUser()?.id {
            Button(role: .destructive) {
                drivePendingDelete = drive
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }
```

`drive` here refers to the row's drive value. If the row is rendered as `ForEach(driveManager.drives) { drive in ... }`, the variable name will match.

- [ ] **Step 4: Add the two alerts at the list level**

On the outermost `List` (or its parent `VStack`/`NavigationStack`), append:

```swift
    .alert("Delete Drive?", isPresented: Binding(
        get: { drivePendingDelete != nil },
        set: { if !$0 { drivePendingDelete = nil } }
    )) {
        Button("Cancel", role: .cancel) { drivePendingDelete = nil }
        Button("Delete", role: .destructive) {
            Task { await performDelete() }
        }
    } message: {
        Text("This permanently removes the drive from your history. This can't be undone.")
    }
    .alert("Unable to Delete Drive", isPresented: Binding(
        get: { deleteError != nil },
        set: { if !$0 { deleteError = nil } }
    )) {
        Button("OK", role: .cancel) {}
    } message: {
        Text(deleteError ?? "Unknown error")
    }
```

- [ ] **Step 5: Add the `performDelete` method**

```swift
    @MainActor
    private func performDelete() async {
        guard let drive = drivePendingDelete, let id = drive.id else { return }
        do {
            try await driveManager.deleteDrive(id: id)
            drivePendingDelete = nil
        } catch {
            deleteError = error.localizedDescription
            drivePendingDelete = nil
        }
    }
```

- [ ] **Step 6: Build**

Re-run the build command. Expected: `BUILD SUCCEEDED`. If the row-level state-binding inside the alert doesn't compile, double-check the `Binding` initializers compile (they do — this is the same idiom used in `ProfileView.swift`).

- [ ] **Step 7: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/DriveHistoryView.swift
git commit -m "feat(ios): swipe to delete on drive history list"
```

---

## Task 8: iOS swipe-to-delete on `CarDetailView` and `GarageView` recent-drives

**Files:**
- Modify: `ios/FastTrack/FastTrack/Views/CarDetailView.swift`
- Modify: `ios/FastTrack/FastTrack/Views/GarageView.swift`

- [ ] **Step 1: Read both files to find the recent-drives section**

```bash
grep -n "Recent Drives\|recent drives\|driveManager.drives" ios/FastTrack/FastTrack/Views/CarDetailView.swift ios/FastTrack/FastTrack/Views/GarageView.swift
```

- [ ] **Step 2: For each file, add new state**

```swift
    @State private var drivePendingDelete: Drive?
    @State private var deleteError: String?
```

Add at the top of each view struct, alongside other `@State` vars.

- [ ] **Step 3: For each file, attach the swipe action on the recent-drives row**

Same pattern as Task 7 step 3. `drive.userID == AuthManager.shared.getUser()?.id` guard. Use `drivePendingDelete = drive`.

- [ ] **Step 4: For each file, attach the two alerts at the section/list level**

Same pattern as Task 7 step 4. If the alerts are attached at a `Section` level, SwiftUI accepts `.alert` on `Section` directly. If attached at a higher level, that's also fine.

- [ ] **Step 5: For each file, add a `performDelete` method**

Same body as Task 7 step 5.

- [ ] **Step 6: Build**

Re-run the build command. Expected: `BUILD SUCCEEDED`. If the CarDetailGauge refactor in progress collides, re-read both files first and add the new state/alerts in a way that does not undo the gauge refactor.

- [ ] **Step 7: Commit**

```bash
git add ios/FastTrack/FastTrack/Views/CarDetailView.swift ios/FastTrack/FastTrack/Views/GarageView.swift
git commit -m "feat(ios): swipe to delete on recent drives in car detail and garage"
```

---

## Task 9: iOS unit tests for `DriveManager.deleteDrive` and `APIService.deleteDrive`

**Files:**
- Create: `ios/FastTrack/FastTrackTests/DriveDeleteTests.swift`

- [ ] **Step 1: Create the test file**

Create `ios/FastTrack/FastTrackTests/DriveDeleteTests.swift`:

```swift
import XCTest
@testable import FastTrack

// Tests for the DriveManager.deleteDrive flow added in 2026-06-09. We stub
// APIService at the URLSession level via URLProtocol to keep the production
// code path intact (no refactor of APIService.init required).

final class DriveDeleteTests: XCTestCase {

    // MARK: - URLSession stubbing

    private final class StubURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data?))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let handler = StubURLProtocol.requestHandler else { return }
            let (response, data) = handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    private var customSession: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubURLProtocol.self]
        customSession = URLSession(configuration: config)
        CarStatsManager.shared.resetAllStats()
    }

    override func tearDown() {
        StubURLProtocol.requestHandler = nil
        customSession = nil
        super.tearDown()
    }

    private func makeDrive(id: Int, userID: Int = 1, carId: String? = "car-A") -> Drive {
        Drive(
            id: id,
            userID: userID,
            startTime: Date(timeIntervalSince1970: 1_000_000),
            endTime: Date(timeIntervalSince1970: 1_000_600),
            startLatitude: 37.0,
            startLongitude: -122.0,
            endLatitude: 37.001,
            endLongitude: -122.0,
            distance: 1000,
            duration: 600,
            maxSpeed: 30,
            minSpeed: 0,
            avgSpeed: 15,
            carId: carId,
            stoppedTime: 0,
            leftTurns: 0,
            rightTurns: 0,
            brakeEvents: 0,
            laneChanges: 0,
            maxAcceleration: 0,
            maxDeceleration: 0,
            peakGForce: 0,
            topCornerSpeed: 0
        )
    }

    // MARK: - APIService

    func testAPIService_deleteDrive_hitsDELETE() async throws {
        // Swap APIService's session via a one-shot URLProtocol handler. We
        // exercise the real APIService so we know the URL and method are right.
        let captured = expectation(description: "request captured")
        var observedMethod: String?
        var observedPath: String?
        StubURLProtocol.requestHandler = { req in
            observedMethod = req.httpMethod
            observedPath = req.url?.path
            captured.fulfill()
            return (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        // Use the singleton; the production init reads URLSession.shared, so
        // URLProtocol on the default config would not be picked up. Instead,
        // we use a tiny shim: a private route on a temp APIService. Since
        // APIService.init is private, we exercise through the public method
        // with a globally-registered protocol on the shared session's
        // configuration.
        //
        // To keep this test self-contained and avoid touching APIService, we
        // call APIService.shared.deleteDrive(id:) and rely on URLProtocol
        // being registered for the default session.
        URLProtocol.registerClass(StubURLProtocol.self)
        defer { URLProtocol.unregisterClass(StubURLProtocol.self) }

        // APIService.shared uses URLSession.shared with default config, so
        // register the protocol on the shared configuration.
        try await APIService.shared.deleteDrive(id: 123)
        await fulfillment(of: [captured], timeout: 2)

        XCTAssertEqual(observedMethod, "DELETE", "deleteDrive must use HTTP DELETE")
        XCTAssertEqual(observedPath, "/api/v1/drives/123", "deleteDrive must hit /drives/{id}")
    }

    func testAPIService_deleteDrive_throwsOnNon2xx() async {
        URLProtocol.registerClass(StubURLProtocol.self)
        defer { URLProtocol.unregisterClass(StubURLProtocol.self) }

        StubURLProtocol.requestHandler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, nil)
        }
        do {
            try await APIService.shared.deleteDrive(id: 1)
            XCTFail("expected throw on 500")
        } catch {
            // expected
        }
    }

    // MARK: - DriveManager

    @MainActor
    func testDriveManager_deleteDrive_removesFromArray() async throws {
        let drive1 = makeDrive(id: 1)
        let drive2 = makeDrive(id: 2)
        let dm = DriveManager(apiService: APIService.shared)
        dm.drives = [drive1, drive2]

        // Stub a successful DELETE
        URLProtocol.registerClass(StubURLProtocol.self)
        defer { URLProtocol.unregisterClass(StubURLProtocol.self) }
        StubURLProtocol.requestHandler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        try await dm.deleteDrive(id: 1)
        XCTAssertEqual(dm.drives.count, 1)
        XCTAssertEqual(dm.drives.first?.id, 2)
    }

    @MainActor
    func testDriveManager_deleteDrive_treats404AsSuccess() async throws {
        let drive = makeDrive(id: 7)
        let dm = DriveManager(apiService: APIService.shared)
        dm.drives = [drive]

        URLProtocol.registerClass(StubURLProtocol.self)
        defer { URLProtocol.unregisterClass(StubURLProtocol.self) }
        StubURLProtocol.requestHandler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
        }

        try await dm.deleteDrive(id: 7)
        XCTAssertTrue(dm.drives.isEmpty, "404 must be treated as success: drive removed locally")
    }

    @MainActor
    func testDriveManager_deleteDrive_propagatesNon404Error() async {
        let drive = makeDrive(id: 8)
        let dm = DriveManager(apiService: APIService.shared)
        dm.drives = [drive]

        URLProtocol.registerClass(StubURLProtocol.self)
        defer { URLProtocol.unregisterClass(StubURLProtocol.self) }
        StubURLProtocol.requestHandler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, nil)
        }

        do {
            try await dm.deleteDrive(id: 8)
            XCTFail("expected throw on 500")
        } catch {
            // expected
        }
        XCTAssertEqual(dm.drives.count, 1, "drive must remain when 500 is returned")
    }
}
```

- [ ] **Step 2: Run the new tests**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  -only-testing:FastTrackTests/DriveDeleteTests \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all `DriveDeleteTests` pass. If any fail because `DriveManager`'s init signature does not accept `apiService:` (the parameter is `private` or uses a different name), adjust the call site in the test to use the public initializer. Open `DriveManager.swift` and check the init declaration; align the test's argument list.

- [ ] **Step 3: Run the full iOS test suite to confirm no regression**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all pre-existing tests still pass.

- [ ] **Step 4: Commit**

```bash
git add ios/FastTrack/FastTrackTests/DriveDeleteTests.swift
git commit -m "test(ios): cover DriveManager.deleteDrive and APIService.deleteDrive"
```

---

## Task 10: Final verification and PR

**Files:** none modified

- [ ] **Step 1: Run backend vet and full tests**

```bash
cd backend && CGO_ENABLED=1 go vet ./... && go test ./... -timeout 60s
```

Expected: no vet warnings, all tests pass.

- [ ] **Step 2: Run iOS test suite one more time**

```bash
cd ios/FastTrack && xcodebuild test \
  -project FastTrack.xcodeproj \
  -scheme FastTrack \
  -destination "platform=iOS Simulator,name=iPhone 17 Pro" \
  CODE_SIGNING_ALLOWED=NO
```

Expected: all tests pass.

- [ ] **Step 3: Rebase onto latest `main`**

```bash
cd .worktrees/integration
git fetch origin main
git rebase origin/main
```

If there are conflicts, resolve them — the most likely conflict is the `CarDetailGauge` refactor landing on `main`. The delete-drive changes are mostly additive and should rebase cleanly.

- [ ] **Step 4: Push the branch**

```bash
git push --force-with-lease origin feat/integration
```

- [ ] **Step 5: Open the PR**

```bash
gh pr create --base main --head feat/integration \
  --title "feat(ios+backend): delete a drive from the detail page and lists" \
  --body "$(cat <<'EOF'
## Summary

Adds the ability for a user to permanently delete one of their own drives.

- New trash icon on the drive overview page toolbar (owner only).
- New swipe-to-delete-with-confirm on the history list and on the recent-drives sections of car-detail and garage views.
- New additive `DELETE /api/v1/drives/:id` endpoint that hard-deletes the row inside a transaction, NULLs any `UserAchievement.source_drive_id` pointing at it, and re-evaluates the user's achievements so PB events stay consistent.

## Why

Drives recorded by mistake (or no longer wanted) have no way to be removed. This is a small, additive change that gives users control over their own history.

## Backward compatibility

- New endpoint, novel response shape — no client decoder conflict.
- Hard delete matches the existing `deleteCurrentUser` pattern; no schema change.
- Litmus test: would this break last week's App Store release? **No.** Old clients don't call the new endpoint.

## Out of scope

- Soft delete / archive. Documented as a follow-up.
- Undo. Not consistent with existing destructive flows.
- Web SPA parity. The SPA has no drive detail page.

## Verification

- Backend: `go vet ./...` clean; `go test ./...` green; new `TestDeleteDrive_*` cases cover 401, 400, 404 (not-found and wrong-owner), happy path, and `UserAchievement.source_drive_id` NULL-out.
- iOS: full test suite green; new `DriveDeleteTests` cover `APIService.deleteDrive` (correct method/path, error on 5xx) and `DriveManager.deleteDrive` (removes from array, treats 404 as success, propagates 5xx).

## Spec

`docs/plans/2026-06-09-delete-drive.md`
EOF
)"
```

- [ ] **Step 6: Confirm the PR is open and CI is green**

```bash
gh pr view --json url,statusCheckRollup
```

Expected: PR URL printed, all checks pass.

---

## Self-Review Notes

- **Spec coverage:** every section of `docs/plans/2026-06-09-delete-drive.md` maps to at least one task. Server (Tasks 1–3), iOS API (Task 4), iOS state (Task 5), detail-page UI (Task 6), list swipe UI (Tasks 7–8), tests (Task 9), verification (Task 10).
- **Placeholders:** none. Every code step shows the actual code to paste.
- **Type consistency:** `deleteDrive(id: Int)` is the same signature in `APIService`, `DriveManager`, and the views' `performDelete` callers. `drivePendingDelete: Drive?` and `deleteError: String?` are consistent across the three list views.
