import SwiftUI

struct FindPeopleView: View {
    @EnvironmentObject var apiService: APIService
    @EnvironmentObject var profileManager: ProfileManager

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
        .background(Color.ftBgGradient, ignoresSafeAreaEdges: .all)
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
            results = try await apiService.searchUsers(query: trimmed)
            hasSearched = true
        } catch {
            errorMessage = error.diagnosticDescription
        }
        isLoading = false
    }
}

// MARK: - Row

private struct UserSearchRow: View {
    @Binding var result: UserSearchResult
    let currentUsername: String?

    var body: some View {
        UserRow(
            avatarSize: 42,
            isYou: result.username == currentUsername
        ) {
            // Avatar
            Group {
                if !result.avatarURL.isEmpty, let url = URL(string: result.avatarURL) {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        default:
                            avatarPlaceholder
                        }
                    }
                } else {
                    avatarPlaceholder
                }
            }
            .clipShape(Circle())
        } primaryContent: {
            Text("@\(result.username)").font(.body)
        } secondaryContent: {
            VStack(alignment: .leading, spacing: 1) {
                if !result.fullName.isEmpty {
                    Text(result.fullName).font(.caption).foregroundStyle(.secondary)
                }
                if !result.country.isEmpty {
                    Text(result.country).font(.caption).foregroundStyle(.secondary)
                }
            }
        } trailing: {
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
    }

    private var avatarPlaceholder: some View {
        ZStack {
            Circle()
                .fill(LinearGradient(
                    colors: [.ftBlue, .purple],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ))
            Text(result.username.prefix(1).uppercased())
                .font(.headline)
                .foregroundStyle(.white)
        }
    }
}

#Preview {
    let apiService = APIService()
    let authManager = AuthManager(apiService: apiService)
    apiService.authManager = authManager
    return NavigationStack {
        FindPeopleView()
            .environmentObject(apiService)
            .environmentObject(ProfileManager(apiService: apiService))
    }
}
