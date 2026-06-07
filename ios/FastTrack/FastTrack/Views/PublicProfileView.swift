import SwiftUI

struct PublicProfileView: View {
    let username: String

    @StateObject private var profileManager = ProfileManager.shared
    @State private var profile: PublicProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isFollowing = false
    @State private var followLoading = false
    @State private var zoomedAvatar: AvatarZoomTarget?

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
            // Narrow header section: avatar | name + bio | follow button.
            // The follow button lives in the header's trailing edge (not
            // below) so the layout reads top-to-bottom as identity →
            // counters → stats → garage.
            Section {
                narrowHeader(profile)
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 12, bottom: 8, trailing: 12))

            // Follower / following counts (tappable)
            Section {
                HStack(spacing: 24) {
                    NavigationLink {
                        FollowersListView(username: profile.username)
                    } label: {
                        countView(value: profile.followerCount, label: "Followers")
                    }
                    .buttonStyle(.plain)

                    NavigationLink {
                        FollowingListView(username: profile.username)
                    } label: {
                        countView(value: profile.followingCount, label: "Following")
                    }
                    .buttonStyle(.plain)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            // Stats (Top Speed, Best 0-60, Total Distance)
            Section("Stats") {
                ForEach(PublicProfileStats.rows(for: profile)) { row in
                    statRow(
                        icon: row.icon,
                        color: row.color,
                        label: row.label,
                        value: row.value
                    )
                }
            }

            // Garage (per the redesign, read-only with photos + short stats)
            if let garage = decodedGarage(from: profile), !garage.isEmpty {
                Section("Garage") {
                    // Decode the per-car stats blob once for the section
                    // rather than once per row — see PR 4 review thread.
                    let statsByCarId = statsByCarId(blob: profile.carStatsData)
                    ForEach(garage) { car in
                        PublicGarageCard(
                            car: car,
                            stats: statsByCarId[car.id]
                        )
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Narrow header

    private func narrowHeader(_ profile: PublicProfile) -> some View {
        HStack(alignment: .center, spacing: 12) {
            avatarView(profile)
                .onTapGesture { presentAvatarZoom(profile) }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName(profile))
                    .font(.headline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                Text("@\(profile.username)")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                if !bioLine(profile).isEmpty {
                    Text(bioLine(profile))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
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
        Button {
            Task { await toggleFollow() }
        } label: {
            if followLoading {
                ProgressView()
                    .frame(width: 80, height: 28)
            } else {
                Text(isFollowing ? "Following" : "Follow")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(isFollowing ? .secondary : .white)
                    .frame(width: 80, height: 28)
                    .background(
                        isFollowing
                            ? Color(.systemFill)
                            : Color.blue,
                        in: Capsule()
                    )
            }
        }
        .buttonStyle(.plain)
        .disabled(followLoading)
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
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title3)
                .fontWeight(.bold)
                .foregroundColor(.primary)
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .contentShape(Rectangle())
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
                    colors: [.blue, .purple],
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
    @available(*, unavailable, message: "Decode the blob once via statsByCarId(blob:) and look up by id.")
    private func statsForCar(id: String, blob: String?) -> CarStats? { nil }

    /// Decode the per-car stats blob once into a `[carId: CarStats]`
    /// dictionary so the garage section can index by id without
    /// re-parsing the JSON for every row. Returns an empty dictionary
    /// when the blob is missing, empty, or malformed.
    private func statsByCarId(blob: String?) -> [String: CarStats] {
        guard let blob, !blob.isEmpty,
              let data = blob.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: CarStats].self, from: data)
        else { return [:] }
        return decoded
    }

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
            let loaded = try await APIService.shared.fetchPublicProfile(username: username)
            profile = loaded
            isFollowing = loaded.isFollowedByMe
        } catch APIError.serverError(404) {
            errorMessage = "This profile is private or doesn't exist."
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    private func toggleFollow() async {
        followLoading = true
        defer { followLoading = false }
        guard var current = profile else { return }
        do {
            if isFollowing {
                try await APIService.shared.unfollowUser(username: username)
                isFollowing = false
                current = PublicProfile(
                    username: current.username, fullName: current.fullName, country: current.country,
                    avatarURL: current.avatarURL, memberSince: current.memberSince,
                    topSpeed: current.topSpeed, totalDistance: current.totalDistance,
                    driveCount: current.driveCount, best060Time: current.best060Time,
                    followerCount: max(0, current.followerCount - 1),
                    followingCount: current.followingCount,
                    isFollowedByMe: false,
                    garage: current.garage, carStatsData: current.carStatsData
                )
            } else {
                try await APIService.shared.followUser(username: username)
                isFollowing = true
                current = PublicProfile(
                    username: current.username, fullName: current.fullName, country: current.country,
                    avatarURL: current.avatarURL, memberSince: current.memberSince,
                    topSpeed: current.topSpeed, totalDistance: current.totalDistance,
                    driveCount: current.driveCount, best060Time: current.best060Time,
                    followerCount: current.followerCount + 1,
                    followingCount: current.followingCount,
                    isFollowedByMe: true,
                    garage: current.garage, carStatsData: current.carStatsData
                )
            }
            profile = current
        } catch {
            // Silently ignore; state stays unchanged
        }
    }
}

#Preview {
    NavigationStack {
        PublicProfileView(username: "fastdriver99")
    }
}
