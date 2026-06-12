import SwiftUI

struct DriveHistoryView: View {
    @EnvironmentObject var driveManager: DriveManager
    @State private var drivePendingDelete: Drive?
    @State private var deleteError: String?

    /// Yellow wins over red: a 0-60 PB is rarer, so when both PBs are
    /// held by the same drive, the yellow tint takes precedence.
    private func rowTint(isPB060: Bool, isPBTopSpeed: Bool) -> Color {
        if isPB060        { return Color.ftPB060Tint.opacity(0.15) }
        if isPBTopSpeed   { return Color.ftPBTopSpeedTint.opacity(0.10) }
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
                    // Hoist PB id lookups out of the ForEach — both are
                    // O(n) scans of `drives` and we were re-evaluating
                    // them once per row, making the list O(n²) on render.
                    let pb060Id = driveManager.pb060DriveId
                    let pbTopSpeedId = driveManager.pbTopSpeedDriveId
                    List {
                        ForEach(driveManager.drives) { drive in
                            let isPB060 = drive.id == pb060Id
                            let isPBTopSpeed = drive.id == pbTopSpeedId
                            NavigationLink(destination: DriveDetailView(drive: drive)) {
                                DriveRowView(
                                    drive: drive,
                                    isPersonalBest060: isPB060,
                                    isPersonalBestTopSpeed: isPBTopSpeed
                                )
                            }
                            .listRowBackground(rowTint(isPB060: isPB060, isPBTopSpeed: isPBTopSpeed))
                            .swipeActions(edge: .trailing) {
                                if drive.userID == AuthManager.shared.getUser()?.id {
                                    Button(role: .destructive) {
                                        drivePendingDelete = drive
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        }
                    }
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                }
            }
            .navigationTitle("Drive History")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { driveManager.fetchDrives() }
            .alert("Delete Drive?", isPresented: Binding(
                get: { drivePendingDelete != nil },
                set: { if !$0 { drivePendingDelete = nil } }
            )) {
                Button("Cancel", role: .cancel) { drivePendingDelete = nil }
                Button("Delete", role: .destructive) {
                    Task { await performDelete() }
                }
            } message: {
                Text("This permanently removes the drive from your history. This can't be undone.")
            }
            .alert("Unable to Delete Drive", isPresented: Binding(
                get: { deleteError != nil },
                set: { if !$0 { deleteError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteError ?? "Unknown error")
            }
        }
    }

    @MainActor
    private func performDelete() async {
        guard let drive = drivePendingDelete, let id = drive.id else { return }
        do {
            try await driveManager.deleteDrive(id: id)
            drivePendingDelete = nil
            ToastManager.shared.show(ToastMessage(
                text: "Drive deleted",
                actionLabel: "Undo"
            ) {
                Task { await driveManager.restoreDrive(drive) }
            })
        } catch {
            deleteError = error.localizedDescription
            drivePendingDelete = nil
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
                    pbPill(text: "PB 0-60", icon: "trophy.fill", bg: Color.ftPB060Tint, fg: Color.black)
                        .transition(.scale.combined(with: .opacity))
                }
                if isPersonalBestTopSpeed {
                    pbPill(text: "PB Top Speed", icon: "flame.fill", bg: Color.ftPBTopSpeedTint, fg: Color.white)
                        .transition(.scale.combined(with: .opacity))
                }
                Spacer()
                if !drive.carDisplayString.isEmpty && drive.carDisplayString != "Unknown Car" {
                    Text(drive.carDisplayString)
                        .font(.caption)
                        .foregroundColor(.ftBlue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.ftBlue.opacity(0.1))
                        .cornerRadius(Radius.xs)
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
                .font(FTFont.pill).minimumScaleFactor(0.7)
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
