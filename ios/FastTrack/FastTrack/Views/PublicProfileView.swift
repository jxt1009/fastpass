import SwiftUI

struct PublicProfileView: View {
    let username: String

    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var apiService: APIService
    @State private var profile: PublicProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isFollowing = false
    @State private var zoomedAvatar: AvatarZoomTarget?
    @State private var followNavigation: FollowDestination?

    private var isOwnProfile: Bool {
        profileManager.profile?.username == username
    }

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
        .navigationDestination(item: $followNavigation) { destination in
            switch destination {
            case .followers(let username):
                FollowersListView(username: username)
            case .following(let username):
                FollowingListView(username: username)
            }
        }
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
                narrowHeader(profile)

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

    // MARK: - Narrow header

    private func narrowHeader(_ profile: PublicProfile) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Button {
                presentAvatarZoom(profile)
            } label: {
                avatarView(profile)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 4) {
                Text(displayName(profile))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text("@\(profile.username)")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)

                    if !bioLine(profile).isEmpty {
                        Text("·")
                            .font(.subheadline)
                            .foregroundStyle(.tertiary)
                        Text(bioLine(profile))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }

                    Spacer(minLength: 0)
                }

                HStack(spacing: 14) {
                    Button {
                        followNavigation = .followers(profile.username)
                    } label: {
                        Text("\(profile.followerCount) Followers")
                            .font(.caption)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)

                    Button {
                        followNavigation = .following(profile.username)
                    } label: {
                        Text("\(profile.followingCount) Following")
                            .font(.caption)
                            .foregroundColor(.primary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer(minLength: 8)

            if !isOwnProfile {
                followButton
            }
        }
    }

    @ViewBuilder
    private func avatarView(_ profile: PublicProfile) -> some View {
        if !profile.avatarURL.isEmpty, let url = URL(string: profile.avatarURL) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().scaledToFill()
                default:
                    avatarFallback(initial: String(profile.username.prefix(1)))
                }
            }
            .frame(width: 56, height: 56)
            .clipShape(Circle())
            .overlay(
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 0.5)
            )
        } else {
            avatarFallback(initial: String(profile.username.prefix(1)))
                .frame(width: 56, height: 56)
        }
    }

    private var followButton: some View {
        FollowButton(
            isFollowing: $isFollowing,
            username: username,
            isSelf: false,
            onError: { message in
                ToastManager.shared.show(ToastMessage(text: message))
            }
        )
    }

    // MARK: - Bio helpers

    private func displayName(_ profile: PublicProfile) -> String {
        profile.fullName.isEmpty ? profile.username : profile.fullName
    }

    private func bioLine(_ profile: PublicProfile) -> String {
        // The display name already includes `fullName` as the headline
        // when present (see `displayName(_:)`); keep this secondary line
        // strictly to non-redundant context like country.
        profile.country
    }

    // MARK: - Avatar fallback

    private func avatarFallback(initial: String) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [.ftBlue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text(initial.uppercased())
                .font(.title3)
                .fontWeight(.bold)
                .foregroundStyle(.white)
        }
    }

    // MARK: - Garage + per-car stats parsing

    private func decodedGarage(from profile: PublicProfile) -> [UserCar] {
        GarageBlob.decode(profile.garage)
    }

    /// Returns the `CarStats` for a given car id by parsing the raw
    /// `car_stats_data` JSON blob the server stores on each user. Returns
    /// nil if the blob is missing/empty/malformed or the car is not in
    /// the blob.
    @available(*, unavailable, message: "Decode the blob once via PublicProfileStatsLookup.byCarId(blob:) and look up by id.")
    private func statsForCar(id: String, blob: String?) -> CarStats? { nil }

    private func presentAvatarZoom(_ profile: PublicProfile) {
        let url: URL? = profile.avatarURL.isEmpty
            ? nil
            : URL(string: profile.avatarURL)
        zoomedAvatar = AvatarZoomTarget(url: url)
    }

    // MARK: - Data Loading

    private func loadProfile() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await apiService.fetchPublicProfile(username: username)
            profile = loaded
            isFollowing = loaded.isFollowedByMe
        } catch APIError.serverError(404) {
            errorMessage = "This profile is private or doesn't exist."
        } catch {
            errorMessage = error.diagnosticDescription
        }
        isLoading = false
    }
}

private enum FollowDestination: Hashable {
    case followers(String)
    case following(String)
}

#Preview {
    let apiService = APIService()
    let authManager = AuthManager(apiService: apiService)
    apiService.authManager = authManager
    return NavigationStack {
        PublicProfileView(username: "fastdriver99")
            .environmentObject(ProfileManager(apiService: apiService))
            .environmentObject(AppSettings(apiService: apiService))
            .environmentObject(apiService)
    }
}
