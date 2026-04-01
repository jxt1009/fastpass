import SwiftUI

struct PublicProfileView: View {
    let username: String

    @StateObject private var profileManager = ProfileManager.shared
    @State private var profile: PublicProfile?
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var isFollowing = false
    @State private var followLoading = false

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
    }

    // MARK: - Profile Content

    @ViewBuilder
    private func profileContent(_ profile: PublicProfile) -> some View {
        List {
            // Header section
            Section {
                VStack(spacing: 16) {
                    // Avatar placeholder
                    ZStack {
                        Circle()
                            .fill(Color(.systemGray5))
                            .frame(width: 80, height: 80)
                        Text(String(profile.username.prefix(1)).uppercased())
                            .font(.largeTitle)
                            .fontWeight(.bold)
                            .foregroundStyle(.secondary)
                    }

                    VStack(spacing: 4) {
                        if !profile.fullName.isEmpty {
                            Text(profile.fullName)
                                .font(.title3)
                                .fontWeight(.semibold)
                        }
                        if !profile.country.isEmpty {
                            Text(profile.country)
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Text("Member since \(profile.memberSince.formatted(.dateTime.month(.wide).year()))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    // Follower / following counts
                    HStack(spacing: 32) {
                        countView(value: profile.followerCount, label: "Followers")
                        countView(value: profile.followingCount, label: "Following")
                    }

                    // Follow / Unfollow button
                    if !isOwnProfile {
                        Button {
                            Task { await toggleFollow() }
                        } label: {
                            if followLoading {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            } else {
                                Text(isFollowing ? "Following" : "Follow")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 8)
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(isFollowing ? .secondary : .blue)
                        .disabled(followLoading)
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            // Stats section
            Section("Stats") {
                statRow(
                    icon: "speedometer", color: .red,
                    label: "Top Speed",
                    value: String(format: "%.0f mph", profile.topSpeed * 2.23694)
                )
                statRow(
                    icon: "map.fill", color: .blue,
                    label: "Total Distance",
                    value: String(format: "%.1f mi", profile.totalDistance * 0.000621371)
                )
                statRow(
                    icon: "flag.fill", color: .green,
                    label: "Total Drives",
                    value: "\(profile.driveCount)"
                )
                if let best060 = profile.best060Time {
                    statRow(
                        icon: "timer", color: .orange,
                        label: "Best 0-60",
                        value: String(format: "%.2f sec", best060)
                    )
                } else {
                    statRow(
                        icon: "timer", color: .orange,
                        label: "Best 0-60",
                        value: "N/A"
                    )
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    // MARK: - Subviews

    private func countView(value: Int, label: String) -> some View {
        VStack(spacing: 2) {
            Text("\(value)")
                .font(.title2)
                .fontWeight(.bold)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
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
        do {
            if isFollowing {
                try await APIService.shared.unfollowUser(username: username)
                isFollowing = false
                profile = profile.map {
                    PublicProfile(
                        username: $0.username, fullName: $0.fullName, country: $0.country,
                        memberSince: $0.memberSince, topSpeed: $0.topSpeed,
                        totalDistance: $0.totalDistance, driveCount: $0.driveCount,
                        best060Time: $0.best060Time,
                        followerCount: $0.followerCount - 1,
                        followingCount: $0.followingCount,
                        isFollowedByMe: false
                    )
                }
            } else {
                try await APIService.shared.followUser(username: username)
                isFollowing = true
                profile = profile.map {
                    PublicProfile(
                        username: $0.username, fullName: $0.fullName, country: $0.country,
                        memberSince: $0.memberSince, topSpeed: $0.topSpeed,
                        totalDistance: $0.totalDistance, driveCount: $0.driveCount,
                        best060Time: $0.best060Time,
                        followerCount: $0.followerCount + 1,
                        followingCount: $0.followingCount,
                        isFollowedByMe: true
                    )
                }
            }
        } catch {
            // Silently ignore; state stays unchanged
        }
        followLoading = false
    }
}

#Preview {
    NavigationStack {
        PublicProfileView(username: "fastdriver99")
    }
}
