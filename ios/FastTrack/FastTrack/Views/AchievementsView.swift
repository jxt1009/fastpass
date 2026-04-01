import SwiftUI

struct AchievementsView: View {
    @StateObject private var achievementManager = AchievementManager.shared
    @EnvironmentObject var driveManager: DriveManager
    @State private var selectedCategory: AchievementCategory?
    @State private var showingUnlockedOnly = false
    
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
        NavigationView {
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
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                            ForEach(filteredAchievements) { achievement in
                                AchievementCard(achievement: achievement)
                            }
                        }
                        .padding()
                    }
                }
            }
            .navigationTitle("Achievements")
            .navigationBarTitleDisplayMode(.large)
            .onAppear {
                achievementManager.updateProgress(with: driveManager.drives)
            }
            .onChange(of: driveManager.drives) { drives in
                achievementManager.updateProgress(with: drives)
            }
        }
    }
    
    // MARK: - Stats Header
    
    private var statsHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: 20) {
                StatPill(
                    title: "Unlocked",
                    value: "\(achievementManager.unlockedAchievements.count)",
                    icon: "trophy.fill",
                    color: .yellow
                )
                
                StatPill(
                    title: "Total",
                    value: "\(achievementManager.achievements.count)",
                    icon: "target",
                    color: .blue
                )
                
                StatPill(
                    title: "Progress",
                    value: String(format: "%.0f%%", progressPercentage),
                    icon: "chart.line.uptrend.xyaxis",
                    color: .green
                )
            }
            
            // Progress Bar
            ProgressView(value: progressPercentage / 100.0)
                .progressViewStyle(LinearProgressViewStyle(tint: .green))
                .scaleEffect(x: 1, y: 2, anchor: .center)
        }
        .padding()
        .background(Color(.systemGray6))
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
            HStack {
                Toggle("Show unlocked only", isOn: $showingUnlockedOnly)
                    .toggleStyle(SwitchToggleStyle())
                Spacer()
            }
            .padding(.horizontal)
        }
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
    }
}

// MARK: - Supporting Views

struct StatPill: View {
    let title: String
    let value: String
    let icon: String
    let color: Color
    
    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .foregroundColor(color)
                .font(.title2)
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

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
                .foregroundColor(isSelected ? .white : color)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? color : Color(.systemGray6))
                .cornerRadius(20)
        }
    }
}

struct AchievementCard: View {
    let achievement: Achievement
    @State private var showingDetail = false
    
    var body: some View {
        Button {
            showingDetail = true
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                // Header with icon and status
                HStack {
                    Image(systemName: achievement.badgeIcon)
                        .font(.title2)
                        .foregroundColor(achievement.badgeColor)
                        .frame(width: 30)
                    
                    Spacer()
                    
                    if achievement.isUnlocked {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundColor(.green)
                    } else {
                        Text(String(format: "%.0f%%", achievement.progress * 100))
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.secondary)
                    }
                }
                
                // Title and description
                VStack(alignment: .leading, spacing: 4) {
                    Text(achievement.title)
                        .font(.headline)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(achievement.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Progress section
                if !achievement.isUnlocked {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(achievement.progressText)
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        
                        ProgressView(value: achievement.progress)
                            .progressViewStyle(LinearProgressViewStyle(tint: achievement.category.color))
                            .scaleEffect(x: 1, y: 1.5, anchor: .center)
                    }
                } else if let unlockedDate = achievement.unlockedDate {
                    Text("Unlocked \(unlockedDate.formatted(date: .abbreviated, time: .omitted))")
                        .font(.caption2)
                        .foregroundColor(.green)
                        .fontWeight(.medium)
                }
            }
            .padding()
            .frame(height: 140)
            .background(achievement.isUnlocked ? Color(.systemBackground) : Color(.systemGray6))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(achievement.isUnlocked ? achievement.category.color.opacity(0.3) : Color.clear, lineWidth: 2)
            )
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
        .sheet(isPresented: $showingDetail) {
            AchievementDetailView(achievement: achievement)
        }
    }
}

struct AchievementDetailView: View {
    let achievement: Achievement
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 30) {
                // Large icon
                Image(systemName: achievement.badgeIcon)
                    .font(.system(size: 80))
                    .foregroundColor(achievement.badgeColor)
                
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
                                    .foregroundColor(.green)
                                Text("Achievement Unlocked!")
                                    .fontWeight(.medium)
                                    .foregroundColor(.green)
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
                            
                            Text(achievement.progressText)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                            
                            ProgressView(value: achievement.progress)
                                .progressViewStyle(LinearProgressViewStyle(tint: achievement.category.color))
                                .scaleEffect(x: 1, y: 2, anchor: .center)
                                .frame(width: 200)
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
                .cornerRadius(12)
                
                Spacer()
            }
            .padding()
            .navigationTitle("Achievement")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Preview

#Preview {
    AchievementsView()
        .environmentObject(DriveManager())
}