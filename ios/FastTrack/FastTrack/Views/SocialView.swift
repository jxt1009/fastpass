import SwiftUI

struct SocialView: View {
    @EnvironmentObject var profileManager: ProfileManager

    @State private var entries: [LeaderboardEntry] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    @State private var selectedCategory: LeaderboardCategory = .topSpeed
    @State private var selectedScope: LeaderboardScope = .global
    @State private var selectedPeriod: LeaderboardPeriod = .allTime
    @State private var carFilter: String = ""
    @FocusState private var carFilterFocused: Bool

    private var currentSelectedCarId: String? {
        profileManager.profile?.selectedCarId
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
                // Dismiss keyboard button shown whenever the car filter field is focused
                ToolbarItem(placement: .keyboard) {
                    Button("Done") { carFilterFocused = false }
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .task(id: queryKey) { await loadLeaderboard() }
            .refreshable { await loadLeaderboard() }
            // Tap anywhere outside the filter to dismiss keyboard,
            // using simultaneousGesture so NavigationLinks still work
            .simultaneousGesture(
                TapGesture().onEnded { carFilterFocused = false },
                including: carFilterFocused ? .all : .subviews
            )
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

            // Car filter row
            HStack(spacing: 8) {
                Image(systemName: "car.fill")
                    .foregroundStyle(.secondary)
                    .font(.caption)
                TextField("Filter by car (e.g. Tesla Model 3)", text: $carFilter)
                    .font(.subheadline)
                    .autocorrectionDisabled()
                    .submitLabel(.search)
                    .focused($carFilterFocused)
                    .onSubmit { carFilterFocused = false; committedCarFilter = carFilter; Task { await loadLeaderboard() } }
                if !carFilter.isEmpty {
                    Button {
                        carFilter = ""
                        committedCarFilter = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.ftCardBg, in: RoundedRectangle(cornerRadius: 8))
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
                                    isCurrentUserCar: entry.carId != nil
                                        && entry.carId == currentSelectedCarId
                                )
                            }
                            .listRowBackground(
                                (entry.carId != nil && entry.carId == currentSelectedCarId)
                                    ? Color.blue.opacity(0.08)
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
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                        .padding(.top, 12)
                        .transition(.opacity)
                }
            }
        }
    }

    // MARK: - Data Loading

    /// Tracks the committed car filter (updated on submit/clear, not on every keystroke).
    @State private var committedCarFilter: String = ""

    /// A stable key for the `.task(id:)` modifier — changes when any filter changes.
    /// Uses committedCarFilter so mid-typing doesn't trigger fetches.
    private var queryKey: String {
        "\(selectedCategory.rawValue)-\(selectedScope.rawValue)-\(selectedPeriod.rawValue)-\(committedCarFilter)"
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

// MARK: - Leaderboard Row

private struct LeaderboardRow: View {
    let entry: LeaderboardEntry
    let category: LeaderboardCategory
    let isCurrentUserCar: Bool

    var body: some View {
        HStack(spacing: 12) {
            // Rank badge
            Text("#\(entry.rank)")
                .font(.headline)
                .monospacedDigit()
                .foregroundStyle(rankColor)
                .frame(width: 32, alignment: .leading)

            // Car photo thumbnail (40pt, rounded) — falls back to tinted car icon
            CarThumbnail(urlString: entry.carPhotoUrl, size: 40)

            // Car info (primary) + username (supporting)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(entry.carDisplayStringWithNickname)
                        .font(.body)
                        .fontWeight(isCurrentUserCar ? .semibold : .regular)
                        .lineLimit(1)
                    if isCurrentUserCar {
                        Text("You")
                            .font(.caption2)
                            .fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Color.blue, in: Capsule())
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

// MARK: - Car Thumbnail

/// 40-48pt rounded thumbnail for a car photo. Falls back to a tinted
/// car icon when the URL is nil/empty or the image fails to load.
private struct CarThumbnail: View {
    let urlString: String?
    let size: CGFloat

    var body: some View {
        Group {
            if let urlString, !urlString.isEmpty, let url = URL(string: urlString) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image.resizable().scaledToFill()
                    default:
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.blue.opacity(0.15))
            Image(systemName: "car.fill")
                .foregroundStyle(.blue)
                .font(.system(size: size * 0.5))
        }
    }
}

#Preview {
    SocialView()
        .environmentObject(ProfileManager.shared)
}
