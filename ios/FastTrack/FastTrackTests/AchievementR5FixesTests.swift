import XCTest
@testable import FastTrack

// Tests for the R5 achievement fixes: `isSecret` backward-compatible
// Codable decode, local zeroToSixty/smoothness progress, and the
// consecutive-day streak same-day fix. These exercise the public
// `AchievementManager.updateProgress` surface and the `Achievement`
// decoder; private helpers are covered indirectly.
final class AchievementR5FixesTests: XCTestCase {

    // MARK: - isSecret backward-compatible decode

    /// Persisted achievements that pre-date `isSecret` (key absent in
    /// `user_achievements_v2` UserDefaults data) must still decode so a
    /// user keeps their unlocked state on app update.
    func testAchievement_DecodesWithoutIsSecretKey() throws {
        let json = """
        {
            "id": "x", "title": "T", "description": "D",
            "category": "Speed", "icon": "i",
            "requirement": {"type": "max_speed", "value": 10, "condition": null},
            "isUnlocked": true, "unlockedDate": null, "progress": 1.0, "sourceDriveId": 7
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(Achievement.self, from: json)
        XCTAssertEqual(decoded.id, "x")
        XCTAssertTrue(decoded.isUnlocked)
        XCTAssertEqual(decoded.sourceDriveId, 7)
        XCTAssertEqual(decoded.progress, 1.0, accuracy: 1e-9)
        XCTAssertFalse(decoded.isSecret, "missing isSecret key must default to false")
    }

    /// `isSecret` round-trips through encode/decode.
    func testAchievement_IsSecretRoundTrips() throws {
        let original = Achievement(
            id: "secret", title: "S", description: "",
            category: .speed, icon: "i",
            requirement: AchievementRequirement(type: .maxSpeed, value: 1, condition: nil),
            isSecret: true
        )
        let data = try JSONEncoder().encode(original)
        let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(object?["isSecret"], "encoded payload must include isSecret")

        let decoded = try JSONDecoder().decode(Achievement.self, from: data)
        XCTAssertTrue(decoded.isSecret)
    }

    /// The catalog marks Speed Demon + Smooth Operator as secret.
    func testCatalog_Speed150AndSmoothOperatorAreSecret() {
        let catalog = AchievementCatalog.createDefaultAchievements()
        let speed150 = catalog.first { $0.id == "speed_150" }
        let smooth = catalog.first { $0.id == "smooth_operator" }
        XCTAssertEqual(speed150?.isSecret, true)
        XCTAssertEqual(smooth?.isSecret, true)
        // Sanity: non-secret achievements stay non-secret.
        let firstDrive = catalog.first { $0.id == "first_drive" }
        XCTAssertEqual(firstDrive?.isSecret, false)
    }

    // MARK: - zeroToSixty local progress

    func testZeroToSixty_UnlocksWhenAtOrUnderThreshold() {
        let manager = freshManager()
        let drives = [makeDrive(startTime: Date(), best060Time: 5.0)]
        manager.updateProgress(with: drives)

        guard let sub6 = manager.achievements.first(where: { $0.id == "sub_6_club" }) else {
            return XCTFail("sub_6_club missing")
        }
        XCTAssertEqual(sub6.progress, 1.0, accuracy: 1e-9)
        XCTAssertTrue(sub6.isUnlocked)
    }

    func testZeroToSixty_PartialProgressWhenAboveThreshold() {
        let manager = freshManager()
        let drives = [makeDrive(startTime: Date(), best060Time: 8.0)]
        manager.updateProgress(with: drives)

        guard let sub6 = manager.achievements.first(where: { $0.id == "sub_6_club" }) else {
            return XCTFail("sub_6_club missing")
        }
        // requirement(6) / best(8) = 0.75
        XCTAssertEqual(sub6.progress, 6.0 / 8.0, accuracy: 1e-9)
        XCTAssertFalse(sub6.isUnlocked)
    }

    func testZeroToSixty_ZeroProgressWithNoTimes() {
        let manager = freshManager()
        let drives = [makeDrive(startTime: Date(), best060Time: nil)]
        manager.updateProgress(with: drives)

        guard let sub6 = manager.achievements.first(where: { $0.id == "sub_6_club" }) else {
            return XCTFail("sub_6_club missing")
        }
        XCTAssertEqual(sub6.progress, 0.0, accuracy: 1e-9)
        XCTAssertFalse(sub6.isUnlocked)
    }

    // MARK: - smoothness local progress

    func testSmoothness_PartialProgressFromBrakeEventsPerMile() {
        let manager = freshManager()
        // 10 miles, 20 brake events -> 2.0/mile -> score 80 -> 80/90
        let drives = [makeDrive(startTime: Date(), brakeEvents: 20, distance: 16093.4)]
        manager.updateProgress(with: drives)

        guard let smooth = manager.achievements.first(where: { $0.id == "smooth_operator" }) else {
            return XCTFail("smooth_operator missing")
        }
        XCTAssertEqual(smooth.progress, 80.0 / 90.0, accuracy: 1e-9)
        XCTAssertFalse(smooth.isUnlocked)
    }

    // MARK: - streak same-day fix

    /// Drives on day1, day2, day2, day3. Same-day drives (day2 x2) must
    /// NOT reset the streak. Without the fix the day2->day2 step resets
    /// and the result is 2; with the fix it continues and the result is 3.
    func testStreak_SameDayDriveDoesNotResetConsecutiveDays() {
        let manager = freshManager()
        let cal = Calendar.current
        let d1 = cal.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000))
        let d2 = cal.date(byAdding: .day, value: 1, to: d1)!
        let d3 = cal.date(byAdding: .day, value: 2, to: d1)!

        let drives = [
            makeDrive(startTime: d1),
            makeDrive(startTime: d2.addingTimeInterval(3600)),
            makeDrive(startTime: d2.addingTimeInterval(7200)),  // same day as previous
            makeDrive(startTime: d3),
        ]
        manager.updateProgress(with: drives)

        guard let streak7 = manager.achievements.first(where: { $0.id == "streak_7" }) else {
            return XCTFail("streak_7 missing")
        }
        // 3 consecutive days out of 7 required.
        XCTAssertEqual(streak7.progress, 3.0 / 7.0, accuracy: 1e-6)
    }

    // MARK: - Helpers

    private func freshManager() -> AchievementManager {
        let manager = AchievementManager()
        manager.achievements = AchievementCatalog.createDefaultAchievements()
        return manager
    }

    private func makeDrive(
        startTime: Date,
        best060Time: Double? = nil,
        brakeEvents: Int = 0,
        distance: Double = 1000
    ) -> Drive {
        Drive(
            id: nil,
            userID: 1,
            startTime: startTime,
            endTime: startTime.addingTimeInterval(600),
            startLatitude: 37.0,
            startLongitude: -122.0,
            endLatitude: 37.001,
            endLongitude: -122.001,
            distance: distance,
            duration: 600,
            maxSpeed: 10,
            minSpeed: 0,
            avgSpeed: 5,
            stoppedTime: 0,
            leftTurns: 0,
            rightTurns: 0,
            brakeEvents: brakeEvents,
            laneChanges: 0,
            maxAcceleration: 1,
            maxDeceleration: 1,
            peakGForce: 0.1,
            topCornerSpeed: 5,
            best060Time: best060Time
        )
    }
}
