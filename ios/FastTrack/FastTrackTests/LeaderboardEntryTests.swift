import XCTest
@testable import FastTrack

final class LeaderboardEntryTests: XCTestCase {

    // MARK: - New wire format

    /// The car-centric wire format from the post-PR-1 backend should decode
    /// every documented field onto the matching Swift property.
    func testLeaderboardEntry_DecodesNewWireFormat() throws {
        let json = """
        {
          "rank": 1,
          "user_id": 42,
          "username": "apexdriver",
          "country": "US",
          "avatar_url": "https://fast.toper.dev/uploads/avatars/42.jpg",
          "value": 31.2928,
          "car_id": "11111111-1111-1111-1111-111111111111",
          "car_key": "11111111-1111-1111-1111-111111111111",
          "car_year": 2024,
          "car_make": "BMW",
          "car_model": "M3",
          "car_trim": "Competition",
          "car_nickname": "Track Toy",
          "car_photo_url": "https://fast.toper.dev/uploads/garage_cars/42_car.jpg"
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(LeaderboardEntry.self, from: json)

        XCTAssertEqual(entry.rank, 1)
        XCTAssertEqual(entry.userId, 42)
        XCTAssertEqual(entry.username, "apexdriver")
        XCTAssertEqual(entry.country, "US")
        XCTAssertEqual(entry.avatarURL, "https://fast.toper.dev/uploads/avatars/42.jpg")
        XCTAssertEqual(entry.value, 31.2928, accuracy: 0.0001)
        XCTAssertEqual(entry.carId, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(entry.carKey, "11111111-1111-1111-1111-111111111111")
        XCTAssertEqual(entry.carYear, 2024)
        XCTAssertEqual(entry.carMake, "BMW")
        XCTAssertEqual(entry.carModel, "M3")
        XCTAssertEqual(entry.carTrim, "Competition")
        XCTAssertEqual(entry.carNickname, "Track Toy")
        XCTAssertEqual(entry.carPhotoUrl, "https://fast.toper.dev/uploads/garage_cars/42_car.jpg")
    }

    /// The composite id (userId + carKey) must be unique when the same user
    /// appears multiple times with different cars. Otherwise ForEach in
    /// SwiftUI will crash or merge rows.
    func testLeaderboardEntry_IdIsUniquePerCar() throws {
        let json = """
        [
          {
            "rank": 1, "user_id": 42, "username": "apex", "country": "US",
            "avatar_url": "", "value": 30.0,
            "car_id": "car-A", "car_key": "car-A",
            "car_make": "BMW", "car_model": "M3"
          },
          {
            "rank": 2, "user_id": 42, "username": "apex", "country": "US",
            "avatar_url": "", "value": 28.0,
            "car_id": "car-B", "car_key": "car-B",
            "car_make": "Tesla", "car_model": "Model 3"
          }
        ]
        """.data(using: .utf8)!

        let entries = try JSONDecoder().decode([LeaderboardEntry].self, from: json)
        XCTAssertEqual(entries.count, 2)
        XCTAssertNotEqual(entries[0].id, entries[1].id,
                          "composite id must differ for the same user with different cars")
    }

    // MARK: - CodingKeys are snake_case

    /// The on-wire keys must remain snake_case, matching the rest of the
    /// FastTrack JSON contract. If a future refactor renames a key to
    /// camelCase, the backend will silently lose data.
    func testLeaderboardEntry_WireKeysAreSnakeCase() throws {
        let entry = LeaderboardEntry(
            rank: 1,
            userId: 7,
            username: "u",
            country: "US",
            avatarURL: "",
            value: 10.0,
            carId: "car-1",
            carKey: "car-1",
            carMake: "BMW",
            carModel: "M3",
            carYear: 2024,
            carTrim: "Comp",
            carNickname: "T",
            carPhotoUrl: "https://example.com/p.jpg"
        )

        let data = try JSONEncoder().encode(entry)
        let json = String(data: data, encoding: .utf8) ?? ""
        let expectedKeys = [
            "\"user_id\"",
            "\"avatar_url\"",
            "\"car_id\"",
            "\"car_key\"",
            "\"car_make\"",
            "\"car_model\"",
            "\"car_year\"",
            "\"car_trim\"",
            "\"car_nickname\"",
            "\"car_photo_url\""
        ]
        for key in expectedKeys {
            XCTAssertTrue(json.contains(key),
                          "expected snake_case wire key \(key) in encoded JSON, got: \(json)")
        }
    }

    // MARK: - Missing optional car fields

    /// The additive contract: a payload that omits the new optional car
    /// fields (car_id, car_year, car_trim, car_nickname, car_photo_url) must
    /// still decode, with the missing fields populated as nil. The backend
    /// always populates car_key, so it stays non-optional.
    func testLeaderboardEntry_MissingOptionalCarFieldsDecodeToNil() throws {
        let json = """
        {
          "rank": 5,
          "user_id": 9,
          "username": "oldserver",
          "country": "DE",
          "avatar_url": "",
          "value": 25.0,
          "car_key": "fallback-key",
          "car_make": "Audi",
          "car_model": "RS5"
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(LeaderboardEntry.self, from: json)

        XCTAssertEqual(entry.carId, nil)
        XCTAssertEqual(entry.carYear, nil)
        XCTAssertEqual(entry.carTrim, nil)
        XCTAssertEqual(entry.carNickname, nil)
        XCTAssertEqual(entry.carPhotoUrl, nil)
        // car_key is non-optional and is always present in the wire
        XCTAssertEqual(entry.carKey, "fallback-key")
        XCTAssertEqual(entry.carMake, "Audi")
        XCTAssertEqual(entry.carModel, "RS5")
    }

    /// car_photo_url is the only field explicitly reserved for PR 3; PR 1
    /// always returns it as nil. The model must still decode that literal
    /// JSON null correctly (not crash, not substitute an empty string).
    func testLeaderboardEntry_ExplicitNullCarPhotoUrlDecodes() throws {
        let json = """
        {
          "rank": 1, "user_id": 1, "username": "u", "country": "US",
          "avatar_url": "", "value": 1.0,
          "car_id": "car-1", "car_key": "car-1",
          "car_make": "BMW", "car_model": "M3",
          "car_year": 2024, "car_trim": null, "car_nickname": null,
          "car_photo_url": null
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(LeaderboardEntry.self, from: json)
        XCTAssertNil(entry.carTrim)
        XCTAssertNil(entry.carNickname)
        XCTAssertNil(entry.carPhotoUrl)
    }

    // MARK: - Old wire format (no car_id, no car_photo_url)

    /// The new server may roll out the new car-centric fields in waves
    /// (car_id first, car_photo_url much later in PR 3). The additive
    /// contract is: when the server omits one of the optional new fields,
    /// the iOS model must still decode and the missing field must come
    /// through as nil. This simulates a payload missing car_id and
    /// car_photo_url (the two fields explicitly called out as nullable in
    /// the plan's locked decisions).
    ///
    /// `car_key` is non-optional on the server side — the SQL always
    /// synthesises it as `car_id | make|model` — so it stays non-optional
    /// here. A pre-PR-1 payload (which would also lack car_key) is a
    /// separate, unsupported config: the server is always ≥ PR 1 by the
    /// time the iOS PR 2 build ships.
    func testLeaderboardEntry_OldWireFormatStillDecodes() throws {
        let json = """
        {
          "rank": 3,
          "user_id": 11,
          "username": "legacy",
          "country": "UK",
          "avatar_url": "https://fast.toper.dev/uploads/avatars/11.jpg",
          "value": 22.5,
          "car_key": "honda|civic",
          "car_make": "Honda",
          "car_model": "Civic"
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder().decode(LeaderboardEntry.self, from: json)
        XCTAssertEqual(entry.rank, 3)
        XCTAssertEqual(entry.userId, 11)
        XCTAssertEqual(entry.username, "legacy")
        XCTAssertEqual(entry.carMake, "Honda")
        XCTAssertEqual(entry.carModel, "Civic")
        XCTAssertEqual(entry.carKey, "honda|civic")
        XCTAssertEqual(entry.value, 22.5, accuracy: 0.0001)

        // New optional fields default to nil when the server omits them
        XCTAssertNil(entry.carId)
        XCTAssertNil(entry.carYear)
        XCTAssertNil(entry.carTrim)
        XCTAssertNil(entry.carNickname)
        XCTAssertNil(entry.carPhotoUrl)
    }

    // MARK: - Enum string round-trip

    /// The new period enum values must serialize to the exact strings the
    /// backend accepts (last_24h, last_7_days, all_time) and decode back
    /// losslessly.
    func testLeaderboardPeriod_RoundTripsAllCases() throws {
        for period in LeaderboardPeriod.allCases {
            let encoded = try JSONEncoder().encode(period)
            let decoded = try JSONDecoder().decode(LeaderboardPeriod.self, from: encoded)
            XCTAssertEqual(decoded, period, "round-trip failed for \(period)")
        }
    }

    /// The legacy "week" period was dropped in PR 1 (server returns 400 for
    /// it). Verify the iOS enum no longer carries it.
    func testLeaderboardPeriod_DropsLegacyWeek() {
        XCTAssertFalse(LeaderboardPeriod.allCases.map { $0.rawValue }.contains("week"),
                       "iOS LeaderboardPeriod must no longer advertise 'week'; the server rejects it with 400")
        XCTAssertTrue(LeaderboardPeriod.allCases.map { $0.rawValue }.contains("last_24h"))
        XCTAssertTrue(LeaderboardPeriod.allCases.map { $0.rawValue }.contains("last_7_days"))
        XCTAssertTrue(LeaderboardPeriod.allCases.map { $0.rawValue }.contains("all_time"))
    }

    /// The category enum must round-trip every current case, and must NOT
    /// carry the dropped driveCount case (server returns 400 for it).
    func testLeaderboardCategory_RoundTripsAllCases() throws {
        for category in LeaderboardCategory.allCases {
            let encoded = try JSONEncoder().encode(category)
            let decoded = try JSONDecoder().decode(LeaderboardCategory.self, from: encoded)
            XCTAssertEqual(decoded, category, "round-trip failed for \(category)")
        }
    }

    /// driveCount is gone — the server 400s it, and the iOS picker should
    /// not advertise it.
    func testLeaderboardCategory_DropsDriveCount() {
        let rawValues = LeaderboardCategory.allCases.map { $0.rawValue }
        XCTAssertFalse(rawValues.contains("drive_count"),
                       "drive_count category was dropped in PR 1; iOS must not send it")
        XCTAssertTrue(rawValues.contains("top_speed"))
        XCTAssertTrue(rawValues.contains("best_060"))
        XCTAssertTrue(rawValues.contains("total_distance"))
    }

    /// The picker order matters: topSpeed, best060, totalDistance matches
    /// the public profile stat ordering and the plan's locked decisions.
    func testLeaderboardCategory_OrderMatchesPlan() {
        XCTAssertEqual(
            LeaderboardCategory.allCases.map { $0.rawValue },
            ["top_speed", "best_060", "total_distance"]
        )
    }

    // MARK: - Quick filter controls

    /// Scope chip is a one-tap toggle between Global and Following.
    func testLeaderboardScope_QuickToggleAlternatesBetweenTwoModes() {
        XCTAssertEqual(LeaderboardScope.global.quickToggle, .following)
        XCTAssertEqual(LeaderboardScope.following.quickToggle, .global)
    }

    /// Period chip cycles in the product-approved order.
    func testLeaderboardPeriod_QuickCycleFollows24h7dAllTimeOrder() {
        XCTAssertEqual(LeaderboardPeriod.last24Hours.nextQuickCycle, .last7Days)
        XCTAssertEqual(LeaderboardPeriod.last7Days.nextQuickCycle, .allTime)
        XCTAssertEqual(LeaderboardPeriod.allTime.nextQuickCycle, .last24Hours)
    }

    // MARK: - Current user position card helper

    func testLeaderboardEntry_FirstCurrentUserEntryFindsPosition() {
        let rows = [
            LeaderboardEntry(
                rank: 1, userId: 99, username: "one", country: "US", avatarURL: "",
                value: 10, carId: nil, carKey: "a", carMake: "BMW", carModel: "M3",
                carYear: 2024, carTrim: nil, carNickname: nil, carPhotoUrl: nil
            ),
            LeaderboardEntry(
                rank: 4, userId: 7, username: "me", country: "US", avatarURL: "",
                value: 9, carId: nil, carKey: "b", carMake: "Tesla", carModel: "Model 3",
                carYear: 2023, carTrim: nil, carNickname: "Daily", carPhotoUrl: nil
            )
        ]

        let myRow = LeaderboardEntry.firstCurrentUserEntry(in: rows, currentUserId: 7)
        XCTAssertEqual(myRow?.rank, 4)
        XCTAssertEqual(myRow?.username, "me")
    }

    func testLeaderboardEntry_FirstCurrentUserEntryReturnsNilWhenMissingOrUnknownUser() {
        let rows = [
            LeaderboardEntry(
                rank: 1, userId: 11, username: "other", country: "US", avatarURL: "",
                value: 10, carId: nil, carKey: "a", carMake: "BMW", carModel: "M3",
                carYear: 2024, carTrim: nil, carNickname: nil, carPhotoUrl: nil
            )
        ]

        XCTAssertNil(LeaderboardEntry.firstCurrentUserEntry(in: rows, currentUserId: 7))
        XCTAssertNil(LeaderboardEntry.firstCurrentUserEntry(in: rows, currentUserId: nil))
    }

    // MARK: - Display strings

    /// "2024 BMW M3" when year is set, "BMW M3" when nil.
    func testLeaderboardEntry_CarDisplayString_IncludesYearWhenPresent() {
        let withYear = LeaderboardEntry(
            rank: 1, userId: 1, username: "u", country: "US", avatarURL: "",
            value: 0, carId: nil, carKey: "k",
            carMake: "BMW", carModel: "M3", carYear: 2024,
            carTrim: nil, carNickname: nil, carPhotoUrl: nil
        )
        XCTAssertEqual(withYear.carDisplayString, "2024 BMW M3")

        let noYear = LeaderboardEntry(
            rank: 1, userId: 1, username: "u", country: "US", avatarURL: "",
            value: 0, carId: nil, carKey: "k",
            carMake: "BMW", carModel: "M3", carYear: nil,
            carTrim: nil, carNickname: nil, carPhotoUrl: nil
        )
        XCTAssertEqual(noYear.carDisplayString, "BMW M3")
    }

    /// Nickname appears in straight quotes when present, omitted when nil
    /// or blank.
    func testLeaderboardEntry_CarDisplayStringWithNickname() {
        let withNick = LeaderboardEntry(
            rank: 1, userId: 1, username: "u", country: "US", avatarURL: "",
            value: 0, carId: nil, carKey: "k",
            carMake: "BMW", carModel: "M3", carYear: 2024,
            carTrim: nil, carNickname: "Track Toy", carPhotoUrl: nil
        )
        XCTAssertEqual(withNick.carDisplayStringWithNickname, "2024 BMW M3 \"Track Toy\"")

        let blankNick = LeaderboardEntry(
            rank: 1, userId: 1, username: "u", country: "US", avatarURL: "",
            value: 0, carId: nil, carKey: "k",
            carMake: "BMW", carModel: "M3", carYear: 2024,
            carTrim: nil, carNickname: "   ", carPhotoUrl: nil
        )
        XCTAssertEqual(blankNick.carDisplayStringWithNickname, "2024 BMW M3")

        let noNick = LeaderboardEntry(
            rank: 1, userId: 1, username: "u", country: "US", avatarURL: "",
            value: 0, carId: nil, carKey: "k",
            carMake: "BMW", carModel: "M3", carYear: 2024,
            carTrim: nil, carNickname: nil, carPhotoUrl: nil
        )
        XCTAssertEqual(noNick.carDisplayStringWithNickname, "2024 BMW M3")
    }
}
