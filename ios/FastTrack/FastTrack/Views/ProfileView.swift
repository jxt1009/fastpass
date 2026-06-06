import SwiftUI

// MARK: - Turn Preference Bar

private struct TurnPreferenceBar: View {
    let leftFraction: Double  // 0–1

    var leftPct: Int { Int(leftFraction * 100) }
    var rightPct: Int { 100 - leftPct }

    var body: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Turn Preference")
                    .font(.headline)
                    .foregroundColor(.primary)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: max(geo.size.width * leftFraction, 4))
                        Rectangle()
                            .fill(Color.pink)
                    }
                    .cornerRadius(4)
                }
                .frame(height: 28)
                HStack {
                    Text("\(leftPct)%")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.blue)
                    Text("Left")
                        .font(.caption).foregroundColor(.secondary)
                    Spacer()
                    Text("Right")
                        .font(.caption).foregroundColor(.secondary)
                    Text("\(rightPct)%")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.pink)
                }
            }
        }
    }
}

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
    @State private var showingSettings = false
    @State private var showingDeleteAccountConfirmation = false
    @State private var isDeletingAccount = false
    @State private var deleteAccountError: String?
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
                        garageSection
                        if driveManager.isLoadingDrives {
                            profileStatsSkeleton
                        } else {
                            mainStatsGrid
                            topSpeedCard
                            best060Card
                            SectionHeader(title: "Maneuvers", info: StatInfo.maneuversSection)
                            maneuvorsGrid
                            TurnPreferenceBar(leftFraction: stats.turnPreferencePct)
                            SectionHeader(title: "Performance", info: StatInfo.performanceSection)
                            performanceGrid
                            SectionHeader(title: "More Stats")
                            moreStatsGrid
                        }
                        privacyToggleCard
                        SectionHeader(title: "Achievements")
                        achievementsSection
                        SectionHeader(title: "Settings")
                        settingsSection
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
                    Button {
                        showingSetup = true
                    } label: {
                        Image(systemName: "pencil.circle")
                            .foregroundColor(.ftBlue)
                    }
                }
            }
            .sheet(isPresented: $showingSetup) {
                ProfileSetupView()
            }
            .sheet(isPresented: $showingAddCar) {
                AddCarView()
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
            HStack(spacing: 14) {
                // Avatar
                ZStack {
                    if let img = profileManager.profileImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 56, height: 56)
                        Image(systemName: "person.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(profileManager.profile.map { "@\($0.username)" } ?? "Set up profile")
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(.primary)
                    let subtitle = [
                        profileManager.profile?.country,
                        profileManager.profile.flatMap { p in
                            p.carMake.isEmpty ? nil : p.carDisplayString
                        }
                    ].compactMap { $0 }.joined(separator: " · ")
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(settings.speedValue(locationManager.currentSpeed)))")
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(.primary)
                    Text(settings.speedUnit)
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Loading skeleton (dark theme)

    private var profileStatsSkeleton: some View {
        VStack(spacing: 16) {
            // Stats grid skeleton (4 cells)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                ForEach(0..<6, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color(.systemGray6).opacity(0.2))
                        .frame(height: 80)
                        .shimmer()
                }
            }
            // Full-width card skeletons
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6).opacity(0.2))
                    .frame(height: 60)
                    .shimmer()
            }
        }
    }

    // MARK: - Garage Section
    
    private var garageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Garage")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                Spacer()
                Button {
                    showingAddCar = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
            }
            
            if let profile = profileManager.profile, !profile.garage.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 8) {
                    ForEach(profile.garage) { car in
                        CarGarageCard(
                            car: car,
                            isSelected: profile.selectedCarId == car.id
                        ) {
                            selectCar(car.id)
                        }
                    }
                }
            } else {
                InstrumentCard {
                    VStack(spacing: 12) {
                        Image(systemName: "car")
                            .font(.title2)
                            .foregroundColor(.secondary)
                        Text("No cars in garage")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        Button("Add Your First Car") {
                            showingAddCar = true
                        }
                        .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: Main Stats Grid

    private var mainStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
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

    // MARK: Top Speed (full-width card)

    private var topSpeedCard: some View {
        InstrumentCard {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Speed")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", settings.speedValue(stats.topSpeed)))
                            .font(.largeTitle).fontWeight(.bold)
                            .foregroundColor(.primary)
                        Text(settings.speedUnit)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: Best 0-60

    private var best060Card: some View {
        InstrumentCard {
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(Color.orange)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Best 0-60 \(settings.speedUnit) time")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    if let t = stats.best060Time {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(String(format: "%.2f", t))
                                .font(.largeTitle).fontWeight(.bold)
                                .foregroundColor(.primary)
                            Text("sec")
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                    } else {
                        Text("—")
                            .font(.largeTitle).fontWeight(.bold)
                            .foregroundColor(.secondary)
                    }
                }
                Spacer()
                StatInfoButton(entry: StatInfo.zeroToSixty)
            }
        }
    }

    // MARK: Maneuvers Grid

    private var maneuvorsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            InstrumentStatCell(
                icon: "arrow.turn.up.left", iconColor: .blue,
                label: "Left Turns", value: "\(stats.totalLeftTurns)", unit: "",
                info: StatInfo.leftTurns
            )
            InstrumentStatCell(
                icon: "arrow.turn.up.right", iconColor: .orange,
                label: "Right Turns", value: "\(stats.totalRightTurns)", unit: "",
                info: StatInfo.rightTurns
            )
            InstrumentStatCell(
                icon: "hand.raised.fill", iconColor: .red,
                label: "Brake Events", value: "\(stats.totalBrakeEvents)", unit: "",
                info: StatInfo.brakeEvents
            )
            InstrumentStatCell(
                icon: "arrow.left.arrow.right", iconColor: .green,
                label: "Lane Changes", value: "\(stats.totalLaneChanges)", unit: "",
                info: StatInfo.laneChanges
            )
        }
    }

    // MARK: Performance Grid

    private var performanceGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            InstrumentStatCell(
                icon: "arrow.down.circle.fill", iconColor: .red,
                label: "Max Deceleration",
                value: String(format: "%.1f", stats.overallMaxDeceleration),
                unit: "m/s²",
                info: StatInfo.maxDeceleration
            )
            InstrumentStatCell(
                icon: "arrow.up.circle.fill", iconColor: .green,
                label: "Max Acceleration",
                value: String(format: "%.1f", stats.overallMaxAcceleration),
                unit: "m/s²",
                info: StatInfo.maxAcceleration
            )
            InstrumentStatCell(
                icon: "circle.circle.fill", iconColor: .orange,
                label: "Peak G-Force",
                value: String(format: "%.2f", stats.overallPeakGForce),
                unit: "G",
                info: StatInfo.peakGForce
            )
            InstrumentStatCell(
                icon: "arrow.triangle.2.circlepath", iconColor: .cyan,
                label: "Top Corner Speed",
                value: String(format: "%.0f", settings.speedValue(stats.overallTopCornerSpeed)),
                unit: settings.speedUnit,
                info: StatInfo.cornerSpeed
            )
        }
    }

    // MARK: More Stats Grid

    private var moreStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            InstrumentStatCell(
                icon: "car.fill", iconColor: .blue,
                label: "Total Trips", value: "\(stats.totalTrips)", unit: ""
            )
            InstrumentStatCell(
                icon: "stop.circle.fill", iconColor: .secondary,
                label: "Total Stops", value: "\(stats.totalStops)", unit: ""
            )
            InstrumentStatCell(
                icon: "road.lanes", iconColor: .green,
                label: "Avg Trip Length",
                value: String(format: "%.1f", settings.distanceValue(stats.avgTripLengthMeters)),
                unit: settings.distanceUnit
            )
            InstrumentStatCell(
                icon: "clock.arrow.circlepath", iconColor: .orange,
                label: "Total Duration",
                value: formatDuration(stats.totalDuration),
                unit: ""
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
                .tint(.blue)
            }
        }
    }

    // MARK: Achievements Section

    private var achievementsSection: some View {
        InstrumentCard {
            VStack(spacing: 12) {
                // Summary row
                HStack(spacing: 16) {
                    HStack(spacing: 6) {
                        Image(systemName: "trophy.fill").foregroundColor(.yellow)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(achievementManager.unlockedAchievements.count)")
                                .font(.title3).fontWeight(.bold).foregroundColor(.primary)
                            Text("Unlocked").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Divider().frame(height: 32)
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.fill").foregroundColor(.blue)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("\(achievementManager.achievements.count)")
                                .font(.title3).fontWeight(.bold).foregroundColor(.primary)
                            Text("Total").font(.caption).foregroundColor(.secondary)
                        }
                    }
                    Spacer()
                    NavigationLink(destination: AchievementsView()) {
                        Text("View All")
                            .font(.subheadline).fontWeight(.semibold)
                            .foregroundColor(.blue)
                    }
                }

                // Most recent unlocked achievements (up to 3)
                let recent = achievementManager.unlockedAchievements.prefix(3)
                if !recent.isEmpty {
                    Divider()
                    VStack(spacing: 8) {
                        ForEach(Array(recent), id: \.id) { achievement in
                            achievementRow(achievement)
                        }
                    }
                }
            }
        }
    }

    // MARK: Achievements Row

    @ViewBuilder
    private func achievementRow(_ achievement: Achievement) -> some View {
        // Try to find the source drive locally first (it's already in
        // driveManager.drives since the unlock came from a drive save).
        let sourceDrive: Drive? = {
            guard let id = achievement.sourceDriveId else { return nil }
            return driveManager.drives.first(where: { $0.id == id })
        }()

        let rowContent = HStack(spacing: 10) {
            Image(systemName: achievement.icon)
                .font(.title3)
                .foregroundColor(achievement.category.color)
            VStack(alignment: .leading, spacing: 1) {
                Text(achievement.title)
                    .font(.subheadline).fontWeight(.semibold)
                    .foregroundColor(.primary)
                Text(achievement.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if achievement.sourceDriveId != nil {
                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundColor(.green)
            }
        }
        .contentShape(Rectangle())

        if let sourceDrive {
            NavigationLink(destination: DriveDetailView(drive: sourceDrive)) {
                rowContent
            }
            .buttonStyle(.plain)
        } else if let driveId = achievement.sourceDriveId {
            // Source drive is on the server but not in the local cache yet.
            // Open a one-shot detail view that lazily fetches it.
            NavigationLink(destination: RemoteDriveDetailLoader(driveId: driveId)) {
                rowContent
            }
            .buttonStyle(.plain)
        } else {
            rowContent
        }
    }

    // MARK: Settings Section

    private var settingsSection: some View {
        InstrumentCard {
            VStack(spacing: 0) {
                // Keep Screen On
                Toggle(isOn: $settings.keepScreenOn) {
                    HStack(spacing: 10) {
                        Image(systemName: "sun.max.fill")
                            .foregroundColor(.yellow)
                            .frame(width: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Keep Screen On While Recording")
                                .font(.subheadline).foregroundColor(.primary)
                            Text("Prevents sleep during active drives")
                                .font(.caption).foregroundColor(.secondary)
                        }
                    }
                }
                .tint(.blue)

                Divider().padding(.vertical, 12)

                // Unit System
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "ruler.fill")
                            .foregroundColor(.orange)
                            .frame(width: 20)
                        Text("Units").font(.subheadline).foregroundColor(.primary)
                    }
                    Picker("Unit System", selection: $settings.unitSystem) {
                        ForEach(UnitSystem.allCases) { system in
                            Text(system.displayName).tag(system)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                Divider().padding(.vertical, 12)

                // Appearance
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Image(systemName: "circle.lefthalf.filled")
                            .foregroundColor(.purple)
                            .frame(width: 20)
                        Text("Appearance").font(.subheadline).foregroundColor(.primary)
                    }
                    Picker("Color Scheme", selection: $settings.preferredColorScheme) {
                        ForEach(AppColorScheme.allCases) { scheme in
                            Text(scheme.displayName).tag(scheme)
                        }
                    }
                    .pickerStyle(.segmented)
                }
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
            .background(Color(.systemGray6))
            .cornerRadius(12)
        }
        .disabled(isDeletingAccount)
        .padding(.top, 8)
    }

    private var signOutButton: some View {
        Button(role: .destructive) {
            AuthManager.shared.signOut()
        } label: {
            Text("Sign Out")
                .fontWeight(.semibold)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
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
    
    private func selectCar(_ carId: String) {
        guard var profile = profileManager.profile else { return }
        profile.selectCar(id: carId)
        profileManager.saveProfile(profile)
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
                                .foregroundColor(.blue)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.blue.opacity(0.2))
                                .cornerRadius(8)
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
        .onTapGesture {
            if !showingStats {
                onSelect()
            }
        }
    }
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
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.15), lineWidth: 0.5)
        )
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.blue.opacity(0.15))
            Image(systemName: "car.fill")
                .font(.system(size: size * 0.45))
                .foregroundColor(.blue)
        }
    }
}

struct CarStatsRow: View {
    let stats: CarStats
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
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
