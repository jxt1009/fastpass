import SwiftUI

// MARK: - CarDetailDrivesList

struct CarDetailDrivesList: View {
    let data: CarDetailData?
    let driveManager: DriveManager
    let settings: AppSettings
    let car: UserCar?
    let onDeleteDrive: (Drive) -> Void
    @EnvironmentObject var authManager: AuthManager

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            perCarAchievementsSection
            recentDrivesSection
        }
    }

    // MARK: - Achievements

    @ViewBuilder
    private var perCarAchievementsSection: some View {
        if let carAchievements = data?.achievementPBs, !carAchievements.isEmpty {
            VStack(alignment: .leading, spacing: Spacing.sm) {
                HStack {
                    Text("Achievements")
                        .font(.headline)
                    Spacer()
                    NavigationLink("See all") {
                        AchievementsView()
                    }
                    .font(.subheadline)
                    .foregroundStyle(Color.ftBlue)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Spacing.sm) {
                        ForEach(carAchievements) { achievement in
                            AchievementChip(achievement: achievement)
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    // MARK: - Recent Drives

    @ViewBuilder
    private var recentDrivesSection: some View {
        let carRecentDrives = data?.recentDrives ?? []

        let topSpeedPBDriveId: Int? = {
            guard let carId = car?.id,
                  let drive = driveManager.drives.filter({ $0.carId == carId }).max(by: { $0.maxSpeed < $1.maxSpeed }),
                  drive.maxSpeed == data?.bestTopSpeed else { return nil }
            return drive.id
        }()

        let zeroSixtyPBDriveId: Int? = {
            guard let carId = car?.id,
                  let time = data?.bestZeroToSixty,
                  let drive = driveManager.drives.first(where: { $0.carId == carId && $0.best060Time == time }) else { return nil }
            return drive.id
        }()

        if !carRecentDrives.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Recent Drives")

                ForEach(carRecentDrives) { drive in
                    NavigationLink {
                        DriveDetailView(drive: drive)
                    } label: {
                        GarageDriveRow(
                            drive: drive,
                            badge: driveBadge(
                                for: drive,
                                topSpeedPBDriveId: topSpeedPBDriveId,
                                zeroSixtyPBDriveId: zeroSixtyPBDriveId
                            )
                        )
                    }
                    .buttonStyle(.plain)
                    .swipeActions(edge: .trailing) {
                        if drive.userID == authManager.getUser()?.id {
                            Button(role: .destructive) {
                                onDeleteDrive(drive)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                }
            }
        }
    }

    private func driveBadge(for drive: Drive, topSpeedPBDriveId: Int?, zeroSixtyPBDriveId: Int?) -> BadgePill? {
        if drive.id == zeroSixtyPBDriveId {
            return BadgePill("PB 0-60", icon: "trophy.fill", style: .pb060)
        }
        if drive.id == topSpeedPBDriveId {
            return BadgePill("PB Speed", icon: "flame.fill", style: .pbTopSpeed)
        }
        return nil
    }
}
