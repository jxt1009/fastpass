import SwiftUI

struct PublicProfileView: View {
    let username: String

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var apiService: APIService
    @EnvironmentObject var profileManager: ProfileManager
    @State private var profile: PublicProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isFollowing = false
    @State private var zoomedAvatar: AvatarZoomTarget?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Profile Unavailable",
                    systemImage: "person.slash",
                    description: Text(error)
                )
            } else if let profile {
                profileContent(profile)
            }
        }
        .navigationTitle(username)
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadProfile() }
        .fullScreenCover(item: $zoomedAvatar) { target in
            AvatarZoomView(url: target.url, image: target.image) {
                zoomedAvatar = nil
            }
        }
    }

    // MARK: - Profile Content

    @ViewBuilder
    private func profileContent(_ profile: PublicProfile) -> some View {
        let garage = decodedGarage(from: profile)
        let statsByCarId = PublicProfileStatsLookup.byCarId(blob: profile.carStatsData)
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.lg) {
                profileHeader(profile)

                aggregateStatsSection(profile)

                if !garage.isEmpty {
                    garageGridSection(garage: garage, profile: profile, statsByCarId: statsByCarId)
                }
            }
            .padding(.horizontal, Spacing.md)
            .padding(.vertical, Spacing.md)
        }
        .background(Color.ftBgGradient, ignoresSafeAreaEdges: .all)
    }

    // MARK: - Profile Header (restored from #125 regression)

    private func profileHeader(_ profile: PublicProfile) -> some View {
        VStack(spacing: Spacing.md) {
            HStack(alignment: .top, spacing: Spacing.md) {
                avatarView(profile)

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    if !profile.fullName.isEmpty {
                        Text(profile.fullName)
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundStyle(.primary)
                    }
                    Text("@\(profile.username)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !profile.country.isEmpty {
                        Label(profile.country, systemImage: "location.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                    FollowButton(
                        isFollowing: $isFollowing,
                        username: profile.username,
                        isSelf: profileManager.profile?.username == profile.username,
                        onError: { ToastManager.shared.show(ToastMessage(text: $0)) }
                    )
                    .padding(.top, Spacing.xs)
                }
            }

            HStack(spacing: Spacing.lg) {
                countStat(label: "Drives", value: profile.driveCount)
                NavigationLink {
                    FollowersListView(username: profile.username)
                } label: {
                    countStat(label: "Followers", value: profile.followerCount)
                }
                .buttonStyle(.plain)
                NavigationLink {
                    FollowingListView(username: profile.username)
                } label: {
                    countStat(label: "Following", value: profile.followingCount)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func avatarView(_ profile: PublicProfile) -> some View {
        let avatarURL = profile.avatarURL.isEmpty ? nil : URL(string: profile.avatarURL)
        return Group {
            if let avatarURL {
                AsyncImage(url: avatarURL) { image in
                    image.resizable().scaledToFill()
                } placeholder: {
                    Circle().fill(Color.ftGlassSurface)
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.ftGlassCardStroke, lineWidth: 2))
                .onTapGesture {
                    zoomedAvatar = AvatarZoomTarget(url: avatarURL)
                }
            } else {
                ZStack {
                    Circle()
                        .fill(LinearGradient(
                            colors: [.ftBlue, .purple],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ))
                    Text(String(profile.username.prefix(1)).uppercased())
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                }
                .frame(width: 80, height: 80)
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.ftGlassCardStroke, lineWidth: 2))
            }
        }
    }

    private func countStat(label: String, value: Int) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.headline)
                .foregroundStyle(.primary)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Aggregate Stats Section

    private func aggregateStatsSection(_ profile: PublicProfile) -> some View {
        LazyVGrid(columns: [
            GridItem(.flexible()), GridItem(.flexible()),
            GridItem(.flexible()), GridItem(.flexible())
        ], spacing: Spacing.sm) {
            InstrumentStatCell(
                icon: "flag.fill", iconColor: .ftGreen,
                label: "Drives",
                value: "\(profile.driveCount)",
                unit: ""
            )
            InstrumentStatCell(
                icon: "map.fill", iconColor: .ftBlue,
                label: "Distance",
                value: String(format: "%.1f", settings.distanceValue(profile.totalDistance)),
                unit: settings.distanceUnit
            )
            InstrumentStatCell(
                icon: "bolt.fill", iconColor: .ftGold,
                label: "Top Speed",
                value: String(format: "%.0f", settings.speedValue(profile.topSpeed)),
                unit: settings.speedUnit
            )
            InstrumentStatCell(
                icon: "timer", iconColor: .ftAmber,
                label: "Best 0-60",
                value: profile.best060Time.map { String(format: "%.2f", $0) } ?? "—",
                unit: profile.best060Time != nil ? "sec" : ""
            )
        }
    }

    // MARK: - Garage Grid Section

    private func garageGridSection(garage: [UserCar], profile: PublicProfile, statsByCarId: [String: CarStats]) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: Spacing.md) {
            ForEach(garage) { car in
                NavigationLink {
                    PublicCarDetailView(
                        username: profile.username,
                        car: car,
                        stats: statsByCarId[car.id],
                        carStatsData: profile.carStatsData
                    )
                } label: {
                    publicCarCard(car: car, stats: statsByCarId[car.id])
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func publicCarCard(car: UserCar, stats: CarStats?) -> some View {
        InstrumentCard(padding: 0) {
            VStack(alignment: .leading, spacing: 0) {
                CarPhotoView(
                    car: car,
                    url: car.photoUrl.flatMap { $0.isEmpty ? nil : URL(string: $0) },
                    cornerRadius: 0
                )
                .frame(maxWidth: .infinity)
                .frame(height: 160)
                .clipped()

                VStack(alignment: .leading, spacing: Spacing.xs) {
                    Text(car.nickname.isEmpty ? car.shortDisplay : car.nickname)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(car.displayString)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    StatsGrid(spacing: 4) {
                        StatMini(title: "Drives", value: "\(stats?.totalDrives ?? 0)")
                        StatMini(
                            title: settings.distanceUnit == "mi" ? "Miles" : "KM",
                            value: String(format: "%.0f", settings.distanceValue(stats?.totalDistance ?? 0))
                        )
                        VStack(spacing: 2) {
                            StatusDot(
                                level: .best,
                                label: stats.map { String(format: "%.0f", settings.speedValue($0.bestTopSpeed)) } ?? "—"
                            )
                            .font(.caption)
                            Text("Top Speed")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        VStack(spacing: 2) {
                            StatusDot(
                                level: .nearBest,
                                label: stats?.bestZeroToSixty.map { String(format: "%.1fs", $0) } ?? "—"
                            )
                            .font(.caption)
                            Text("0-60")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(Spacing.sm)
            }
        }
    }

    // MARK: - Garage + per-car stats parsing

    private func decodedGarage(from profile: PublicProfile) -> [UserCar] {
        GarageBlob.decode(profile.garage)
    }

    // MARK: - Data Loading

    private func loadProfile() async {
        isLoading = true
        errorMessage = nil
        do {
            let p = try await apiService.fetchPublicProfile(username: username)
            profile = p
            isFollowing = p.isFollowedByMe
        } catch APIError.serverError(404) {
            errorMessage = "This profile is private or doesn't exist."
        } catch {
            errorMessage = error.diagnosticDescription
        }
        isLoading = false
    }
}

#Preview {
    let apiService = APIService()
    let authManager = AuthManager(apiService: apiService)
    apiService.authManager = authManager
    return NavigationStack {
        PublicProfileView(username: "fastdriver99")
            .environmentObject(AppSettings(apiService: apiService))
            .environmentObject(apiService)
    }
}
