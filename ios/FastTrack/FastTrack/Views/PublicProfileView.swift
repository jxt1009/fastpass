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
        List {
            Section {
                narrowHeader(profile)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))
            .listRowBackground(Color.ftCardBg)

            // Stats (Top Speed, Best 0-60, Total Distance)
            Section("Stats") {
                ForEach(PublicProfileStats.rows(for: profile, settings: settings)) { row in
                    statRow(
                        icon: row.icon,
                        color: row.color,
                        label: row.label,
                        value: row.value
                    )
                }
            }
            .listRowBackground(Color.ftCardBg)

            // Garage (per the redesign, read-only with photos + short stats).
            // Each card is wrapped in a NavigationLink with .buttonStyle(.plain)
            // so it pushes the read-only PublicCarDetailView for that car
            // without the system disclosure indicator on top of the card's
            // own chevron hint.
            if let garage = decodedGarage(from: profile), !garage.isEmpty {
                Section("Garage") {
                    // Decode the per-car stats blob once for the section
                    // rather than re-parsing the JSON for every row inside
                    // the ForEach.
                    let statsByCarId = PublicProfileStatsLookup.byCarId(blob: profile.carStatsData)
                    ForEach(garage) { car in
                        NavigationLink {
                            PublicCarDetailView(
                                username: profile.username,
                                car: car,
                                stats: statsByCarId[car.id],
                                carStatsData: profile.carStatsData
                            )
                        } label: {
                            PublicGarageCard(
                                car: car,
                                stats: statsByCarId[car.id]
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .listRowBackground(Color.ftCardBg)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color.ftSurfaceBg.ignoresSafeArea())
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

    // MARK: - Subviews (counters + stat rows)

    private func countView(value: Int, label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("\(value)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private func statRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
    }

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

    private func decodedGarage(from profile: PublicProfile) -> [UserCar]? {
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
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private enum FollowDestination: Hashable {
    case followers(String)
    case following(String)
}

#Preview {
    NavigationStack {
        PublicProfileView(username: "fastdriver99")
    }
}
