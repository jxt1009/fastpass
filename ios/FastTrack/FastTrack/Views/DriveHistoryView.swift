import SwiftUI

struct DriveHistoryView: View {
    @EnvironmentObject var driveManager: DriveManager

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
                            NavigationLink(destination: DriveDetailView(drive: drive)) {
                                DriveRowView(drive: drive, isPersonalBest060: drive.id == driveManager.pb060DriveId)
                            }
                            .listRowBackground(
                                drive.id == driveManager.pb060DriveId
                                    ? Color.yellow.opacity(0.15)
                                    : Color.ftSurfaceBg
                            )
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
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(drive.startTime, style: .date)
                    .font(.headline)
                if isPersonalBest060, drive.best060Time != nil {
                    HStack(spacing: 3) {
                        Image(systemName: "trophy.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("PB 0-60")
                            .font(.caption2.weight(.bold))
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.yellow)
                    .foregroundColor(.black)
                    .clipShape(Capsule())
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
}

#Preview {
    DriveHistoryView()
        .environmentObject(DriveManager.preview())
        .environmentObject(AppSettings.shared)
}
