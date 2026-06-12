import XCTest
@testable import FastTrack

// The "You" marker on the car-centric leaderboard must be driven by the
// row's `userId`, not its `carId`. A user with multiple cars on the board
// (up to three — one per car) should see the badge on *all* of their rows.
// See `LeaderboardYouMarker.swift`.

final class LeaderboardYouMarkerTests: XCTestCase {

    // MARK: - Helpers

    /// Build a `LeaderboardEntry` with the minimum fields the predicate
    /// reads. The other fields are filled with placeholders so the decode
    /// path in the helper struct isn't a distraction here.
    private func entry(userId: Int, carKey: String = "car-A") -> LeaderboardEntry {
        LeaderboardEntry(
            rank: 1,
            userId: userId,
            username: "driver",
            country: "",
            avatarURL: "",
            value: 0,
            carId: carKey,
            carKey: carKey,
            carMake: "",
            carModel: "",
            carYear: nil,
            carTrim: nil,
            carNickname: nil,
            carPhotoUrl: nil
        )
    }

    // MARK: - Same userId across multiple rows

    /// The car-centric board can show the same user up to three times.
    /// All three rows must be marked "You" when the current user's id
    /// matches — regardless of the row's carId. This is the regression
    /// guard: the previous code keyed off `carId == selectedCarId`, so
    /// a user with three cars only saw the badge on the one matching
    /// their currently-selected car.
    func testIsCurrentUser_MatchesByUserIdNotCarId() {
        let currentUserId = 123
        let rowA = entry(userId: currentUserId, carKey: "car-A")
        let rowB = entry(userId: currentUserId, carKey: "car-B")
        let rowC = entry(userId: currentUserId, carKey: "car-C")

        XCTAssertTrue(LeaderboardYouMarker.isCurrentUser(entry: rowA, currentUserId: currentUserId))
        XCTAssertTrue(LeaderboardYouMarker.isCurrentUser(entry: rowB, currentUserId: currentUserId))
        XCTAssertTrue(LeaderboardYouMarker.isCurrentUser(entry: rowC, currentUserId: currentUserId))
    }

    // MARK: - Different user

    /// A row belonging to a different user must not be marked "You",
    /// even if its carId happens to match the current user's selected
    /// car (carIds in this app are UUIDs, so collisions are vanishingly
    /// unlikely — but the test guards the intent of the predicate).
    func testIsCurrentUser_DifferentUser() {
        let otherUser = entry(userId: 999, carKey: "car-A")
        XCTAssertFalse(LeaderboardYouMarker.isCurrentUser(entry: otherUser, currentUserId: 123))
    }

    // MARK: - No current user

    /// When the local profile hasn't been restored yet (e.g. before
    /// sign-in completes), there is no current user to compare against.
    /// The marker must not light up on every row.
    func testIsCurrentUser_NoCurrentUser() {
        let row = entry(userId: 123, carKey: "car-A")
        XCTAssertFalse(LeaderboardYouMarker.isCurrentUser(entry: row, currentUserId: nil))
    }

    // MARK: - Profile id backfill

    /// `ProfileManager.restoreFromServer` must set `profile.id` on an
    /// upgraded client whose previously-saved `UserProfile` doesn't have
    /// an id yet, even when the server returns a smaller (or empty)
    /// garage. The previous implementation only overwrote the local
    /// profile when the local was empty or the server garage was larger,
    /// so the id never got backfilled and the leaderboard "You" marker
    /// could not find the current user.
    func testRestoreFromServer_BackfillsIdOnNonEmptyLocalProfile() async {
        resetProfileManager()
        let local = UserProfile(
            username: "alice",
            country: "US",
            garage: [UserCar(make: "Honda", model: "Civic")],
            selectedCarId: nil
        )
        ProfileManager(apiService: APIService()).saveProfile(local)
        XCTAssertNil(ProfileManager(apiService: APIService()).profile?.id, "precondition: local profile has no id")

        let serverUser = makeServerUser(id: 42, username: "alice", garage: nil)
        await ProfileManager(apiService: APIService()).restoreFromServer(serverUser: serverUser)

        XCTAssertEqual(ProfileManager(apiService: APIService()).profile?.id, 42)
        XCTAssertEqual(ProfileManager(apiService: APIService()).profile?.username, "alice")
        XCTAssertEqual(ProfileManager(apiService: APIService()).profile?.garage.count, 1,
                       "garage should be preserved when the server returns a smaller one")
    }

    /// The id backfill must also persist through UserDefaults so a
    /// subsequent relaunch sees the new id.
    func testRestoreFromServer_IdBackfillPersistsToUserDefaults() async {
        resetProfileManager()
        ProfileManager(apiService: APIService()).saveProfile(
            UserProfile(username: "bob", country: "", garage: [], selectedCarId: nil)
        )
        XCTAssertNil(ProfileManager(apiService: APIService()).profile?.id)

        await ProfileManager(apiService: APIService()).restoreFromServer(
            serverUser: makeServerUser(id: 7, username: "bob", garage: nil)
        )
        XCTAssertEqual(ProfileManager(apiService: APIService()).profile?.id, 7)

        // Re-load from UserDefaults to confirm the id was actually written.
        let saved = UserDefaults.standard.data(forKey: "user_profile_v2")
        let decoded = try? JSONDecoder().decode(UserProfile.self, from: saved ?? Data())
        XCTAssertEqual(decoded?.id, 7, "id must be persisted, not just held in memory")
    }

    /// The id is not overwritten if the local profile already has one.
    /// (Backfill is one-way: never clobber a known id with a stale
    /// server-side value, even if it disagrees.)
    func testRestoreFromServer_DoesNotOverwriteExistingId() async {
        resetProfileManager()
        ProfileManager(apiService: APIService()).saveProfile(
            UserProfile(
                id: 99,
                username: "carol",
                country: "",
                garage: [],
                selectedCarId: nil
            )
        )

        await ProfileManager(apiService: APIService()).restoreFromServer(
            serverUser: makeServerUser(id: 1, username: "carol", garage: nil)
        )
        XCTAssertEqual(ProfileManager(apiService: APIService()).profile?.id, 99)
    }

    // MARK: - UserProfile id round-trip

    /// Building a `UserProfile` with an explicit id (the way the
    /// `ProfileSetupView.save()` fix does) and re-saving it must keep
    /// the id through JSON encode/decode. This guards the regression
    /// where the id would silently disappear and break the "You" marker.
    func testUserProfile_IdSurvivesEncodeAndDecode() throws {
        let original = UserProfile(
            id: 42,
            username: "alice",
            country: "US",
            garage: [UserCar(make: "Honda", model: "Civic")],
            selectedCarId: nil
        )
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(UserProfile.self, from: data)
        XCTAssertEqual(decoded.id, 42)
        XCTAssertEqual(decoded.username, "alice")
    }

    // MARK: - Helpers

    private func resetProfileManager() {
        UserDefaults.standard.removeObject(forKey: "user_profile_v2")
        ProfileManager(apiService: APIService()).clearProfile()
    }

    private func makeServerUser(id: Int, username: String, garage: String?) -> User {
        User(
            id: id,
            appleUserID: nil,
            googleUserID: nil,
            email: nil,
            fullName: nil,
            username: username,
            country: nil,
            avatarURL: nil,
            carMake: nil,
            carModel: nil,
            carYear: nil,
            carTrim: nil,
            garage: garage,
            selectedCarID: nil,
            carStatsData: nil,
            unitSystem: nil,
            colorScheme: nil,
            authProvider: nil,
            createdAt: Date(),
            updatedAt: Date()
        )
    }
}
