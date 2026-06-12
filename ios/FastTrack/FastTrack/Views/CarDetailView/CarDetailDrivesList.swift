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
        if let pbs = data?.achievementPBs, !pbs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    SectionHeader(title: "Achievements")
                    Spacer()
                    if let indicator = recentPBIndicatorText {
                        HStack(spacing: 4) {
                            Circle()
                                .fill(Color.ftAmber)
                                .frame(width: 6, height: 6)
                            Text(indicator)
                                .font(.caption2.weight(.semibold))
                                .foregroundColor(.ftAmber)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.ftAmber.opacity(0.12))
                        )
                    }
                }
                ForEach(pbs) { achievement in
                    NavigationLink {
                        destination(for: achievement)
                    } label: {
                        achievementRow(achievement)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for achievement: Achievement) -> some View {
        switch RecentAchievementsStripLogic.resolveSourceDrive(
            for: achievement,
            in: driveManager.drives
        ) {
        case .local(let drive):
            DriveDetailView(drive: drive)
        case .remote(let driveId):
            RemoteDriveDetailLoader(driveId: driveId)
        case .none:
            AchievementsView()
        }
    }

    private func achievementRow(_ achievement: Achievement) -> some View {
        InstrumentCard {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: achievement.badgeIcon)
                    .font(.title3)
                    .foregroundColor(achievement.badgeColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(achievement.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(achievement.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    private var recentPBIndicatorText: String? {
        let count = data?.recentPBCount ?? 0
        guard count > 0 else { return nil }
        return count == 1 ? "Recently unlocked" : "\(count) recently unlocked"
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
