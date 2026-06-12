import SwiftUI

// MARK: - Followers list
//
// Tapping the "Followers" count on a public profile pushes this view. It
// fetches `/api/v1/users/:username/followers` once on appear and renders
// each row as a navigation link to the follower's `PublicProfileView`.

struct FollowersListView: View {
    let username: String
    @EnvironmentObject var apiService: APIService

    var body: some View {
        FollowListView(
            username: username,
            title: "Followers",
            fetcher: { try await apiService.fetchFollowers(username: $0) }
        )
    }
}

// MARK: - Following list

struct FollowingListView: View {
    let username: String
    @EnvironmentObject var apiService: APIService

    var body: some View {
        FollowListView(
            username: username,
            title: "Following",
            fetcher: { try await apiService.fetchFollowing(username: $0) }
        )
    }
}

// MARK: - Shared implementation

private struct FollowListView: View {
    let username: String
    let title: String
    let fetcher: (String) async throws -> [FollowUserEntry]

    @State private var users: [FollowUserEntry] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = errorMessage {
                ContentUnavailableView(
                    "Unable to Load",
                    systemImage: "wifi.slash",
                    description: Text(error)
                )
            } else if users.isEmpty {
                ContentUnavailableView(
                    "No \(title)",
                    systemImage: "person.2",
                    description: Text("This list is empty.")
                )
            } else {
                List(users) { user in
                    NavigationLink(destination: PublicProfileView(username: user.username)) {
                        FollowUserRow(user: user)
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
                .background(Color.ftSurfaceBg.ignoresSafeArea())
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        do {
            users = try await fetcher(username)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

private struct FollowUserRow: View {
    let user: FollowUserEntry

    var body: some View {
        UserRow(
            avatarSize: 40
        ) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [.ftBlue, .purple],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                Text(String(user.username.prefix(1)).uppercased())
                    .font(.headline)
                    .foregroundColor(.white)
            }
            .clipShape(Circle())
        } primaryContent: {
            Text("@\(user.username)").font(.body)
        } secondaryContent: {
            if !user.country.isEmpty {
                Text(user.country).font(.caption).foregroundStyle(.secondary)
            }
        } trailing: {
            EmptyView()
        }
    }
}
