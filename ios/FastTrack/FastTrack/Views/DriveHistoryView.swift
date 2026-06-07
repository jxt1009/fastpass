import SwiftUI

struct DriveHistoryView: View {
    @EnvironmentObject var driveManager: DriveManager

    /// Yellow wins over red: a 0-60 PB is rarer, so when both PBs are
    /// held by the same drive, the yellow tint takes precedence.
    private func rowTint(isPB060: Bool, isPBTopSpeed: Bool) -> Color {
        if isPB060        { return Color.yellow.opacity(0.15) }
        if isPBTopSpeed   { return Color.red.opacity(0.10) }
        return Color.ftSurfaceBg
    }

    var body: some View {
        NavigationStack {
            Group {
                if driveManager.isLoadingDrives {
                    List {
                        ForEach(0..<6, id: \.self) { _ in
                            DriveRowSkeleton()
                                .listRowBackground(Color.ftSurfaceBg)
                        }
                    }
                } else if driveManager.drives.isEmpty {
                    ContentUnavailableView(
                        "No Drives Yet",
                        systemImage: "car.fill",
                        description: Text("Start a drive to see your history here.")
                    )
                } else {
                    List {
                        ForEach(driveManager.drives) { drive in
                            let isPB060 = drive.id == driveManager.pb060DriveId
                            let isPBTopSpeed = drive.id == driveManager.pbTopSpeedDriveId
                            NavigationLink(destination: DriveDetailView(drive: drive)) {
                                DriveRowView(
                                    drive: drive,
                                    isPersonalBest060: isPB060,
                                    isPersonalBestTopSpeed: isPBTopSpeed
                                )
                            }
                            .listRowBackground(rowTint(isPB060: isPB060, isPBTopSpeed: isPBTopSpeed))
                        }
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                }
            }
            .navigationTitle("Drive History")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { driveManager.fetchDrives() }
        }
    }
}

struct DriveRowSkeleton: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SkeletonBlock(width: 120, height: 16)
                Spacer()
                SkeletonBlock(width: 80, height: 14)
            }
            HStack {
                SkeletonBlock(width: 70, height: 12)
                Spacer()
                SkeletonBlock(width: 70, height: 12)
                Spacer()
                SkeletonBlock(width: 50, height: 12)
            }
        }
        .padding(.vertical, 4)
    }
}

struct DriveRowView: View {
    let drive: Drive
    var isPersonalBest060: Bool = false
    var isPersonalBestTopSpeed: Bool = false
    @EnvironmentObject var settings: AppSettings

    /// A stable key for the visible PB pills; when it changes (e.g. the
    /// PB id flips after a drives refresh), the pills animate in/out via
    /// the parent's spring animation.
    private var pbAnimationKey: String {
        "\(drive.id ?? 0)-\(isPersonalBest060)-\(isPersonalBestTopSpeed)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Text(drive.startTime, style: .date)
                    .font(.headline)
                if isPersonalBest060, drive.best060Time != nil {
                    pbPill(text: "PB 0-60", icon: "trophy.fill", bg: Color.yellow, fg: Color.black)
                        .transition(.scale.combined(with: .opacity))
                }
                if isPersonalBestTopSpeed {
                    pbPill(text: "PB Top Speed", icon: "flame.fill", bg: Color.red, fg: Color.white)
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
                if !drive.carDisplayString.isEmpty && drive.carDisplayString != "Unknown Car" {
                    Text(drive.carDisplayString)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            .animation(.spring(response: 0.4, dampingFraction: 0.7), value: pbAnimationKey)
            HStack {
                Label(settings.speedDisplay(drive.maxSpeed), systemImage: "speedometer")
                Spacer()
                Label(settings.distanceDisplay(drive.distance, decimals: 2), systemImage: "map")
                Spacer()
                Label(drive.durationString, systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private func pbPill(text: String, icon: String, bg: Color, fg: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(bg)
        .foregroundColor(fg)
        .clipShape(Capsule())
    }
}

#Preview {
    DriveHistoryView()
        .environmentObject(DriveManager.preview())
        .environmentObject(AppSettings.shared)
}
