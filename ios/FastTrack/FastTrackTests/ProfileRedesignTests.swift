import XCTest
import UIKit
@testable import FastTrack

// PR 4 of #57: profile redesign. These tests cover the pure helpers
// introduced in `ProfileRedesignHelpers.swift`, the `PublicProfile`
// decode path for the new `garage` / `car_stats_data` fields, and the
// `AvatarZoomTarget` Identifiable wrapper that drives the tap-to-zoom
// fullScreenCover.

final class ProfileRedesignTests: XCTestCase {

    // MARK: - PublicProfileStats ordering

    /// Top Speed, Best 0-60, Total Distance — in that order. Total
    /// Drives is gone.
    func testPublicProfileStats_OrderIsTopSpeedThenBest060ThenTotalDistance() {
        let profile = sampleProfile(
            topSpeed: 30.0,           // 67 mph
            totalDistance: 1609.344,  // 1.0 mi
            best060: 4.25
        )
        let rows = PublicProfileStats.rows(for: profile)
        XCTAssertEqual(rows.map(\.label), ["Top Speed", "Best 0-60", "Total Distance"])
    }

    /// Total Drives must not appear anywhere in the rendered stats.
    func testPublicProfileStats_DoesNotIncludeTotalDrives() {
        let rows = PublicProfileStats.rows(for: sampleProfile(
            topSpeed: 30, totalDistance: 0, best060: nil
        ))
        XCTAssertFalse(rows.contains(where: { $0.label == "Total Drives" }))
        XCTAssertEqual(rows.count, 3)
    }

    /// Best 0-60 falls back to "N/A" when the server has no time for the
    /// user, otherwise it formats as "X.XX sec".
    func testPublicProfileStats_Best060Formatting() {
        let withTime = sampleProfile(topSpeed: 0, totalDistance: 0, best060: 4.25)
        XCTAssertEqual(PublicProfileStats.best060Display(withTime.best060Time), "4.25 sec")

        let withoutTime = sampleProfile(topSpeed: 0, totalDistance: 0, best060: nil)
        XCTAssertEqual(PublicProfileStats.best060Display(withoutTime.best060Time), "N/A")
    }

    // MARK: - Garage card short stats

    /// When the per-car stats have nothing meaningful recorded yet, the
    /// short-stats line is nil so the view can hide it entirely.
    func testGarageCardShortStats_NilWhenAllZero() {
        let stats = CarStats(carId: "x")
        XCTAssertNil(GarageCardShortStats.formattedLine(
            for: stats,
            speedUnit: "mph", distanceUnit: "mi",
            speedFactor: 2.23694, distanceFactor: 0.000621371
        ))
    }

    /// Nil input also returns nil (matches what the view sees when the
    /// server has no `car_stats_data` blob for this user).
    func testGarageCardShortStats_NilForMissingStats() {
        XCTAssertNil(GarageCardShortStats.formattedLine(
            for: nil,
            speedUnit: "mph", distanceUnit: "mi",
            speedFactor: 2.23694, distanceFactor: 0.000621371
        ))
    }

    /// All three segments show when each has a non-zero value, separated
    /// by the middle-dot delimiter.
    func testGarageCardShortStats_AllThreeSegmentsRender() {
        var stats = CarStats(carId: "x")
        stats.bestTopSpeed = 30.0          // 67 mph
        stats.bestZeroToSixty = 4.20      // 4.20s
        stats.totalDistance = 1609.344    // 1.0 mi

        let line = GarageCardShortStats.formattedLine(
            for: stats,
            speedUnit: "mph", distanceUnit: "mi",
            speedFactor: 2.23694, distanceFactor: 0.000621371
        )
        XCTAssertEqual(line, "Top: 67 mph · Best 0-60: 4.20s · Total: 1.0 mi")
    }

    /// Zero values are dropped, and the remaining segments still join
    /// correctly with the delimiter.
    func testGarageCardShortStats_ZeroValuesAreDropped() {
        var stats = CarStats(carId: "x")
        stats.bestTopSpeed = 30.0
        stats.bestZeroToSixty = 0
        stats.totalDistance = 1609.344

        let line = GarageCardShortStats.formattedLine(
            for: stats,
            speedUnit: "mph", distanceUnit: "mi",
            speedFactor: 2.23694, distanceFactor: 0.000621371
        )
        XCTAssertEqual(line, "Top: 67 mph · Total: 1.0 mi")
        XCTAssertFalse(line?.contains("0-60") ?? true)
    }

    /// Metric unit system flows through to the formatter.
    func testGarageCardShortStats_RespectsUnitSystem() {
        var stats = CarStats(carId: "x")
        stats.bestTopSpeed = 27.7778   // 100 km/h
        stats.totalDistance = 1000.0    // 1.0 km
        let line = GarageCardShortStats.formattedLine(
            for: stats,
            speedUnit: "km/h", distanceUnit: "km",
            speedFactor: 3.6, distanceFactor: 0.001
        )
        XCTAssertEqual(line, "Top: 100 km/h · Total: 1.0 km")
    }

    // MARK: - Followers / Following endpoint URL builder

    /// The followers/following endpoint paths follow /users/:username/.
    /// The exact match here is what `APIService.fetchFollowers` /
    /// `fetchFollowing` use, so a regression here would also break
    /// the live calls.
    func testFollowListEndpoint_FollowersPath() {
        XCTAssertEqual(
            FollowListEndpoint.followersPath(username: "fastdriver99"),
            "/users/fastdriver99/followers"
        )
    }

    func testFollowListEndpoint_FollowingPath() {
        XCTAssertEqual(
            FollowListEndpoint.followingPath(username: "fastdriver99"),
            "/users/fastdriver99/following"
        )
    }

    /// Usernames with reserved URL characters must be percent-encoded
    /// so the path is well-formed.
    func testFollowListEndpoint_PercentEncodesSpecialCharacters() {
        XCTAssertEqual(
            FollowListEndpoint.followersPath(username: "fast driver"),
            "/users/fast%20driver/followers"
        )
    }

    /// `/` must be encoded as `%2F` so a hostile username can't be
    /// treated as a path separator and route to the wrong endpoint.
    func testFollowListEndpoint_EncodesForwardSlash() {
        XCTAssertEqual(
            FollowListEndpoint.followersPath(username: "fast/driver"),
            "/users/fast%2Fdriver/followers"
        )
        XCTAssertEqual(
            FollowListEndpoint.followingPath(username: "fast/driver"),
            "/users/fast%2Fdriver/following"
        )
    }

    // MARK: - Garage blob decoding

    /// A valid JSON array string decodes into [UserCar].
    func testGarageBlob_DecodesValidArray() {
        let json = """
        [{"id":"a","make":"Honda","model":"Civic","year":2018,"trim":"","nickname":"","photo_url":""}]
        """
        let cars = GarageBlob.decode(json)
        XCTAssertEqual(cars.count, 1)
        XCTAssertEqual(cars.first?.make, "Honda")
    }

    /// Empty / missing / malformed input is treated as an empty garage
    /// (not a crash). This is the "no garage on the public profile"
    /// fallback.
    func testGarageBlob_HandlesEmptyNilAndMalformed() {
        XCTAssertTrue(GarageBlob.decode(nil).isEmpty)
        XCTAssertTrue(GarageBlob.decode("").isEmpty)
        XCTAssertTrue(GarageBlob.decode("not json at all").isEmpty)
        XCTAssertTrue(GarageBlob.decode("{not an array}").isEmpty)
    }

    // MARK: - PublicProfile decoding of new fields

    /// A PublicProfile JSON with the new `garage` and `car_stats_data`
    /// keys should decode both as String? values.
    func testPublicProfile_DecodesGarageAndCarStatsData() throws {
        let json = """
        {
          "username": "fastdriver99",
          "full_name": "Fast Driver",
          "country": "US",
          "avatar_url": "https://example.com/a.png",
          "member_since": "2025-01-01T00:00:00Z",
          "top_speed": 30.0,
          "total_distance": 1609.344,
          "drive_count": 7,
          "best_060_time": 4.25,
          "follower_count": 12,
          "following_count": 3,
          "is_followed_by_me": false,
          "garage": "[{\\"id\\":\\"a\\",\\"make\\":\\"Honda\\",\\"model\\":\\"Civic\\"}]",
          "car_stats_data": "{\\"a\\":{\\"carId\\":\\"a\\",\\"totalDrives\\":3}}"
        }
        """.data(using: .utf8)!

        let profile = try iso8601Decoder().decode(PublicProfile.self, from: json)
        XCTAssertEqual(profile.garage, "[{\"id\":\"a\",\"make\":\"Honda\",\"model\":\"Civic\"}]")
        XCTAssertEqual(profile.carStatsData, "{\"a\":{\"carId\":\"a\",\"totalDrives\":3}}")
    }

    /// Backward-compat: a PublicProfile JSON without the new keys
    /// (older backend) decodes with both new fields nil.
    func testPublicProfile_MissingGarageAndCarStatsDataDecodeToNil() throws {
        let json = """
        {
          "username": "fastdriver99",
          "full_name": "",
          "country": "",
          "avatar_url": "",
          "member_since": "2025-01-01T00:00:00Z",
          "top_speed": 0,
          "total_distance": 0,
          "drive_count": 0,
          "follower_count": 0,
          "following_count": 0,
          "is_followed_by_me": false
        }
        """.data(using: .utf8)!

        let profile = try iso8601Decoder().decode(PublicProfile.self, from: json)
        XCTAssertNil(profile.garage)
        XCTAssertNil(profile.carStatsData)
    }

    // MARK: - AvatarZoomTarget

    /// The Identifiable id is derived from the URL (or "memory" for the
    /// local-UIImage case) so presenting the same avatar twice in a row
    /// doesn't churn the fullScreenCover binding.
    func testAvatarZoomTarget_IdIsStableForSameURL() {
        let url = URL(string: "https://example.com/a.png")!
        XCTAssertEqual(AvatarZoomTarget(url: url).id, url.absoluteString)
        XCTAssertEqual(AvatarZoomTarget(url: url).id, AvatarZoomTarget(url: url).id)
    }

    /// Local-image zoom has a stable id of "memory" so the same in-memory
    /// UIImage presented twice is treated as one item.
    func testAvatarZoomTarget_IdIsMemoryForLocalImage() {
        let image = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).image { _ in }
        XCTAssertEqual(AvatarZoomTarget(image: image).id, "memory")
    }

    /// Two targets with the same URL compare equal (the fullScreenCover
    /// binding is value-based; this prevents repeat presentations).
    func testAvatarZoomTarget_EqualityForSameURL() {
        let url = URL(string: "https://example.com/a.png")!
        XCTAssertEqual(AvatarZoomTarget(url: url), AvatarZoomTarget(url: url))
    }

    // MARK: - ProfileView body section order (issue #64 regression guard)

    /// The achievements strip must render directly under the profile
    /// header and ahead of the garage section, so a returning user can
    /// see their recent unlocks without scrolling. This is a line-order
    /// regression guard rather than a SwiftUI snapshot: the project does
    /// not currently use ViewInspector and the layout itself is hard to
    /// inspect without it, but the *order* of the three sections in the
    /// body of `ProfileView` is straightforward to pin down.
    func testProfileView_AchievementsStripAboveGarage() throws {
        let source = try readProfileViewSource()
        let headerLine = try firstLineNumber(in: source, matching: "profileHeader")
        let stripLine = try firstLineNumber(in: source, matching: "RecentAchievementsStrip(driveManager:")
        let garageLine = try firstLineNumber(in: source, matching: "garageSection")
        XCTAssertGreaterThan(stripLine, headerLine,
            "RecentAchievementsStrip must come after profileHeader in ProfileView.swift")
        XCTAssertLessThan(stripLine, garageLine,
            "RecentAchievementsStrip must come before garageSection in ProfileView.swift")
    }

    // MARK: - "View Garage" entry point (Phase 2 / Track E)

    /// The garage section header must include a "View Garage" entry
    /// point that pushes `GarageView`. This is a structural guard:
    /// line-order source check, matching the pattern of the
    /// achievements-strip regression guard above. A regression that
    /// drops the link (or replaces `GarageView()` with a different
    /// destination) would break this test.
    func testProfileView_HasViewGarageLink() throws {
        let source = try readProfileViewSource()
        XCTAssertTrue(source.contains("View Garage"),
            "ProfileView.swift must contain a 'View Garage' entry point that pushes GarageView")
        XCTAssertTrue(source.contains("GarageView()"),
            "ProfileView.swift must push a GarageView destination from the 'View Garage' link")
    }

    // MARK: - Helpers

    private func readProfileViewSource() throws -> String {
        // `#filePath` resolves to this test's source file at compile time.
        // The project layout is `ios/FastTrack/FastTrack/Views/...` (the
        // outer `FastTrack/` is the Xcode project folder, the inner
        // `FastTrack/` is the source root), so the candidate path
        // walks from `FastTrackTests/…` up one level and re-descends
        // into `FastTrack/Views/...`.
        let thisFile = (#filePath as NSString)
        let candidates = [
            thisFile.deletingLastPathComponent + "/../FastTrack/Views/ProfileView.swift",
            thisFile.deletingLastPathComponent + "/../../FastTrack/FastTrack/Views/ProfileView.swift",
        ].map { (path: String) -> String in
            (path as NSString).standardizingPath
        }
        for path in candidates {
            if let data = FileManager.default.contents(atPath: path),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        XCTFail("ProfileView.swift not found at expected locations: \(candidates). Regression guard cannot run.")
        struct FileNotFound: Error {}
        throw FileNotFound()
    }

    private func firstLineNumber(in text: String, matching needle: String) throws -> Int {
        var lineNo = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNo += 1
            if line.contains(needle) { return lineNo }
        }
        XCTFail("Did not find \(needle) in ProfileView.swift. Section-order regression guard cannot run.")
        struct SectionMarkerNotFound: Error {}
        throw SectionMarkerNotFound()
    }

    private func iso8601Decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    private func sampleProfile(
        topSpeed: Double,
        totalDistance: Double,
        best060: Double?
    ) -> PublicProfile {
        PublicProfile(
            username: "fastdriver99",
            fullName: "Fast Driver",
            country: "US",
            avatarURL: "",
            memberSince: Date(timeIntervalSince1970: 0),
            topSpeed: topSpeed,
            totalDistance: totalDistance,
            driveCount: 0,
            best060Time: best060,
            followerCount: 0,
            followingCount: 0,
            isFollowedByMe: false,
            garage: nil,
            carStatsData: nil
        )
    }
}
