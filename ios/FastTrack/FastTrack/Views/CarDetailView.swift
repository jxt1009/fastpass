import SwiftUI
import Charts

// MARK: - CarDetailView
//
// Pushed from `GarageView` (or a future public profile deep link).
// Showy per-car mini-profile with: hero photo, two large PB gauges
// (Top Speed, Best 0-60), a sparkline of this car's `maxSpeed` per
// drive, a driving-style badge, a stats grid, a per-car PBs list of
// achievements whose source drive belongs to this car, and a
// one-shot confetti animation when a PB is newer than 7 days.
//
// The hero photo carries a pencil overlay that opens a focused
// `CarHeroPhotoEditorSheet` for photo-only edits. The toolbar pencil
// still opens the full `EditCarView` (nickname + photo).
//
// Data is assembled once via `CarDetailData.derive(...)` so the view
// body stays a thin renderer.

struct CarDetailView: View {
    let carId: String

    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var carStatsManager: CarStatsManager
    @EnvironmentObject var achievementManager: AchievementManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var driveManager: DriveManager

    private var car: UserCar? {
        profileManager.profile?.garage.first(where: { $0.id == carId })
    }

    private var isActiveCar: Bool {
        profileManager.profile?.selectedCarId == carId
    }

    @State private var zoomedPhoto: AvatarZoomTarget?
    @State private var showConfetti = false
    @State private var confettiTask: Task<Void, Never>?
    @State private var showingEditCar = false
    @State private var showingHeroPhotoEditor = false
    @State private var showingDrivingStyleGuide = false
    @State private var lastPresentedConfettiToken: String?
    @State private var drivePendingDelete: Drive?
    @State private var showingDeleteConfirmation = false
    @State private var deleteError: String?

    /// Snapshot of the data the view is rendering. Rebuilt whenever
    /// the source data changes. Nil until the first `refresh()` call
    /// or when the car has been removed from the garage.
    @State private var data: CarDetailData?

    private var currentData: CarDetailData? {
        guard let car else { return nil }
        return CarDetailData.derive(
            car: car,
            drives: driveManager.drives,
            carStats: carStatsManager.getStats(for: car.id),
            achievements: achievementManager.achievements,
            now: Date(),
            calculateSmoothness: carStatsManager.calculateSmoothnessScore
        )
    }

    var body: some View {
        Group {
            if car != nil {
                content
                    .fullScreenCover(item: $zoomedPhoto, content: photoZoomCover)
                    .sheet(isPresented: $showingEditCar) {
                        EditCarView(carId: carId)
                    }
                    .sheet(isPresented: $showingHeroPhotoEditor) {
                        CarDetailPhotoEditor(
                            carId: carId,
                            existingPhotoURL: car?.photoUrl,
                            onUploadComplete: handleHeroPhotoUpload,
                            isPresented: $showingHeroPhotoEditor
                        )
                    }
                    .sheet(isPresented: $showingDrivingStyleGuide) {
                        CarDetailStyleGuide(isPresented: $showingDrivingStyleGuide)
                    }
                    .overlay(alignment: .top, content: {
                        ConfettiOverlay(show: showConfetti)
                    })
                    .modifier(LifecycleModifier(
                        onAppear: handleAppear,
                        onDisappear: handleDisappear,
                        driveCount: driveManager.drives.count,
                        carStatsCount: carStatsManager.carStats.count,
                        achievementCount: achievementManager.achievements.count,
                        onChangeRefresh: refresh
                    ))
            } else {
                ContentUnavailableView(
                    "Car Removed",
                    systemImage: "car.fill",
                    description: Text("This car is no longer in your garage.")
                )
            }
        }
        .background(Color.ftSurfaceBg.ignoresSafeArea())
        .navigationTitle(car.map { $0.nickname.isEmpty ? $0.shortDisplay : $0.nickname } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    if car != nil {
                        Button {
                            showingEditCar = true
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundColor(.ftBlue)
                        }
                    }
                    if isActiveCar {
                        BadgePill("Active", style: .selected)
                    } else if car != nil {
                        Button("Set Active") {
                            setActiveCar()
                        }
                        .foregroundColor(.ftBlue)
                    }
                }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                CarDetailHero(
                    car: car,
                    data: data,
                    settings: settings,
                    onTapPhoto: presentPhotoZoom,
                    onTapEditPhoto: { showingHeroPhotoEditor = true },
                    onTapStyleGuide: { showingDrivingStyleGuide = true }
                )
                CarDetailSparkline(data: data, settings: settings)
                CarDetailStatsGrid(
                    data: data,
                    settings: settings,
                    car: car,
                    drives: driveManager.drives
                )
                CarDetailDrivesList(
                    data: data,
                    driveManager: driveManager,
                    settings: settings,
                    car: car,
                    onDeleteDrive: { drive in
                        drivePendingDelete = drive
                        showingDeleteConfirmation = true
                    }
                )
                Spacer(minLength: 16)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
        .alert("Delete Drive?", isPresented: $showingDeleteConfirmation) {
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

    private func handleAppear() {
        refresh()
    }

    private func handleDisappear() {
        confettiTask?.cancel()
        confettiTask = nil
        showConfetti = false
    }

    private func setActiveCar() {
        guard var profile = profileManager.profile else { return }
        profile.selectCar(id: carId)
        profileManager.saveProfile(profile)
    }

    @MainActor
    private func handleHeroPhotoUpload(newURL: URL) {
        guard var profile = profileManager.profile else { return }
        profile.updateCarPhotoUrl(id: carId, url: newURL.absoluteString)
        profileManager.saveProfile(profile)
        refresh()
    }

    // MARK: - Photo Zoom

    @ViewBuilder
    private func photoZoomCover(_ target: AvatarZoomTarget) -> some View {
        AvatarZoomView(url: target.url, image: target.image) {
            zoomedPhoto = nil
        }
    }

    private func presentPhotoZoom() {
        guard let urlString = car?.photoUrl, !urlString.isEmpty,
              let url = URL(string: urlString) else { return }
        zoomedPhoto = AvatarZoomTarget(url: url)
    }

    // MARK: - Lifecycle

    private func refresh() {
        data = currentData
        triggerConfettiIfEligible()
    }

    private func triggerConfettiIfEligible() {
        confettiTask?.cancel()
        guard data?.confettiEligible == true,
              let token = data?.confettiTriggerToken else { return }
        guard token != lastPresentedConfettiToken else { return }
        guard UserDefaults.standard.string(forKey: confettiTokenDefaultsKey) != token else {
            lastPresentedConfettiToken = token
            return
        }

        lastPresentedConfettiToken = token
        UserDefaults.standard.set(token, forKey: confettiTokenDefaultsKey)
        showConfetti = true
        confettiTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if Task.isCancelled { return }
            showConfetti = false
            confettiTask = nil
        }
    }

    private var confettiTokenDefaultsKey: String {
        "CarDetailView.lastConfettiToken.\(carId)"
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
            deleteError = error.diagnosticDescription
            drivePendingDelete = nil
        }
    }
}

// MARK: - Lifecycle modifier

private struct LifecycleModifier: ViewModifier {
    let onAppear: () -> Void
    let onDisappear: () -> Void
    let driveCount: Int
    let carStatsCount: Int
    let achievementCount: Int
    let onChangeRefresh: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
            .onChange(of: driveCount) { _, _ in onChangeRefresh() }
            .onChange(of: carStatsCount) { _, _ in onChangeRefresh() }
            .onChange(of: achievementCount) { _, _ in onChangeRefresh() }
    }
}
