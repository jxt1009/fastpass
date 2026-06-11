import SwiftUI

// MARK: - Main Profile View
// MARK: - Main Profile View

struct ProfileView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @StateObject private var achievementManager = AchievementManager.shared
    @StateObject private var appleSignInManager = AppleSignInManager()
    @EnvironmentObject var driveManager: DriveManager
    @EnvironmentObject var locationManager: LocationManager
    @ObservedObject private var settings = AppSettings.shared
    @State private var showingSetup = false
    @State private var showingAddCar = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
    @State private var showingSignOutConfirmation = false
    @State private var zoomedAvatar: AvatarZoomTarget?
    @State private var croppingAvatar: CropImageSource?
    var onSwitchToGarage: (() -> Void)? = nil
    private var stats: UserStats {
        UserStats.from(drives: driveManager.drives)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.ftSurfaceBg.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        profileHeader
                        garageLinkRow
                        RecentAchievementsStrip(driveManager: driveManager)
                        if driveManager.isLoadingDrives {
                            profileStatsSkeleton
                        } else {
                            mainStatsGrid
                            headlineSpeedGrid
                        }
                        privacyToggleCard
                        deleteAccountButton
                        signOutButton
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        NavigationLink {
                            SettingsView()
                                .environmentObject(AppSettings.shared)
                        } label: {
                            Image(systemName: "gearshape")
                                .foregroundColor(.ftBlue)
                        }
                        Button {
                            showingSetup = true
                        } label: {
                            Image(systemName: "pencil.circle")
                                .foregroundColor(.ftBlue)
                        }
                    }
                }
            }
            .sheet(isPresented: $showingSetup) {
                ProfileSetupView()
            }
            .fullScreenCover(item: $zoomedAvatar) { target in
                AvatarZoomView(
                    url: target.url,
                    image: target.image,
                    onDismiss: { zoomedAvatar = nil },
                    onEdit: { image in
                        zoomedAvatar = nil
                        let resized = image.resizedForAvatar(maxDimension: 2048)
                        croppingAvatar = CropImageSource(image: resized, context: .avatar)
                    }
                )
            }
            .fullScreenCover(item: $croppingAvatar) { source in
                PhotoCropView(image: source.image, context: source.context) { cropped in
                    profileManager.saveAvatar(cropped.resizedForAvatar(maxDimension: 800))
                }
            }
            .alert("Delete Account?", isPresented: $showingDeleteAccountConfirmation) {
                Button("Cancel", role: .cancel) {}
                Button(isDeletingAccount ? "Deleting..." : "Delete", role: .destructive) {
                    Task { await deleteAccount() }
                }
                .disabled(isDeletingAccount)
            } message: {
                Text("This permanently deletes your FastTrack account and recorded drive data.")
            }
            .alert("Unable to Delete Account", isPresented: Binding(
                get: { deleteAccountError != nil },
                set: { if !$0 { deleteAccountError = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(deleteAccountError ?? "Unknown error")
            }
            .onAppear {
                if !profileManager.isProfileComplete {
                    showingSetup = true
                }
                driveManager.fetchDrives()
                achievementManager.updateProgress(with: driveManager.drives)
                Task { await driveManager.refreshAchievementsFromServer() }
            }
            .onChange(of: driveManager.drives) { _, drives in
                achievementManager.updateProgress(with: drives)
            }
        }
    }

    // MARK: Profile Header

    private var profileHeader: some View {
        InstrumentCard {
            HStack(alignment: .center, spacing: 12) {
                // Avatar — tap to zoom. Mirrors the public-profile header.
                avatarView
                    .onTapGesture { presentAvatarZoom() }

                VStack(alignment: .leading, spacing: 2) {
                    Text(profileManager.profile.map { $0.username } ?? "Set up profile")
                        .font(.headline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    if let username = profileManager.profile?.username, !username.isEmpty {
                        Text("@\(username)")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    if !bioLine.isEmpty {
                        Text(bioLine)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)
            }
        }
    }

    @ViewBuilder
    private var avatarView: some View {
        if let img = profileManager.profileImage {
            Image(uiImage: img)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
                )
        } else {
            ZStack {
                Circle()
                    .fill(Color.ftBlue.opacity(0.3))
                    .frame(width: 56, height: 56)
                Image(systemName: "person.fill")
                    .font(.title2)
                    .foregroundColor(.ftBlue)
            }
        }
    }

    /// Compact bio: country + active car make/model. Used in the narrow
    /// header. Empty when nothing is set yet, so the header collapses
    /// gracefully.
    private var bioLine: String {
        guard let profile = profileManager.profile else { return "" }
        var parts: [String] = []
        if !profile.country.isEmpty { parts.append(profile.country) }
        if !profile.carMake.isEmpty { parts.append(profile.carDisplayString) }
        return parts.joined(separator: " · ")
    }

    private func presentAvatarZoom() {
        guard let image = profileManager.profileImage else { return }
        // Use the in-memory UIImage so the zoom shows the locally-saved
        // avatar. Persisted / uploaded URL is also available via the
        // server, but the local copy is always current and avoids a
        // network round-trip for the zoom.
        zoomedAvatar = AvatarZoomTarget(image: image)
    }

    // MARK: - Garage Link Row

    private var garageLinkRow: some View {
        Button {
            onSwitchToGarage?()
        } label: {
            HStack {
                Image(systemName: "car.2.fill")
                    .foregroundColor(.ftBlue)
                Text("Your Garage")
                    .fontWeight(.semibold)
                Spacer()
                if let profile = profileManager.profile, !profile.garage.isEmpty {
                    Text("\(profile.garage.count) car\(profile.garage.count == 1 ? "" : "s")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                }
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
    }

    // MARK: - Loading skeleton (dark theme)

    private var profileStatsSkeleton: some View {
        VStack(spacing: 16) {
            // Stats grid skeleton (4 cells)
            StatsGrid(spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .fill(Color.ftCardBg.opacity(0.2))
                        .frame(height: 80)
                        .shimmer()
                }
            }
            // Full-width card skeletons
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: Radius.lg)
                    .fill(Color.ftCardBg.opacity(0.2))
                    .frame(height: 60)
                    .shimmer()
            }
        }
    }


    // MARK: Main Stats Grid

    private var mainStatsGrid: some View {
        StatsGrid(spacing: 10) {
            InstrumentStatCell(
                icon: "location.fill", iconColor: .cyan,
                label: "Total Distance",
                value: String(format: "%.1f", settings.distanceValue(stats.totalDistance)),
                unit: settings.distanceUnit
            )
            InstrumentStatCell(
                icon: "clock.fill", iconColor: .orange,
                label: "Total Duration",
                value: formatDuration(stats.totalDuration),
                unit: ""
            )
            InstrumentStatCell(
                icon: "pause.fill", iconColor: .purple,
                label: "Stopped Time",
                value: formatDuration(stats.totalStoppedTime),
                unit: ""
            )
            InstrumentStatCell(
                icon: "flag.fill", iconColor: .green,
                label: "Total Trips",
                value: "\(stats.totalTrips)",
                unit: ""
            )
        }
    }

    // MARK: Headline Speed Grid (Top Speed + Best 0-60)

    private var headlineSpeedGrid: some View {
        StatsGrid(spacing: 10) {
            InstrumentStatCell(
                icon: "bolt.fill", iconColor: .yellow,
                label: "Top Speed",
                value: String(format: "%.0f", settings.speedValue(stats.topSpeed)),
                unit: settings.speedUnit
            )
            InstrumentStatCell(
                icon: "timer", iconColor: .orange,
                label: "Best 0-60",
                value: stats.best060Time.map { String(format: "%.2f", $0) } ?? "—",
                unit: stats.best060Time != nil ? "sec" : "",
                info: StatInfo.zeroToSixty
            )
        }
    }

    // MARK: Privacy Toggle

    private var privacyToggleCard: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 10) {
                Toggle(isOn: Binding(
                    get: { profileManager.profile?.isPublic ?? true },
                    set: { newValue in
                        guard var p = profileManager.profile else { return }
                        p.isPublic = newValue
                        profileManager.saveProfile(p)
                        ToastManager.shared.show(ToastMessage(
                            text: newValue ? "Profile is now public" : "Profile is now private"
                        ))
                    }
                )) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Public Profile")
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Text("Appear on leaderboards and let others view your stats")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .tint(.ftBlue)
            }
        }
    }


    // MARK: Sign Out

    private var deleteAccountButton: some View {
        Button(role: .destructive) {
            showingDeleteAccountConfirmation = true
        } label: {
            HStack {
                if isDeletingAccount {
                    ProgressView()
                        .tint(.red)
                }
                Text("Delete Account")
                    .fontWeight(.semibold)
            }
            .foregroundColor(.red)
            .frame(maxWidth: .infinity)
            .padding()
            .background(Color.ftCardBg)
            .cornerRadius(Radius.lg)
        }
        .disabled(isDeletingAccount)
        .padding(.top, 8)
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            showingSignOutConfirmation = true
        } label: {
            Text("Sign Out")
                .fontWeight(.semibold)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color.ftCardBg)
                .cornerRadius(Radius.lg)
        }
        .confirmationDialog(
            "Sign out of FastTrack?",
            isPresented: $showingSignOutConfirmation,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                AuthManager.shared.signOut()
                ToastManager.shared.show(ToastMessage(text: "Signed out"))
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll need to sign in again to view drives.")
        }
        .padding(.top, 8)
    }

    // MARK: Helpers

    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }

    @MainActor
    private func deleteAccount() async {
        guard !isDeletingAccount else { return }

        isDeletingAccount = true
        defer { isDeletingAccount = false }

        do {
            let authProvider = AuthManager.shared.getUser()?.authProvider?.lowercased()
            let isAppleUser =
                authProvider == "apple" ||
                (authProvider == nil && AuthManager.shared.getUser()?.appleUserID != nil)

            let appleAuthorizationCode: String?
            if isAppleUser {
                appleAuthorizationCode = try await appleSignInManager.reauthorizeForAccountDeletion()
            } else {
                appleAuthorizationCode = nil
            }

            try await AuthManager.shared.deleteAccount(appleAuthorizationCode: appleAuthorizationCode)
            driveManager.clearLocalData()
        } catch {
            deleteAccountError = error.localizedDescription
        }
    }
}

// MARK: - Car Garage Card with Stats

// MARK: - Remote Drive Detail Loader

/// Fetches a single drive via the public endpoint on appear and forwards it
/// to `DriveDetailView`. Used by profile achievement rows when the source
/// drive isn't in the local cache.
struct RemoteDriveDetailLoader: View {
    let driveId: Int
    @State private var drive: Drive?
    @State private var error: String?
    @State private var isLoading = true

    var body: some View {
        Group {
            if let drive {
                DriveDetailView(drive: drive)
            } else if isLoading {
                ProgressView("Loading drive…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ContentUnavailableView(
                    "Drive Unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(error ?? "This drive could not be loaded.")
                )
            }
        }
        .task { await load() }
    }

    private func load() async {
        do {
            let fetched = try await APIService.shared.fetchPublicDrive(id: driveId)
            await MainActor.run {
                self.drive = fetched
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.error = error.localizedDescription
                self.isLoading = false
            }
        }
    }
}

struct CarGarageCard: View {
    let car: UserCar
    let isSelected: Bool
    let onSelect: () -> Void

    @StateObject private var carStatsManager = CarStatsManager.shared
    @State private var showingStats = false
    @State private var editingCar: EditingCarTarget?

    private var carStats: CarStats? {
        carStatsManager.getStats(for: car.id)
    }

    var body: some View {
        InstrumentCard {
            VStack(spacing: 8) {
                // Main car info
                HStack(spacing: 12) {
                    CarPhotoThumbnail(photoURL: car.photoUrl, size: 56)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(car.shortDisplay)
                            .font(.headline)
                            .fontWeight(.semibold)
                            .foregroundColor(.primary)
                        Text(car.displayString)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        if isSelected {
                            Text("SELECTED")
                                .font(.caption2)
                                .fontWeight(.semibold)
.foregroundColor(.ftBlue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.ftBlue.opacity(0.2))
                                .cornerRadius(Radius.sm)
                        }

                        Button {
                            showingStats.toggle()
                        } label: {
                            Image(systemName: showingStats ? "chevron.up" : "chart.bar")
                                .foregroundColor(.gray)
                        }
                    }
                }

                // Stats section (collapsible)
                if showingStats {
                    Divider()

                    if let stats = carStats {
                        CarStatsRow(stats: stats)
                    } else {
                        Text("No driving data yet")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.vertical, 4)
                    }
                }
            }
            .padding(.vertical, showingStats ? 8 : 4)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            if !showingStats {
                onSelect()
            }
        }
        .contextMenu {
            Button {
                editingCar = EditingCarTarget(id: car.id)
            } label: {
                Label("Edit Car", systemImage: "pencil")
            }
            if !isSelected {
                Button {
                    onSelect()
                } label: {
                    Label("Select as Active", systemImage: "checkmark.circle")
                }
            }
        }
        .sheet(item: $editingCar) { target in
            EditCarView(carId: target.id)
        }
    }
}

/// Wrapper so `.sheet(item:)` can drive a `carId` (String is not Identifiable).
private struct EditingCarTarget: Identifiable {
    let id: String
}

/// Small rounded thumbnail for a car's photo. Falls back to a tinted car icon
/// placeholder when no usable photo URL is set.
struct CarPhotoThumbnail: View {
    let photoURL: String?
    var size: CGFloat = 56

    var body: some View {
        Group {
            if let photoURL, !photoURL.isEmpty, let url = URL(string: photoURL) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .empty:
                        placeholder
                    case .success(let image):
                        image.resizable().scaledToFill()
                    case .failure:
                        placeholder
                    @unknown default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: Radius.md))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(Color.ftBlue.opacity(0.15))
            Image(systemName: "car.fill")
                .font(.system(size: size * 0.45))
                .foregroundColor(.ftBlue)
        }
    }
}

struct CarStatsRow: View {
    let stats: CarStats
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        StatsGrid(spacing: 8) {
            StatMini(title: "Drives", value: "\(stats.totalDrives)")
            StatMini(title: settings.distanceUnit == "mi" ? "Miles" : "KM",
                     value: String(format: "%.0f", settings.distanceValue(stats.totalDistance)))
            StatMini(title: "Top Speed",
                     value: String(format: "%.0f \(settings.speedUnit)", settings.speedValue(stats.bestTopSpeed)))
            StatMini(title: "Category", value: stats.performanceCategory)
        }
    }
}

struct StatMini: View {
    let title: String
    let value: String
    
    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(.primary)
            Text(title)
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
}
