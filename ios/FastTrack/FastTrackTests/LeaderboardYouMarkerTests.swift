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
}
