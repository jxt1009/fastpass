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
    @StateObject private var profileManager = ProfileManager.shared
    @StateObject private var carStatsManager = CarStatsManager.shared
    @State private var showingAddCar = false
    @State private var zoomedPhoto: AvatarZoomTarget?

    private var cars: [UserCar] {
        profileManager.profile?.garage ?? []
    }

    private var columns: [GridItem] {
        // 2 columns on compact widths, 3 on regular. We don't bother
        // with a 4-column layout — most users have 1–3 cars and 3 cols
        // reads cleanly on iPad.
        [GridItem(.adaptive(minimum: 160), spacing: 12)]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if cars.isEmpty {
                    emptyState
                        .padding(.top, 60)
                } else {
                    LazyVGrid(columns: columns, spacing: 12) {
                        ForEach(cars) { car in
                            GarageCarCard(
                                car: car,
                                stats: carStatsManager.getStats(for: car.id)
                            ) {
                                zoomedPhoto = photoTarget(for: car)
                            }
                        }
                    }
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
        .fullScreenCover(item: $zoomedPhoto) { target in
            AvatarZoomView(url: target.url, image: target.image) {
                zoomedPhoto = nil
            }
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        InstrumentCard {
            VStack(spacing: 14) {
                Image(systemName: "car")
                    .font(.system(size: 36))
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

    // MARK: - Photo target

    private func photoTarget(for car: UserCar) -> AvatarZoomTarget? {
        guard let urlString = car.photoUrl, !urlString.isEmpty,
              let url = URL(string: urlString) else {
            return nil
        }
        return AvatarZoomTarget(url: url)
    }
}

// MARK: - Garage Car Card
//
// A single car card in the `GarageView` grid. Distinct from
// `CarGarageCard` (the legacy row in `ProfileView.garageSection`):
// - Hero photo on top (160pt), full-width, rounded top corners
// - Nickname (large, headline) + year/make/model/trim (caption)
// - 2×2 mini-stat grid (drives, total distance, top speed, best 0-60)
// - Tap to push `CarDetailView`; tap on the photo to zoom
// - Context menu offers Edit / Select as Active (matching the
//   legacy card's behavior on the profile)

struct GarageCarCard: View {
    let car: UserCar
    let stats: CarStats?
    let onPhotoTap: () -> Void

    @EnvironmentObject var driveManager: DriveManager
    @ObservedObject private var profileManager = ProfileManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var editingCar: EditingCarTarget?

    private var isSelected: Bool {
        profileManager.profile?.selectedCarId == car.id
    }

    var body: some View {
        NavigationLink {
            CarDetailView(car: car)
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
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                .onTapGesture { onPhotoTap() }

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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.ftCardBg)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 0.5)
        )
    }

    @ViewBuilder
    private var photo: some View {
        if let urlString = car.photoUrl, !urlString.isEmpty,
           let url = URL(string: urlString) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .empty:
                    photoPlaceholder
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    photoPlaceholder
                @unknown default:
                    photoPlaceholder
                }
            }
        } else {
            photoPlaceholder
        }
    }

    private var photoPlaceholder: some View {
        ZStack {
            LinearGradient(
                colors: [.ftBlue.opacity(0.5), .purple.opacity(0.4)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Text(initials(for: car))
                .font(.system(size: 48, weight: .bold, design: .rounded))
                .foregroundColor(.white.opacity(0.9))
        }
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
                title: "Top",
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

    private func initials(for car: UserCar) -> String {
        let first = car.make.first.map(String.init) ?? ""
        let second = car.model.first.map(String.init) ?? ""
        let combined = (first + second).uppercased()
        return combined.isEmpty ? "?" : combined
    }

    private func selectCar() {
        guard var profile = profileManager.profile else { return }
        profile.selectCar(id: car.id)
        profileManager.saveProfile(profile)
    }
}

/// Wrapper so `.sheet(item:)` can drive a `carId` (String is not Identifiable).
/// Defined privately here because `ProfileView.swift` already has its own
/// `EditingCarTarget`; Swift's access control keeps them in their own
/// files. This one is used by `GarageCarCard`.
private struct EditingCarTarget: Identifiable {
    let id: String
}
