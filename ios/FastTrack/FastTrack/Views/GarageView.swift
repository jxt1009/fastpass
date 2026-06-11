import SwiftUI

// MARK: - GarageView
//
// Pushed from the own profile's "View Garage" button. Replaces the
// inline `LazyVGrid` of `CarGarageCard`s with a richer grid of
// `GarageCarCard`s — hero photo, headline nickname, year/make/model,
// and a 2×2 mini-stat grid. Tapping a card pushes `CarDetailView`.
//
// The "Add Car" affordance reuses the existing `AddCarView` sheet
// (also reached from `CarSelectorView`), so there's no new
// add/edit flow. The empty state mirrors the "No cars in garage"
// message that's already on the profile so users in the new view see
// the same wording they saw on the profile.

struct GarageView: View {
    @EnvironmentObject var driveManager: DriveManager
    @StateObject private var profileManager = ProfileManager.shared
    @StateObject private var carStatsManager = CarStatsManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var showingAddCar = false
    @State private var drivePendingDelete: Drive?
    @State private var deleteError: String?

    private var cars: [UserCar] {
        profileManager.profile?.garage ?? []
    }

    private var columns: [GridItem] {
        // 2 columns on compact widths, 3 on regular. We don't bother
        // with a 4-column layout — most users have 1–3 cars and 3 cols
        // reads cleanly on iPad.
        [GridItem(.adaptive(minimum: 160), spacing: 12)]
    }

    private var allCarsStats: (totalDrives: Int, totalDistance: Double, topSpeed: Double, best060: Double?) {
        let allStats = carStatsManager.getAllStats()
        let totalDrives = allStats.reduce(0) { $0 + $1.totalDrives }
        let totalDistance = allStats.reduce(0.0) { $0 + $1.totalDistance }
        let topSpeed = allStats.map(\.bestTopSpeed).max() ?? 0
        let best060 = allStats.compactMap(\.bestZeroToSixty).min()
        return (totalDrives, totalDistance, topSpeed, best060)
    }

    private var allCarsSummary: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            InstrumentStatCell(
                icon: "flag.fill", iconColor: .ftGreen,
                label: "Total Drives",
                value: "\(allCarsStats.totalDrives)",
                unit: ""
            )
            InstrumentStatCell(
                icon: "map.fill", iconColor: .ftBlue,
                label: "Total Distance",
                value: String(format: "%.1f", settings.distanceValue(allCarsStats.totalDistance)),
                unit: settings.distanceUnit
            )
            InstrumentStatCell(
                icon: "bolt.fill", iconColor: .ftGold,
                label: "Top Speed",
                value: String(format: "%.0f", settings.speedValue(allCarsStats.topSpeed)),
                unit: settings.speedUnit
            )
            InstrumentStatCell(
                icon: "timer", iconColor: .ftAmber,
                label: "Best 0-60",
                value: allCarsStats.best060.map { String(format: "%.2f", $0) } ?? "—",
                unit: allCarsStats.best060 != nil ? "sec" : ""
            )
        }
    }

    private var recentDrivesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            let recent = driveManager.drives
                .sorted { $0.startTime > $1.startTime }
                .prefix(5)

            if !recent.isEmpty {
                SectionHeader(title: "Recent Drives")
                ForEach(Array(recent)) { drive in
                    NavigationLink {
                        DriveDetailView(drive: drive)
                    } label: {
                        GarageDriveRow(drive: drive)
                    }
                    .buttonStyle(.plain)
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
            if driveManager.drives.count > 5 {
                NavigationLink {
                    DriveHistoryView()
                } label: {
                    HStack {
                        Text("See All Drives")
                        Image(systemName: "chevron.right")
                    }
                    .font(.subheadline)
                    .foregroundColor(.ftBlue)
                }
            }
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    allCarsSummary
                    if cars.isEmpty {
                        emptyState
                            .padding(.top, 60)
                    } else {
                        LazyVGrid(columns: columns, spacing: 12) {
                            ForEach(cars) { car in
                                GarageCarCard(
                                    car: car,
                                    stats: carStatsManager.getStats(for: car.id)
                                )
                            }
                        }
                        recentDrivesSection
                    }
                }
                .padding()
            }
            .background(Color.ftSurfaceBg.ignoresSafeArea())
            .navigationTitle("Your Garage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingAddCar = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundColor(.ftBlue)
                            .font(.title3)
                    }
                    .accessibilityLabel("Add Car")
                }
            }
            .sheet(isPresented: $showingAddCar) {
                AddCarView()
            }
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

    // MARK: - Empty state

    private var emptyState: some View {
        InstrumentCard {
            VStack(spacing: 14) {
                Image(systemName: "car")
                    .font(FTFont.scoreboard).minimumScaleFactor(0.6)
                    .foregroundColor(.secondary)
                Text("No cars in your garage yet")
                    .font(.headline)
                    .foregroundColor(.primary)
                Text("Add a car to start tracking drives, photos, and personal bests.")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                Button {
                    showingAddCar = true
                } label: {
                    Text("Add Your First Car")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(InstrumentButtonStyle(color: .ftBlue))
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
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

// MARK: - Garage Car Card
//
// A single car card in the `GarageView` grid. Distinct from
// `CarGarageCard` (the legacy row in `ProfileView.garageSection`):
// - Hero photo on top (160pt), full-width, rounded top corners
// - Nickname (large, headline) + year/make/model/trim (caption)
// - 2×2 mini-stat grid (drives, total distance, top speed, best 0-60)
// - Tap to push `CarDetailView`. Photo zoom is intentionally not
//   triggered from the card to avoid the SwiftUI double-tap hazard
//   where a `.onTapGesture` on a child of a `NavigationLink` label
//   fires the gesture *and* pushes the destination. The detail
//   view's hero still offers a tap-to-zoom.
// - Context menu offers Edit / Select as Active (matching the
//   legacy card's behavior on the profile)

struct GarageCarCard: View {
    let car: UserCar
    let stats: CarStats?

    @EnvironmentObject var driveManager: DriveManager
    @ObservedObject private var profileManager = ProfileManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var editingCar: EditingCarTarget?
    @State private var showingRemoveAlert = false

    private var isSelected: Bool {
        profileManager.profile?.selectedCarId == car.id
    }

    var body: some View {
        NavigationLink {
            CarDetailView(carId: car.id)
        } label: {
            card
        }
        .buttonStyle(.plain)
        .contextMenu {
            Button {
                editingCar = EditingCarTarget(id: car.id)
            } label: {
                Label("Edit Car", systemImage: "pencil")
            }
            if !isSelected {
                Button {
                    selectCar()
                } label: {
                    Label("Select as Active", systemImage: "checkmark.circle")
                }
            }
            Button(role: .destructive) {
                showingRemoveAlert = true
            } label: {
                Label("Remove Car", systemImage: "trash")
            }
        }
        .alert("Remove Car", isPresented: $showingRemoveAlert) {
            Button("Remove", role: .destructive) {
                removeCar()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Remove this car from your garage? Its recorded drives and stats will remain in your history.")
        }
        .sheet(item: $editingCar) { target in
            EditCarView(carId: target.id)
        }
    }

    @ViewBuilder
    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            photo
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Radius.xl, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Text("SELECTED")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.ftBlue)
                            )
                            .padding(8)
                    }
                }
                .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 4) {
                Text(car.nickname.isEmpty ? car.shortDisplay : car.nickname)
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text(car.displayString)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .padding(.top, 10)

            statsGrid
                .padding(.horizontal, 10)
                .padding(.top, 8)
                .padding(.bottom, 10)
        }
        .background(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(Color.ftCardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
    }

    private var photo: some View {
        CarPhotoView(
            car: car,
            url: car.photoUrl.flatMap { $0.isEmpty ? nil : URL(string: $0) },
            cornerRadius: 0
        )
    }

    private var statsGrid: some View {
        LazyVGrid(
            columns: [GridItem(.flexible()), GridItem(.flexible())],
            spacing: 6
        ) {
            StatMini(title: "Drives", value: "\(stats?.totalDrives ?? 0)")
            StatMini(
                title: settings.distanceUnit == "mi" ? "Miles" : "KM",
                value: String(
                    format: "%.0f",
                    settings.distanceValue(stats?.totalDistance ?? 0)
                )
            )
            StatMini(
                title: "Top Speed",
                value: stats.map {
                    String(format: "%.0f", settings.speedValue($0.bestTopSpeed))
                } ?? "—"
            )
            StatMini(
                title: "0-60",
                value: stats?.bestZeroToSixty.map {
                    String(format: "%.1fs", $0)
                } ?? "—"
            )
        }
    }

    private func selectCar() {
        guard var profile = profileManager.profile else { return }
        profile.selectCar(id: car.id)
        profileManager.saveProfile(profile)
    }

    private func removeCar() {
        guard var profile = profileManager.profile else { return }
        profile.removeCarFromGarage(id: car.id)
        profileManager.saveProfile(profile)
    }
}

// MARK: - Garage Drive Row

struct GarageDriveRow: View {
    let drive: Drive
    var badge: GarageDriveBadge? = nil
    @EnvironmentObject var settings: AppSettings

    var body: some View {
        InstrumentCard {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 4) {
                        Text(drive.startTime, style: .date)
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        if !drive.carDisplayString.isEmpty && drive.carDisplayString != "Unknown Car" {
                            Text(drive.carDisplayString)
                                .font(.caption2)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.ftBlue.opacity(0.8))
                                .clipShape(Capsule())
                        }
                    }
                    HStack(spacing: 12) {
                        Label(settings.speedDisplay(drive.maxSpeed), systemImage: "speedometer")
                        Label(settings.distanceDisplay(drive.distance, decimals: 1), systemImage: "map")
                        Label(drive.durationString, systemImage: "clock")
                    }
                    .font(.caption)
                    .foregroundColor(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 8) {
                    if let badge {
                        HStack(spacing: 3) {
                            Image(systemName: badge.icon)
                                .font(FTFont.pill).minimumScaleFactor(0.7)
                            Text(badge.text)
                                .font(.caption2.weight(.bold))
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(badge.background)
                        .foregroundColor(badge.foreground)
                        .clipShape(Capsule())
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(Color.secondary.opacity(0.7))
                }
            }
        }
    }
}

struct GarageDriveBadge {
    let text: String
    let icon: String
    let background: Color
    let foreground: Color
}

// MARK: - Analytics Card (hoisted from AnalyticsView)

struct AnalyticsCard: View {
    let title: String
    let value: String
    let icon: String
    let iconColor: Color
    let trend: TrendDirection?
    var info: StatInfoEntry? = nil

    var body: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(iconColor)
                        .font(.title3)
                    Spacer()
                    if let trend = trend {
                        TrendIndicator(trend: trend)
                    }
                    if let info { StatInfoButton(entry: info) }
                }

                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct TrendIndicator: View {
    let trend: TrendDirection

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: trend.icon)
                .font(.caption)
            Text(trend.label)
                .font(.caption2)
        }
        .foregroundColor(trend.color)
    }
}

/// Wrapper so `.sheet(item:)` can drive a `carId` (String is not Identifiable).
/// Defined privately here because `ProfileView.swift` already has its own
/// `EditingCarTarget`; Swift's access control keeps them in their own
/// files. This one is used by `GarageCarCard`.
private struct EditingCarTarget: Identifiable {
    let id: String
}
