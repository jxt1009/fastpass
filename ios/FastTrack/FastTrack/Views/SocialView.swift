import SwiftUI

struct SocialView: View {
    @EnvironmentObject var profileManager: ProfileManager

    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var selectedCategory: LeaderboardCategory = .topSpeed
    @State private var selectedScope: LeaderboardScope = .global
    @State private var selectedPeriod: LeaderboardPeriod = .allTime
    @State private var committedCarFilter: String = ""
    @State private var draftCarFilter: String = ""
    @State private var showingCarFilterSheet = false

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
                    NavigationLink(destination: NotificationsView()) {
                        NotificationsBell(manager: NotificationsManager.shared)
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(destination: FindPeopleView()) {
                        Label("Find People", systemImage: "person.badge.plus")
                    }
                }
            }
            .task(id: queryKey) { await loadLeaderboard() }
            .refreshable { await loadLeaderboard() }
            .sheet(isPresented: $showingCarFilterSheet) {
                carFilterSheet
            }
        }
    }

    // MARK: - Filter Bar

    private var filterBar: some View {
        VStack(spacing: 8) {
            Picker("Category", selection: $selectedCategory) {
                ForEach(LeaderboardCategory.allCases, id: \.self) { cat in
                    Label(cat.displayName, systemImage: cat.icon).tag(cat)
                }
            }
            .pickerStyle(.segmented)

            HStack(spacing: 8) {
                Button {
                    selectedScope = selectedScope.quickToggle
                } label: {
                    LeaderboardQuickFilterChip(
                        icon: "person.2",
                        title: selectedScope.displayName,
                        accent: selectedScope == .following
                    )
                }
                .buttonStyle(.plain)

                Button {
                    selectedPeriod = selectedPeriod.nextQuickCycle
                } label: {
                    LeaderboardQuickFilterChip(
                        icon: "clock",
                        title: selectedPeriod.displayName,
                        accent: selectedPeriod != .allTime
                    )
                }
                .buttonStyle(.plain)

                Button {
                    draftCarFilter = committedCarFilter
                    showingCarFilterSheet = true
                } label: {
                    LeaderboardQuickFilterChip(
                        icon: "magnifyingglass",
                        title: committedCarFilter.isEmpty ? "Any Car" : committedCarFilter,
                        accent: !committedCarFilter.isEmpty
                    )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.ftSurfaceBg)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if isLoading && entries.isEmpty {
            // Full skeleton only on initial/empty load
            VStack(spacing: 0) {
                ForEach(0..<8, id: \.self) { _ in
                    LeaderboardSkeletonRow()
                    Divider().padding(.leading, 76)
                }
            }
            .transition(.opacity)
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
                description: Text(selectedCategory == .best060
                    ? "Complete a drive with a 0–60 mph run to appear here."
                    : "No drives recorded in this category.")
            )
        } else {
            ZStack(alignment: .top) {
                List {
                    if let userEntry = LeaderboardEntry.firstCurrentUserEntry(
                        in: entries,
                        currentUserId: profileManager.profile?.id
                    ) {
                        Section {
                            LeaderboardYourPositionCard(entry: userEntry, category: selectedCategory)
                                .listRowBackground(Color.ftCardBg)
                        }
                    }
                    Section {
                        ForEach(entries) { entry in
                            let isCurrentUserRow = LeaderboardYouMarker.isCurrentUser(
                                entry: entry,
                                currentUserId: profileManager.profile?.id
                            )
                            NavigationLink(destination: PublicProfileView(username: entry.username)) {
                                LeaderboardRow(
                                    entry: entry,
                                    category: selectedCategory,
                                    isCurrentUserRow: isCurrentUserRow
                                )
                            }
                            .listRowBackground(
                                isCurrentUserRow
                                    ? Color.ftBlue.opacity(0.08)
                                    : Color.ftCardBg
                            )
                        }
                    }
                }
                .listStyle(.inset)
                .opacity(isLoading ? 0.5 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: isLoading)

                // Subtle refresh indicator while re-fetching with existing data
                if isLoading {
                    ProgressView()
                        .padding(10)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.md))
                        .padding(.top, 12)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Data Loading

    private var queryKey: String {
        "\(selectedCategory.rawValue)-\(selectedScope.rawValue)-\(selectedPeriod.rawValue)-\(committedCarFilter)"
    }

    private var carFilterSheet: some View {
        NavigationStack {
            Form {
                Section("Car Make + Model") {
                    TextField("Example: Tesla Model 3", text: $draftCarFilter)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                    Text("Leave empty to include all cars.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Filter Cars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Clear") {
                        draftCarFilter = ""
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        committedCarFilter = draftCarFilter.trimmingCharacters(in: .whitespacesAndNewlines)
                        showingCarFilterSheet = false
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.height(220), .medium])
    }

    private func loadLeaderboard() async {
        withAnimation(.easeInOut(duration: 0.15)) { isLoading = true }
        errorMessage = nil
        // Parse committed car filter: first word = make, rest = model
        let parts = committedCarFilter.split(separator: " ", maxSplits: 1)
        let make = parts.count > 0 ? String(parts[0]) : ""
        let model = parts.count > 1 ? String(parts[1]) : ""
        do {
            let fetched = try await APIService.shared.fetchLeaderboard(
                category: selectedCategory,
                scope: selectedScope,
                period: selectedPeriod,
                carMake: make,
                carModel: model
            )
            withAnimation(.easeInOut(duration: 0.25)) {
                entries = fetched
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        withAnimation { isLoading = false }
    }
}

private struct LeaderboardQuickFilterChip: View {
    let icon: String
    let title: String
    let accent: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(title)
                .font(.caption)
                .lineLimit(1)
        }
        .foregroundStyle(accent ? Color.ftBlue : .secondary)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(accent ? Color.ftBlue.opacity(0.12) : Color.ftCardBg)
        )
    }
}

private struct LeaderboardYourPositionCard: View {
    let entry: LeaderboardEntry
    let category: LeaderboardCategory

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Your Position")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("#\(entry.rank)")
                    .font(.title3)
                    .fontWeight(.bold)
                    .monospacedDigit()
                Text(entry.carDisplayStringWithNickname)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(category.formattedValue(entry.value))
                .font(.headline)
                .monospacedDigit()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Leaderboard Row

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let category: LeaderboardCategory
    let isCurrentUserRow: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            Text("#\(entry.rank)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(rankColor)
                .frame(width: 32, alignment: .leading)

            // Car photo thumbnail (40pt, rounded) — falls back to tinted car icon
            CarPhotoView(
                car: UserCar(
                    id: entry.carId ?? entry.carKey,
                    make: entry.carMake,
                    model: entry.carModel,
                    year: entry.carYear,
                    trim: entry.carTrim ?? "",
                    nickname: entry.carNickname ?? "",
                    photoUrl: entry.carPhotoUrl
                ),
                url: entry.carPhotoUrl.flatMap { $0.isEmpty ? nil : URL(string: $0) },
                cornerRadius: 6,
                size: 40
            )

            // Car info (primary) + username (supporting)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.carDisplayStringWithNickname)
                        .font(.body)
                        .fontWeight(isCurrentUserRow ? .semibold : .regular)
                        .lineLimit(1)
                    if isCurrentUserRow {
                        BadgePill("You", style: .you)
                    }
                }
                HStack(spacing: 6) {
                    Text("@\(entry.username)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    if !entry.country.isEmpty {
                        Text("·")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                        Text(entry.country)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }

            Spacer(minLength: 4)

            // Stat value
            Text(category.formattedValue(entry.value))
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundStyle(.primary)
                .monospacedDigit()
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
        .environmentObject(ProfileManager.shared)
}
