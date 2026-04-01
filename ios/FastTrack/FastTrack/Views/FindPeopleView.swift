import SwiftUI

struct FindPeopleView: View {
    @StateObject private var profileManager = ProfileManager.shared

    @State private var query = ""
    @State private var results: [UserSearchResult] = []
    @State private var isLoading = false
    @State private var hasSearched = false
    @State private var errorMessage: String?

    private var currentUsername: String? { profileManager.profile?.username }

    var body: some View {
        List {
            if isLoading {
                HStack {
                    Spacer()
                    ProgressView()
                    Spacer()
                }
                .listRowBackground(Color.clear)
            } else if let error = errorMessage {
                ContentUnavailableView("Error", systemImage: "wifi.slash", description: Text(error))
                    .listRowBackground(Color.clear)
            } else if hasSearched && results.isEmpty {
                ContentUnavailableView(
                    "No Users Found",
                    systemImage: "person.slash",
                    description: Text("No public profiles match " + query + ".")
                )
                .listRowBackground(Color.clear)
            } else if !hasSearched {
                ContentUnavailableView(
                    "Find People",
                    systemImage: "person.2.fill",
                    description: Text("Search by username or name to find and follow other drivers.")
                )
                .listRowBackground(Color.clear)
            } else {
                ForEach($results) { $result in
                    NavigationLink(destination: PublicProfileView(username: result.username)) {
                        UserSearchRow(result: $result, currentUsername: currentUsername)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Find People")
        .navigationBarTitleDisplayMode(.large)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by username or name")
        .onSubmit(of: .search) { Task { await runSearch() } }
        .onChange(of: query) { _, new in
            if new.isEmpty {
                results = []
                hasSearched = false
                errorMessage = nil
            }
        }
    }

    private func runSearch() async {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2 else { return }

        isLoading = true
        errorMessage = nil
        do {
            results = try await APIService.shared.searchUsers(query: trimmed)
            hasSearched = true
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Row

private struct UserSearchRow: View {
    @Binding var result: UserSearchResult
    let currentUsername: String?

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.15))
                    .frame(width: 42, height: 42)
                Text(result.username.prefix(1).uppercased())
                    .font(.headline)
                    .foregroundStyle(.blue)
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(result.username)
                        .font(.body)
                    if result.username == currentUsername {
                        Text("You")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue, in: Capsule())
                    }
                }
                if !result.fullName.isEmpty {
                    Text(result.fullName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !result.country.isEmpty {
                    Text(result.country)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Follow/Following button — only for other users
            if result.username != currentUsername {
                FollowToggleButton(result: $result)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Follow Toggle Button

private struct FollowToggleButton: View {
    @Binding var result: UserSearchResult
    @State private var isLoading = false

    var body: some View {
        Button {
            Task { await toggle() }
        } label: {
            if isLoading {
                ProgressView()
                    .frame(width: 80)
            } else if result.isFollowedByMe {
                Text("Following")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color(.systemFill), in: Capsule())
            } else {
                Text("Follow")
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.blue, in: Capsule())
            }
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }

    private func toggle() async {
        isLoading = true
        do {
            if result.isFollowedByMe {
                try await APIService.shared.unfollowUser(username: result.username)
                result.isFollowedByMe = false
            } else {
                try await APIService.shared.followUser(username: result.username)
                result.isFollowedByMe = true
            }
        } catch {
            // Silently ignore — the button state stays unchanged
        }
        isLoading = false
    }
}

#Preview {
    NavigationStack {
        FindPeopleView()
    }
}
