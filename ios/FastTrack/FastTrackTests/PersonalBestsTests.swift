import XCTest
@testable import FastTrack

/// Tests for the personal-best (PB) computed properties on `DriveManager`.
///
/// The PB ids are the source of truth for the "trophy" treatment in
/// `DriveHistoryView`. They prefer the server's authoritative
/// `sourceDriveId` on a relevant achievement and fall back to a local
/// scan with a deterministic tie-break.
@MainActor
final class PersonalBestsTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a drive with the given id, top speed (m/s), and start time.
    /// Other fields are set to safe defaults so the computed property
    /// under test only depends on what this helper varies.
    private func makeDrive(id: Int, maxSpeed: Double, startTime: Date) -> Drive {
        makeDrive(id: id, carId: nil, maxSpeed: maxSpeed, best060Time: nil, startTime: startTime)
    }

    /// Builds a drive with an explicit car id, top speed, optional 0-60
    /// time, and start time.
    private func makeDrive(
        id: Int,
        carId: String?,
        maxSpeed: Double,
        best060Time: Double? = nil,
        startTime: Date
    ) -> Drive {
        Drive(
            id: id,
            userID: 1,
            startTime: startTime,
            endTime: startTime.addingTimeInterval(60),
            startLatitude: 37.0,
            startLongitude: -122.0,
            endLatitude: 37.001,
            endLongitude: -122.0,
            distance: 100,
            duration: 60,
            maxSpeed: maxSpeed,
            minSpeed: 0,
            avgSpeed: maxSpeed / 2,
            routeData: nil,
            carId: carId,
            carMake: nil,
            carModel: nil,
            carYear: nil,
            carTrim: nil,
            carNickname: nil,
            stoppedTime: 0,
            leftTurns: 0,
            rightTurns: 0,
            brakeEvents: 0,
            laneChanges: 0,
            maxAcceleration: 0,
            maxDeceleration: 0,
            peakGForce: 0,
            topCornerSpeed: 0,
            best060Time: best060Time
        )
    }

    private func unlock(_ id: String, sourceDriveId: Int?, sourceValue: Double = 0) -> UserAchievement {
        UserAchievement(
            achievementId: id,
            unlockedAt: Date(),
            sourceDriveId: sourceDriveId,
            sourceKind: "max_speed",
            sourceValue: sourceValue
        )
    }

    private func makeManager(drives: [Drive] = [], unlocks: [UserAchievement] = []) -> DriveManager {
        let realAPI = APIService()
        let authMgr = AuthManager(apiService: realAPI)
        realAPI.authManager = authMgr
        let m = DriveManager(
            authManager: authMgr,
            profileManager: ProfileManager(apiService: realAPI),
            settings: AppSettings(apiService: realAPI),
            apiService: realAPI,
            carStatsManager: CarStatsManager(apiService: realAPI),
            achievementManager: AchievementManager()
        )
        m.drives = drives
        m.userAchievements = unlocks
        return m
    }

    // MARK: - Top speed PB

    /// The server's `speed_150` source drive should win over the
    /// `speed_100` (Century Club) source drive. The two are independent
    /// achievements that may have been unlocked by different drives; we
    /// trust the 150 mph one as the more authoritative top-speed marker.
    func testPBTopSpeedDriveId_PrefersSpeed150SourceDrive() {
        let older   = makeDrive(id: 1, maxSpeed: 50,  startTime: Date(timeIntervalSince1970: 1_700_000_000))
        let faster  = makeDrive(id: 2, maxSpeed: 80,  startTime: Date(timeIntervalSince1970: 1_700_000_100))
        // speed_150 was unlocked by the *second* drive; speed_100 (Century
        // Club) was unlocked by the *first*. The 150 mph source drive wins.
        let unlocks = [
            unlock("speed_150", sourceDriveId: 2),
            unlock("speed_100", sourceDriveId: 1),
        ]
        let m = makeManager(drives: [older, faster], unlocks: unlocks)
        XCTAssertEqual(m.pbTopSpeedDriveId, 2)
    }

    /// With no server-side unlock to anchor the PB, the property must fall
    /// back to the most recent drive with the all-time maximum top speed.
    func testPBTopSpeedDriveId_FallsBackToLocalScan() {
        let a = makeDrive(id: 10, maxSpeed: 120, startTime: Date(timeIntervalSince1970: 1_700_000_000))
        let b = makeDrive(id: 11, maxSpeed: 145, startTime: Date(timeIntervalSince1970: 1_700_000_100))
        let c = makeDrive(id: 12, maxSpeed: 130, startTime: Date(timeIntervalSince1970: 1_700_000_200))
        let m = makeManager(drives: [a, b, c], unlocks: [])
        XCTAssertEqual(m.pbTopSpeedDriveId, 11)
    }

    /// Ties on `maxSpeed` must resolve to the most recent drive (lex
    /// tie-break on `startTime`), not the first one encountered.
    func testPBTopSpeedDriveId_TieBreakUsesMostRecent() {
        let older = makeDrive(id: 20, maxSpeed: 150, startTime: Date(timeIntervalSince1970: 1_700_000_000))
        let newer = makeDrive(id: 21, maxSpeed: 150, startTime: Date(timeIntervalSince1970: 1_700_000_300))
        let m = makeManager(drives: [older, newer], unlocks: [])
        XCTAssertEqual(m.pbTopSpeedDriveId, 21)
    }

    /// No drives and no unlocks → nil. Nothing to mark.
    func testPBTopSpeedDriveId_NoDrives() {
        let m = makeManager(drives: [], unlocks: [])
        XCTAssertNil(m.pbTopSpeedDriveId)
    }

    /// Three drives whose `maxSpeed` is all zero (incomplete / legacy
    /// imports) must not be crowned as a top-speed PB — the local-scan
    /// fallback should bail out the same way `pb060DriveId` ignores
    /// non-positive 0-60 times.
    func testPBTopSpeedDriveId_AllZeroMaxSpeedReturnsNil() {
        let a = makeDrive(id: 30, maxSpeed: 0, startTime: Date(timeIntervalSince1970: 1_700_000_000))
        let b = makeDrive(id: 31, maxSpeed: 0, startTime: Date(timeIntervalSince1970: 1_700_000_100))
        let c = makeDrive(id: 32, maxSpeed: 0, startTime: Date(timeIntervalSince1970: 1_700_000_200))
        let m = makeManager(drives: [a, b, c], unlocks: [])
        XCTAssertNil(m.pbTopSpeedDriveId)
    }

    /// Mixed zero and positive `maxSpeed` values: the local-scan
    /// fallback must surface the positive max (not treat the zeros as
    /// a tie at the all-time max).
    func testPBTopSpeedDriveId_MixedZeroAndPositive_ReturnsPositiveMax() {
        let zero1 = makeDrive(id: 40, maxSpeed: 0, startTime: Date(timeIntervalSince1970: 1_700_000_000))
        let zero2 = makeDrive(id: 41, maxSpeed: 0, startTime: Date(timeIntervalSince1970: 1_700_000_100))
        let fast  = makeDrive(id: 42, maxSpeed: 50, startTime: Date(timeIntervalSince1970: 1_700_000_200))
        let m = makeManager(drives: [zero1, zero2, fast], unlocks: [])
        XCTAssertEqual(m.pbTopSpeedDriveId, 42)
    }

    // MARK: - PersonalBests helper — true top speed

    /// `PersonalBests.trueTopSpeed` must return the drive with the
    /// maximum `maxSpeed` for the given car, ignoring drives tagged
    /// to other cars.
    func testTrueTopSpeedPB_usesMaxAcrossAllDrivesForCar() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let myCar = "car-A"
        let drives = [
            makeDrive(id: 1, carId: myCar,  maxSpeed: 30,  startTime: t0),
            makeDrive(id: 2, carId: myCar,  maxSpeed: 55,  startTime: t0.addingTimeInterval(60)),
            makeDrive(id: 3, carId: myCar,  maxSpeed: 40,  startTime: t0.addingTimeInterval(120)),
            // Drive belonging to a different car must be ignored.
            makeDrive(id: 4, carId: "car-B", maxSpeed: 99, startTime: t0.addingTimeInterval(180)),
        ]
        let (speed, drive) = PersonalBests.trueTopSpeed(carId: myCar, drives: drives)
        XCTAssertEqual(speed, 55, accuracy: 0.001)
        XCTAssertEqual(drive?.id, 2)
    }

    // MARK: - PersonalBests helper — true 0-60

    /// `PersonalBests.trueZeroToSixty` must return the drive with the
    /// minimum positive `best060Time` for the given car, ignoring
    /// drives for other cars and non-positive sentinel values.
    func testTrueZeroToSixtyPB_usesMinAcrossAllDrivesForCar() {
        let t0 = Date(timeIntervalSince1970: 1_700_000_000)
        let myCar = "car-A"
        let drives = [
            makeDrive(id: 1, carId: myCar,  maxSpeed: 30, best060Time: 5.8,  startTime: t0),
            makeDrive(id: 2, carId: myCar,  maxSpeed: 30, best060Time: 4.2,  startTime: t0.addingTimeInterval(60)),
            makeDrive(id: 3, carId: myCar,  maxSpeed: 30, best060Time: 0,    startTime: t0.addingTimeInterval(120)),  // sentinel
            makeDrive(id: 4, carId: myCar,  maxSpeed: 30, best060Time: nil,  startTime: t0.addingTimeInterval(180)),  // no attempt
            // Drive belonging to a different car with a faster time must be ignored.
            makeDrive(id: 5, carId: "car-B", maxSpeed: 30, best060Time: 2.9, startTime: t0.addingTimeInterval(240)),
        ]
        let (time, drive) = PersonalBests.trueZeroToSixty(carId: myCar, drives: drives)
        XCTAssertEqual(time, 4.2, accuracy: 0.001)
        XCTAssertEqual(drive?.id, 2)
    }

    // MARK: - CarStats performance fields round-trip non-optional Drive fields

    /// `CarStatsManager.updateStats(for:)` must read `Drive.maxAcceleration`,
    /// `maxDeceleration`, `peakGForce`, `brakeEvents`, `leftTurns`, and
    /// `rightTurns` as non-optional values. They are non-optional on `Drive`
    /// and always populated by the recording pipeline, so any `?? 0` on
    /// the read path in `CarStats.swift:88-94` is dead code. This test is a
    /// regression guard: it would fail if those fields ever reverted to
    /// optional (silently degrading to zero) or if the aggregator
    /// accidentally dropped one of the values.
    func testUpdateStats_accumulatesPerformanceFieldsFromNonOptionalDriveFields() {
        let carId = "car-p0-1"
        // Use a fresh manager so we don't read prior test state from the
        // shared singleton. We never call saveCarStats / upload because
        // the public surface used here only mutates in-memory state.
        let manager = CarStatsManager(apiService: APIService())
        let start = Date(timeIntervalSince1970: 1_700_000_000)
        let drive = Drive(
            id: 1,
            userID: 1,
            startTime: start,
            endTime: start.addingTimeInterval(60),
            startLatitude: 37.0,
            startLongitude: -122.0,
            endLatitude: 37.001,
            endLongitude: -122.0,
            distance: 100,
            duration: 60,
            maxSpeed: 10,
            minSpeed: 0,
            avgSpeed: 5,
            routeData: nil,
            carId: carId,
            carMake: nil,
            carModel: nil,
            carYear: nil,
            carTrim: nil,
            carNickname: nil,
            stoppedTime: 0,
            leftTurns: 4,
            rightTurns: 7,
            brakeEvents: 3,
            laneChanges: 0,
            maxAcceleration: 2.5,
            maxDeceleration: 3.5,
            peakGForce: 0.9,
            topCornerSpeed: 0,
            best060Time: nil
        )

        manager.updateStats(for: drive, suppressUpload: true)

        guard let stats = manager.getStats(for: carId) else {
            XCTFail("Expected stats for \(carId) after updateStats")
            return
        }
        XCTAssertEqual(stats.bestAcceleration, 2.5, accuracy: 0.0001)
        XCTAssertEqual(stats.bestDeceleration, 3.5, accuracy: 0.0001)
        XCTAssertEqual(stats.bestLateralG, 0.9, accuracy: 0.0001)
        XCTAssertEqual(stats.totalBrakeEvents, 3)
        XCTAssertEqual(stats.totalTurns, 11) // 4 left + 7 right
    }

    // MARK: - 0-60 label is not unit-dependent

    /// The "Best 0-60" label in ProfileView must be the fixed string
    /// "Best 0-60 mph time", not an interpolated unit string that would
    /// render incorrectly in metric mode ("Best 0-60 km/h time").
    func testZeroToSixtyLabel_isNotUnitDependent() throws {
        // Read the ProfileView source and assert the interpolated pattern is absent.
        let bundle = Bundle(for: PersonalBestsTests.self)
        // The test target includes the app sources; locate ProfileView.swift
        // via its known relative path from the module root.
        guard let srcURL = bundle.resourceURL?
            .deletingLastPathComponent()   // .build/Debug-iphonesimulator
            .deletingLastPathComponent()   // .build
            .deletingLastPathComponent()   // FastTrack.xcodeproj parent
            .appendingPathComponent("FastTrack/Views/ProfileView.swift"),
              let source = try? String(contentsOf: srcURL, encoding: .utf8) else {
            // If file resolution fails in CI (paths vary), skip gracefully.
            throw XCTSkip("Could not locate ProfileView.swift for source inspection")
        }
        // The interpolated unit pattern must be absent.
        XCTAssertFalse(
            source.contains("Best 0-60 \\(settings.speedUnit)"),
            "ProfileView still contains unit-interpolated 0-60 label"
        )
        // The correct fixed label must be present.
        XCTAssertTrue(
            source.contains("Best 0-60 mph time"),
            "ProfileView does not contain the fixed 'Best 0-60 mph time' label"
        )
    }
}
