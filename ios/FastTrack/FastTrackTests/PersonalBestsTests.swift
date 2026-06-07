import XCTest
@testable import FastTrack

/// Tests for the personal-best (PB) computed properties on `DriveManager`.
///
/// The PB ids are the source of truth for the "trophy" treatment in
/// `DriveHistoryView`. They prefer the server's authoritative
/// `sourceDriveId` on a relevant achievement and fall back to a local
/// scan with a deterministic tie-break.
final class PersonalBestsTests: XCTestCase {

    // MARK: - Helpers

    /// Builds a drive with the given id, top speed (m/s), and start time.
    /// Other fields are set to safe defaults so the computed property
    /// under test only depends on what this helper varies.
    private func makeDrive(id: Int, maxSpeed: Double, startTime: Date) -> Drive {
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
            carId: nil,
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
            best060Time: nil
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
        let m = DriveManager()
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
}
