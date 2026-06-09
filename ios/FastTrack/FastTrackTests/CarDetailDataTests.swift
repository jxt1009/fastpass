import XCTest
@testable import FastTrack

// Phase 2 / Track E: tests for the pure `CarDetailData` derivation.
// The view itself is a thin wrapper over `CarDetailData` (constructed
// via `CarDetailData.derive(car:drives:carStats:achievements:now:)`),
// so we exercise the heuristic in isolation. The `now` parameter is
// injected so the confetti-eligible test can pin the clock.

final class CarDetailDataTests: XCTestCase {

    // MARK: - Driving style thresholds

    /// High brake events per mile + high top speed → sporty.
    func testDerive_DrivingStyle_Sporty() {
        let car = sampleCar()
        let stats = sampleStats(
            totalDrives: 10,
            totalDistanceMeters: meters(forMiles: 50),   // 50 mi
            totalBrakeEvents: 200,                       // 4/mi
            bestTopSpeedMps: mps(forMph: 110)            // 110 mph
        )

        let data = CarDetailData.derive(
            car: car,
            drives: [],
            carStats: stats,
            achievements: [],
            now: Date()
        )
        XCTAssertEqual(data.drivingStyle, .sporty)
    }

    /// Low brake events per mile + many drives → smooth.
    func testDerive_DrivingStyle_Smooth() {
        let car = sampleCar()
        let stats = sampleStats(
            totalDrives: 8,
            totalDistanceMeters: meters(forMiles: 80),   // 80 mi
            totalBrakeEvents: 16,                        // 0.2/mi
            bestTopSpeedMps: mps(forMph: 60)
        )

        let data = CarDetailData.derive(
            car: car,
            drives: [],
            carStats: stats,
            achievements: [],
            now: Date()
        )
        XCTAssertEqual(data.drivingStyle, .smooth)
    }

    /// Brake rate in the middle of the range → balanced.
    func testDerive_DrivingStyle_Balanced() {
        let car = sampleCar()
        let stats = sampleStats(
            totalDrives: 4,
            totalDistanceMeters: meters(forMiles: 20),   // 20 mi
            totalBrakeEvents: 20,                        // 1.0/mi
            bestTopSpeedMps: mps(forMph: 70)
        )

        let data = CarDetailData.derive(
            car: car,
            drives: [],
            carStats: stats,
            achievements: [],
            now: Date()
        )
        XCTAssertEqual(data.drivingStyle, .balanced)
    }

    /// No drives at all → unknown, regardless of the stats blob.
    func testDerive_DrivingStyle_Unknown() {
        let car = sampleCar()
        let data = CarDetailData.derive(
            car: car,
            drives: [],
            carStats: nil,
            achievements: [],
            now: Date()
        )
        XCTAssertEqual(data.drivingStyle, .unknown)
    }

    func testDrivingStyle_GuideStyles_OrderAndCoverage() {
        XCTAssertEqual(DrivingStyle.guideStyles, [.smooth, .balanced, .sporty, .unknown])
    }

    func testDrivingStyle_DetailedExplanation_IsNonEmpty() {
        for style in DrivingStyle.guideStyles {
            XCTAssertFalse(style.detailedExplanation.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        XCTAssertTrue(DrivingStyle.smooth.detailedExplanation.localizedCaseInsensitiveContains("measured"))
    }

    // MARK: - Sparkline

    /// Drives supplied out of order come back ordered by `startTime`
    /// ascending. The sparkline must read left-to-right chronologically.
    func testDerive_SparklineOrdersByStartTimeAscending() {
        let car = sampleCar()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let drives = [
            sampleDrive(carId: car.id, startTime: now.addingTimeInterval(200), maxSpeed: 30),
            sampleDrive(carId: car.id, startTime: now, maxSpeed: 10),
            sampleDrive(carId: car.id, startTime: now.addingTimeInterval(100), maxSpeed: 20),
        ]

        let data = CarDetailData.derive(
            car: car, drives: drives, carStats: nil, achievements: [], now: now
        )
        XCTAssertEqual(data.sparklinePoints, [10, 20, 30])
    }

    /// 50 drives should be capped to the 30 most recent. The oldest
    /// 20 fall off the left edge.
    func testDerive_SparklineLimitsTo30MostRecent() {
        let car = sampleCar()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let drives = (0..<50).map { i in
            sampleDrive(
                carId: car.id,
                startTime: now.addingTimeInterval(TimeInterval(i * 60)),
                maxSpeed: Double(i)  // strictly increasing so order is unambiguous
            )
        }

        let data = CarDetailData.derive(
            car: car, drives: drives, carStats: nil, achievements: [], now: now
        )
        XCTAssertEqual(data.sparklinePoints.count, 30)
        // The last 30 of an increasing series start at index 20
        XCTAssertEqual(data.sparklinePoints.first, 20)
        XCTAssertEqual(data.sparklinePoints.last, 49)
    }

    /// When the max lives in the middle of the array, the PB index
    /// points at it. The view uses this to render the red marker.
    func testDerive_PBSparklineIndexPointsAtMax() {
        let car = sampleCar()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let drives = [
            sampleDrive(carId: car.id, startTime: now,                       maxSpeed: 10),
            sampleDrive(carId: car.id, startTime: now.addingTimeInterval(60), maxSpeed: 25),
            sampleDrive(carId: car.id, startTime: now.addingTimeInterval(120), maxSpeed: 18),
            sampleDrive(carId: car.id, startTime: now.addingTimeInterval(180), maxSpeed: 22),
        ]

        let data = CarDetailData.derive(
            car: car, drives: drives, carStats: nil, achievements: [], now: now
        )
        XCTAssertEqual(data.pbSparklineIndex, 1)
    }

    // MARK: - Achievements filter

    /// Only achievements whose source drive is tagged with this car's
    /// id end up in the per-car PB list. The other two are filtered
    /// out (one has a source drive that belongs to a different car, one
    /// has no source drive at all).
    func testDerive_AchievementPBs_FiltersToThisCar() {
        let car = sampleCar()
        let otherCar = UserCar(
            id: "other",
            make: "Mazda", model: "MX-5"
        )
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let myDrive = sampleDrive(
            id: 1,
            carId: car.id,
            startTime: now,
            maxSpeed: 30
        )
        let otherDrive = sampleDrive(
            id: 2,
            carId: otherCar.id,
            startTime: now,
            maxSpeed: 20
        )
        let achievements = [
            unlockedAchievement(id: "mine",  sourceDriveId: myDrive.id),
            unlockedAchievement(id: "theirs", sourceDriveId: otherDrive.id),
            unlockedAchievement(id: "noSource", sourceDriveId: nil),
        ]

        let data = CarDetailData.derive(
            car: car,
            drives: [myDrive, otherDrive],
            carStats: nil,
            achievements: achievements,
            now: now
        )
        XCTAssertEqual(data.achievementPBs.map(\.id), ["mine"])
    }

    // MARK: - Confetti eligibility

    /// An achievement unlocked 3 days ago is still "new" — within the
    /// 7-day window.
    func testDerive_ConfettiEligible_TrueWhenNewPB() {
        let car = sampleCar()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let drive = sampleDrive(
            carId: car.id, startTime: now, maxSpeed: 30
        )
        let achievement = unlockedAchievement(
            id: "fresh",
            sourceDriveId: drive.id,
            unlockedDate: now.addingTimeInterval(-3 * 24 * 3600)
        )

        let data = CarDetailData.derive(
            car: car,
            drives: [drive],
            carStats: nil,
            achievements: [achievement],
            now: now
        )
        XCTAssertTrue(data.confettiEligible)
    }

    /// An achievement unlocked 30 days ago is outside the window.
    func testDerive_ConfettiEligible_FalseWhenOldPB() {
        let car = sampleCar()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let drive = sampleDrive(
            carId: car.id, startTime: now, maxSpeed: 30
        )
        let achievement = unlockedAchievement(
            id: "stale",
            sourceDriveId: drive.id,
            unlockedDate: now.addingTimeInterval(-30 * 24 * 3600)
        )

        let data = CarDetailData.derive(
            car: car,
            drives: [drive],
            carStats: nil,
            achievements: [achievement],
            now: now
        )
        XCTAssertFalse(data.confettiEligible)
    }

    /// No achievements at all → no confetti. Trivially false.
    func testDerive_ConfettiEligible_FalseWhenNoPB() {
        let car = sampleCar()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let data = CarDetailData.derive(
            car: car,
            drives: [],
            carStats: nil,
            achievements: [],
            now: now
        )
        XCTAssertFalse(data.confettiEligible)
    }

    /// A future-dated `unlockedDate` (e.g. device clock drifted back)
    /// must NOT trigger the confetti — a negative interval would
    /// otherwise pass the `<= window` check.
    func testDerive_ConfettiEligible_FalseWhenFutureUnlockedDate() {
        let car = sampleCar()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let drive = sampleDrive(
            carId: car.id, startTime: now, maxSpeed: 30
        )
        let achievement = unlockedAchievement(
            id: "future",
            sourceDriveId: drive.id,
            unlockedDate: now.addingTimeInterval(3600)   // 1h in the future
        )

        let data = CarDetailData.derive(
            car: car,
            drives: [drive],
            carStats: nil,
            achievements: [achievement],
            now: now
        )
        XCTAssertFalse(data.confettiEligible)
    }

    /// The trigger token is nil when no recent PB unlocks are eligible.
    func testDerive_ConfettiTriggerToken_NilWithoutRecentPBs() {
        let car = sampleCar()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let drive = sampleDrive(carId: car.id, startTime: now, maxSpeed: 30)
        let stale = unlockedAchievement(
            id: "stale",
            sourceDriveId: drive.id,
            unlockedDate: now.addingTimeInterval(-30 * 24 * 3600)
        )

        let data = CarDetailData.derive(
            car: car,
            drives: [drive],
            carStats: nil,
            achievements: [stale],
            now: now
        )
        XCTAssertNil(data.confettiTriggerToken)
        XCTAssertEqual(data.recentPBCount, 0)
    }

    /// Token is deterministic for the same eligible set and changes when
    /// a newly eligible unlock is added.
    func testDerive_ConfettiTriggerToken_StableThenChangesForNewUnlock() {
        let car = sampleCar()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let drive = sampleDrive(carId: car.id, startTime: now, maxSpeed: 30)
        let freshA = unlockedAchievement(
            id: "fresh-a",
            sourceDriveId: drive.id,
            unlockedDate: now.addingTimeInterval(-2 * 24 * 3600)
        )
        let freshB = unlockedAchievement(
            id: "fresh-b",
            sourceDriveId: drive.id,
            unlockedDate: now.addingTimeInterval(-1 * 24 * 3600)
        )

        let first = CarDetailData.derive(
            car: car,
            drives: [drive],
            carStats: nil,
            achievements: [freshA, freshB],
            now: now
        )
        let reordered = CarDetailData.derive(
            car: car,
            drives: [drive],
            carStats: nil,
            achievements: [freshB, freshA],
            now: now
        )
        XCTAssertEqual(first.confettiTriggerToken, reordered.confettiTriggerToken)
        XCTAssertEqual(first.recentPBCount, 2)

        let freshC = unlockedAchievement(
            id: "fresh-c",
            sourceDriveId: drive.id,
            unlockedDate: now.addingTimeInterval(-3600)
        )
        let withNewUnlock = CarDetailData.derive(
            car: car,
            drives: [drive],
            carStats: nil,
            achievements: [freshA, freshB, freshC],
            now: now
        )
        XCTAssertNotEqual(first.confettiTriggerToken, withNewUnlock.confettiTriggerToken)
        XCTAssertEqual(withNewUnlock.recentPBCount, 3)
    }

    /// 0-60 fallback must filter out non-positive `best060Time` values
    /// from the local drives — a sentinel `0` in a legacy or aborted
    /// drive should not become the all-time minimum.
    func testDerive_ResolveZeroSixty_FiltersOutNonPositive() {
        let car = sampleCar()
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let drives = [
            sampleDrive(
                id: 1, carId: car.id, startTime: now, maxSpeed: 30, best060Time: 0
            ),
            sampleDrive(
                id: 2, carId: car.id, startTime: now.addingTimeInterval(60),
                maxSpeed: 28, best060Time: 4.5
            ),
            sampleDrive(
                id: 3, carId: car.id, startTime: now.addingTimeInterval(120),
                maxSpeed: 26, best060Time: -1   // negative sentinel
            ),
        ]

        let data = CarDetailData.derive(
            car: car, drives: drives, carStats: nil, achievements: [], now: now
        )
        XCTAssertEqual(data.bestZeroToSixty, 4.5)
    }

    // MARK: - Helpers

    private func sampleCar() -> UserCar {
        UserCar(id: "test-car", make: "Honda", model: "Civic")
    }

    private func sampleStats(
        totalDrives: Int,
        totalDistanceMeters: Double,
        totalBrakeEvents: Int,
        bestTopSpeedMps: Double
    ) -> CarStats {
        var s = CarStats(carId: "test-car")
        s.totalDrives = totalDrives
        s.totalDistance = totalDistanceMeters
        s.totalBrakeEvents = totalBrakeEvents
        s.bestTopSpeed = bestTopSpeedMps
        return s
    }

    private func sampleDrive(
        id: Int = 1,
        carId: String,
        startTime: Date,
        maxSpeed: Double,
        best060Time: Double? = nil
    ) -> Drive {
        Drive(
            id: id,
            userID: 1,
            startTime: startTime,
            endTime: startTime.addingTimeInterval(600),
            startLatitude: 37.0,
            startLongitude: -122.0,
            endLatitude: 37.001,
            endLongitude: -122.001,
            distance: 1000,
            duration: 600,
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

    private func unlockedAchievement(
        id: String,
        sourceDriveId: Int?,
        unlockedDate: Date? = nil
    ) -> Achievement {
        Achievement(
            id: id,
            title: id,
            description: "",
            category: .milestone,
            icon: "circle",
            requirement: AchievementRequirement(type: .driveCount, value: 1, condition: nil),
            isUnlocked: true,
            unlockedDate: unlockedDate ?? Date(timeIntervalSince1970: 1_700_000_000),
            progress: 1.0,
            sourceDriveId: sourceDriveId
        )
    }

    /// meters(forMiles:) — converts a miles value to meters so the
    /// `CarStats` totalDistance stays in the same units the rest of
    /// the app uses.
    private func meters(forMiles miles: Double) -> Double {
        miles / 0.000621371
    }

    /// mps(forMph:) — converts a mph value to m/s.
    private func mps(forMph mph: Double) -> Double {
        mph / 2.23694
    }
}
