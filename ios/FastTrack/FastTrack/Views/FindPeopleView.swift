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
        .scrollContentBackground(.hidden)
        .background(Color.ftSurfaceBg.ignoresSafeArea())
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

    private func avatarCircle(initial: String) -> some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [.ftBlue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
                .frame(width: 42, height: 42)
            Text(initial)
                .font(.headline)
                .foregroundStyle(.white)
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            // Avatar
            Group {
                if !result.avatarURL.isEmpty, let url = URL(string: result.avatarURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                                .frame(width: 42, height: 42)
                                .clipShape(Circle())
                        default:
                            avatarCircle(initial: result.username.prefix(1).uppercased())
                        }
                    }
                } else {
                    avatarCircle(initial: result.username.prefix(1).uppercased())
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text("@\(result.username)")
                        .font(.body)
                    if result.username == currentUsername {
                        Text("You")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.ftBlue, in: Capsule())
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

            FollowButton(
                isFollowing: Binding(
                    get: { result.isFollowedByMe },
                    set: { result.isFollowedByMe = $0 }
                ),
                username: result.username,
                isSelf: result.username == currentUsername,
                onError: { message in
                    ToastManager.shared.show(ToastMessage(text: message))
                }
            )
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    NavigationStack {
        FindPeopleView()
    }
}
