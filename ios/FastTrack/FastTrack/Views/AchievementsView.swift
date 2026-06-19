import SwiftUI

struct AchievementsView: View {
    @EnvironmentObject var achievementManager: AchievementManager
    @EnvironmentObject var driveManager: DriveManager
    @EnvironmentObject var settings: AppSettings
    @State private var selectedCategory: AchievementCategory?
    @State private var showingUnlockedOnly = false
    @State private var selectedAchievement: Achievement?
    
    private var filteredAchievements: [Achievement] {
        var achievements = showingUnlockedOnly ? achievementManager.unlockedAchievements : achievementManager.achievements
        
        if let category = selectedCategory {
            achievements = achievements.filter { $0.category == category }
        }
        
        return achievements.sorted { first, second in
            // Sort by: unlocked first, then by progress, then alphabetically
            if first.isUnlocked != second.isUnlocked {
                return first.isUnlocked && !second.isUnlocked
            }
            if first.progress != second.progress {
                return first.progress > second.progress
            }
            return first.title < second.title
        }
    }
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Stats Header
                statsHeader
                
                // Filter Controls
                filterControls
                
                // Achievement Grid
                if filteredAchievements.isEmpty {
                    ContentUnavailableView(
                        showingUnlockedOnly ? "No Unlocked Achievements" : "No Achievements",
                        systemImage: "trophy",
                        description: Text(showingUnlockedOnly ? "Keep driving to unlock achievements!" : "Complete drives to earn achievements")
                    )
                } else {
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())],
                            spacing: Spacing.sm
                        ) {
                            ForEach(filteredAchievements) { achievement in
                                AchievementBadgeCard(achievement: achievement)
                                    .onTapGesture { selectedAchievement = achievement }
                            }
                        }
                        .padding()
                    }
                }
            }
            .background(Color.ftBgGradient, ignoresSafeAreaEdges: .all)
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.inline)
            .accentColor(.ftBlue)
            .onAppear {
                achievementManager.updateProgress(with: driveManager.drives)
            }
            .onChange(of: driveManager.drives) { drives in
                achievementManager.updateProgress(with: drives)
            }
            .sheet(item: $selectedAchievement) { achievement in
                AchievementDetailView(achievement: achievement)
                    .environmentObject(settings)
            }
        }
    }
    
    // MARK: - Stats Header

    private var statsHeader: some View {
        HStack(spacing: 16) {
            Label("\(achievementManager.unlockedAchievements.count) unlocked", systemImage: "trophy.fill")
                .foregroundStyle(Color.ftGold)
            Spacer()
            Label(String(format: "%.0f%%", progressPercentage), systemImage: "chart.line.uptrend.xyaxis")
                .foregroundStyle(Color.ftGreen)
        }
        .font(.subheadline)
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(Color.ftGlassCardFill)
        .overlay(alignment: .bottom) {
            ProgressView(value: progressPercentage / 100.0)
                .progressViewStyle(LinearProgressViewStyle(tint: Color.ftGreen))
                .padding(.horizontal)
        }
    }
    
    private var progressPercentage: Double {
        guard !achievementManager.achievements.isEmpty else { return 0 }
        return Double(achievementManager.unlockedAchievements.count) / Double(achievementManager.achievements.count) * 100
    }
    
    // MARK: - Filter Controls
    
    private var filterControls: some View {
        VStack(spacing: 12) {
            // Category Filter
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    CategoryFilterChip(
                        title: "All",
                        isSelected: selectedCategory == nil,
                        color: .gray
                    ) {
                        selectedCategory = nil
                    }
                    
                    ForEach(AchievementCategory.allCases, id: \.self) { category in
                        CategoryFilterChip(
                            title: category.rawValue,
                            isSelected: selectedCategory == category,
                            color: category.color
                        ) {
                            selectedCategory = selectedCategory == category ? nil : category
                        }
                    }
                }
                .padding(.horizontal)
            }
            
            // Show/Hide Filter
            InstrumentCard {
                Toggle("Show unlocked only", isOn: $showingUnlockedOnly)
                    .tint(.ftBlue)
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
    }
}

// MARK: - Supporting Views
struct CategoryFilterChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundStyle(isSelected ? color : .secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Color.ftGlassCardFill)
                .overlay(
                    Group {
                        if isSelected {
                            Capsule().fill(color.opacity(0.20))
                            Capsule().stroke(color.opacity(0.30), lineWidth: 1)
                        } else {
                            Capsule().stroke(Color.ftGlassCardStroke, lineWidth: 1)
                        }
                    }
                )
                .clipShape(Capsule())
        }
    }
}

struct AchievementDetailView: View {
    let achievement: Achievement
    @EnvironmentObject var settings: AppSettings
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Icon
                RoundedRectangle(cornerRadius: Radius.xl)
                    .fill(achievement.category.color.opacity(0.20))
                    .frame(width: 64, height: 64)
                    .overlay(
                        Image(systemName: achievement.icon)
                            .font(.system(size: 28, weight: .semibold))
                            .foregroundStyle(achievement.category.color)
                    )
                
                // Title and description
                VStack(spacing: 8) {
                    Text(achievement.title)
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text(achievement.description)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                }
                
                // Status
                VStack(spacing: 12) {
                    if achievement.isUnlocked {
                        VStack(spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(Color.ftGreen)
                                Text("Achievement Unlocked!")
                                    .fontWeight(.medium)
                                    .foregroundColor(Color.ftGreen)
                            }
                            .font(.headline)
                            
                            if let unlockedDate = achievement.unlockedDate {
                                Text("Completed on \(unlockedDate.formatted(date: .complete, time: .shortened))")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        }
                    } else {
                        VStack(spacing: 8) {
                            Text("Progress")
                                .font(.headline)
                            
                            Text(achievement.progressText(with: settings))
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            GradientProgressBar(
                                value: achievement.progress,
                                range: 0...1,
                                size: .hero
                            )
                            .padding(.horizontal, Spacing.lg)
                        }
                    }
                }
                
                // Category badge
                HStack {
                    Image(systemName: achievement.category.icon)
                    Text(achievement.category.rawValue)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(achievement.category.color.opacity(0.2))
                .foregroundColor(achievement.category.color)
                .cornerRadius(Radius.lg)
                
                Spacer()
            }
            .padding()
            .background(Color.ftBgGradient, ignoresSafeAreaEdges: .all)
            .navigationTitle("Achievement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationBackground(Color.ftBgGradient)
    }
}

// MARK: - Preview

#Preview {
    let apiService = APIService()
    let authManager = AuthManager(apiService: apiService)
    apiService.authManager = authManager
    return AchievementsView()
        .environmentObject(DriveManager(
            authManager: authManager,
            profileManager: ProfileManager(apiService: apiService),
            settings: AppSettings(apiService: apiService),
            apiService: apiService,
            carStatsManager: CarStatsManager(apiService: apiService),
            achievementManager: AchievementManager()
        ))
        .environmentObject(AppSettings(apiService: apiService))
        .environmentObject(AchievementManager())
}