import SwiftUI

struct SocialView: View {
    @StateObject private var profileManager = ProfileManager.shared

    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var selectedCategory: LeaderboardCategory = .topSpeed
    @State private var selectedScope: LeaderboardScope = .global
    @State private var selectedPeriod: LeaderboardPeriod = .allTime

    private var currentUsername: String? {
        profileManager.profile?.username
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                Divider()
                content
            }
            .navigationTitle("Leaderboard")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: FindPeopleView()) {
                        Label("Find People", systemImage: "person.badge.plus")
                    }
                }
            }
            .task(id: queryKey) { await loadLeaderboard() }
            .refreshable { await loadLeaderboard() }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            // Category picker
            Picker("Category", selection: $selectedCategory) {
                ForEach(LeaderboardCategory.allCases, id: \.self) { cat in
                    Label(cat.displayName, systemImage: cat.icon).tag(cat)
                }
            }
            .pickerStyle(.segmented)

            // Scope + Period row
            HStack {
                Picker("Scope", selection: $selectedScope) {
                    ForEach(LeaderboardScope.allCases, id: \.self) { scope in
                        Text(scope.displayName).tag(scope)
                    }
                }
                .pickerStyle(.segmented)

                Picker("Period", selection: $selectedPeriod) {
                    ForEach(LeaderboardPeriod.allCases, id: \.self) { period in
                        Text(period.displayName).tag(period)
                    }
                }
                .pickerStyle(.segmented)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && entries.isEmpty {
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let error = errorMessage, entries.isEmpty {
            ContentUnavailableView(
                "Couldn't Load",
                systemImage: "wifi.slash",
                description: Text(error)
            )
        } else if entries.isEmpty {
            ContentUnavailableView(
                "No Data Yet",
                systemImage: "chart.bar.xaxis",
                description: Text("No drives recorded in this category.")
            )
        } else {
            List {
                if selectedScope == .following {
                    Section {
                        Text("Showing you + everyone you follow")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(entries) { entry in
                        NavigationLink(destination: PublicProfileView(username: entry.username)) {
                            LeaderboardRow(
                                entry: entry,
                                category: selectedCategory,
                                isCurrentUser: entry.username == currentUsername
                            )
                        }
                        .listRowBackground(
                            entry.username == currentUsername
                                ? Color.blue.opacity(0.08)
                                : Color(.systemBackground)
                        )
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    // MARK: - Data Loading

    /// A stable key for the `.task(id:)` modifier — changes whenever any filter changes.
    private var queryKey: String {
        "\(selectedCategory.rawValue)-\(selectedScope.rawValue)-\(selectedPeriod.rawValue)"
    }

    private func loadLeaderboard() async {
        isLoading = true
        errorMessage = nil
        do {
            entries = try await APIService.shared.fetchLeaderboard(
                category: selectedCategory,
                scope: selectedScope,
                period: selectedPeriod
            )
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Leaderboard Row

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let category: LeaderboardCategory
    let isCurrentUser: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            Text("#\(entry.rank)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(rankColor)
                .frame(width: 40, alignment: .leading)

            // User info
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.username)
                        .font(.body)
                        .fontWeight(isCurrentUser ? .semibold : .regular)
                    if isCurrentUser {
                        Text("You")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue, in: Capsule())
                    }
                }
                if !entry.country.isEmpty {
                    Text(entry.country)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            // Stat value
            Text(category.formattedValue(entry.value))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
        }
        .padding(.vertical, 2)
    }

    private var rankColor: Color {
        switch entry.rank {
        case 1: return .yellow
        case 2: return Color(white: 0.7)
        case 3: return Color(red: 0.8, green: 0.5, blue: 0.2)
        default: return .secondary
        }
    }
}

#Preview {
    SocialView()
}
