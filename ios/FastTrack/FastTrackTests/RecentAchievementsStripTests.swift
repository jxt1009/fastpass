import XCTest
@testable import FastTrack

// Tests for the `RecentAchievementsStrip` (issue #64 / Phase 1 Track C).
// The view itself is hard to inspect without a SwiftUI snapshot harness
// (the project does not currently use ViewInspector), so we exercise the
// pure logic helpers in `RecentAchievementsStripLogic` and let the view
// be a thin wrapper. The structural / line-order test lives in
// `ProfileRedesignTests.testProfileView_AchievementsStripAboveGarage`.
final class RecentAchievementsStripTests: XCTestCase {

    // MARK: - Ordering

    /// With six unlocked achievements at known `unlockedDate`s, the strip
    /// must show the five most-recent in newest-first order.
    func testRecentAchievementsStrip_RendersLatestUnlocksFirst() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let achievements: [Achievement] = (0..<6).map { i in
            Achievement(
                id: "a\(i)",
                title: "A\(i)",
                description: "",
                category: .milestone,
                icon: "circle",
                requirement: AchievementRequirement(type: .driveCount, value: 1, condition: nil),
                isUnlocked: true,
                unlockedDate: now.addingTimeInterval(TimeInterval(i * 60)),
                progress: 1.0,
                sourceDriveId: nil
            )
        }

        let recent = RecentAchievementsStripLogic.recentUnlocks(from: achievements, maxCount: 5)
        XCTAssertEqual(recent.map(\.id), ["a5", "a4", "a3", "a2", "a1"])
    }

    /// `maxCount` larger than the unlocked set returns the full unlocked
    /// list, not padded with locked entries.
    func testRecentAchievementsStrip_MaxCountExceedsUnlocked() {
        let achievements = [
            unlockedAchievement(id: "a1"),
            unlockedAchievement(id: "a2"),
            lockedAchievement(id: "locked-1"),
        ]
        let recent = RecentAchievementsStripLogic.recentUnlocks(from: achievements, maxCount: 5)
        XCTAssertEqual(recent.map(\.id), ["a1", "a2"])
    }

    /// No unlocked achievements → empty list. (The view renders the
    /// empty state from this signal.)
    func testRecentAchievementsStrip_EmptyWhenNothingUnlocked() {
        let achievements = [lockedAchievement(id: "locked-1"), lockedAchievement(id: "locked-2")]
        XCTAssertTrue(RecentAchievementsStripLogic.recentUnlocks(from: achievements, maxCount: 5).isEmpty)
    }

    /// `unlockedDate == nil` sorts to the end (and ties are broken by id
    /// ascending) so the deterministic order doesn't change between
    /// runs.
    func testRecentAchievementsStrip_NilDateSortsLast() {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let achievements: [Achievement] = [
            Achievement(
                id: "dated",
                title: "Dated",
                description: "",
                category: .milestone,
                icon: "circle",
                requirement: AchievementRequirement(type: .driveCount, value: 1, condition: nil),
                isUnlocked: true,
                unlockedDate: now,
                progress: 1.0,
                sourceDriveId: nil
            ),
            Achievement(
                id: "nil-1",
                title: "Nil 1",
                description: "",
                category: .milestone,
                icon: "circle",
                requirement: AchievementRequirement(type: .driveCount, value: 1, condition: nil),
                isUnlocked: true,
                unlockedDate: nil,
                progress: 1.0,
                sourceDriveId: nil
            ),
            Achievement(
                id: "nil-2",
                title: "Nil 2",
                description: "",
                category: .milestone,
                icon: "circle",
                requirement: AchievementRequirement(type: .driveCount, value: 1, condition: nil),
                isUnlocked: true,
                unlockedDate: nil,
                progress: 1.0,
                sourceDriveId: nil
            ),
        ]
        let recent = RecentAchievementsStripLogic.recentUnlocks(from: achievements, maxCount: 5)
        XCTAssertEqual(recent.map(\.id), ["dated", "nil-1", "nil-2"])
    }

    // MARK: - Source-drive resolution

    /// If the source drive is in `driveManager.drives`, the strip's
    /// NavigationLink destination is `DriveDetailView(drive:)`.
    func testRecentAchievementsStrip_LinksToSourceDrive() {
        let drive = makeDrive(id: 42)
        let achievement = unlockedAchievement(id: "a1", sourceDriveId: 42)

        let resolution = RecentAchievementsStripLogic.resolveSourceDrive(
            for: achievement, in: [drive]
        )
        guard case let .local(resolved) = resolution else {
            return XCTFail("Expected .local, got \(resolution)")
        }
        XCTAssertEqual(resolved.id, drive.id)
    }

    /// If the source drive is NOT in `driveManager.drives`, the strip
    /// falls back to `RemoteDriveDetailLoader(driveId:)` so the user can
    /// still tap into a server-only drive.
    func testRecentAchievementsStrip_FallsBackToRemoteLoader() {
        let local = makeDrive(id: 99)
        let achievement = unlockedAchievement(id: "a1", sourceDriveId: 42)

        let resolution = RecentAchievementsStripLogic.resolveSourceDrive(
            for: achievement, in: [local]
        )
        guard case let .remote(driveId) = resolution else {
            return XCTFail("Expected .remote, got \(resolution)")
        }
        XCTAssertEqual(driveId, 42)
    }

    /// An achievement with no `sourceDriveId` resolves to `.none`. The
    /// view falls back to `AchievementsView` in that case.
    func testRecentAchievementsStrip_NoSourceDriveResolvesToNone() {
        let achievement = unlockedAchievement(id: "a1", sourceDriveId: nil)
        XCTAssertEqual(
            RecentAchievementsStripLogic.resolveSourceDrive(for: achievement, in: []),
            .none
        )
    }

    // MARK: - Helpers

    private func unlockedAchievement(id: String, sourceDriveId: Int? = nil) -> Achievement {
        Achievement(
            id: id,
            title: id,
            description: "",
            category: .milestone,
            icon: "circle",
            requirement: AchievementRequirement(type: .driveCount, value: 1, condition: nil),
            isUnlocked: true,
            unlockedDate: Date(timeIntervalSince1970: 1_700_000_000),
            progress: 1.0,
            sourceDriveId: sourceDriveId
        )
    }

    private func lockedAchievement(id: String) -> Achievement {
        Achievement(
            id: id,
            title: id,
            description: "",
            category: .milestone,
            icon: "circle",
            requirement: AchievementRequirement(type: .driveCount, value: 1, condition: nil),
            isUnlocked: false,
            unlockedDate: nil,
            progress: 0.0,
            sourceDriveId: nil
        )
    }

    private func makeDrive(id: Int) -> Drive {
        Drive(
            id: id,
            userID: 1,
            startTime: Date(timeIntervalSince1970: 1_700_000_000),
            endTime: Date(timeIntervalSince1970: 1_700_000_010),
            startLatitude: 37.0,
            startLongitude: -122.0,
            endLatitude: 37.001,
            endLongitude: -122.0,
            distance: 100,
            duration: 10,
            maxSpeed: 30,
            minSpeed: 0,
            avgSpeed: 10,
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
}
