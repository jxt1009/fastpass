import Foundation
import Combine

// MARK: - Achievement Manager

class AchievementManager: ObservableObject {
    @Published var achievements: [Achievement] = []
    @Published var recentUnlocks: [Achievement] = []

    private let userDefaultsKey = "user_achievements_v2"

    init() {
        loadAchievements()
        setupDefaultAchievements()
    }

    private func setupDefaultAchievements() {
        if achievements.isEmpty {
            achievements = AchievementCatalog.createDefaultAchievements()
            saveAchievements()
        }
    }

    func applyServerUnlocks(_ serverUnlocks: [UserAchievement], catalog: [AchievementCatalogEntry] = []) {
        var updated = achievements
        for server in serverUnlocks {
            guard let idx = updated.firstIndex(where: { $0.id == server.achievementId }) else { continue }
            updated[idx].isUnlocked = true
            if updated[idx].unlockedDate == nil {
                updated[idx].unlockedDate = server.unlockedAt
            }
            if updated[idx].sourceDriveId == nil {
                updated[idx].sourceDriveId = server.sourceDriveId
            }
        }
        if updated.map(\.isUnlocked) != achievements.map(\.isUnlocked) ||
            updated.map(\.sourceDriveId) != achievements.map(\.sourceDriveId) {
            achievements = updated
            saveAchievements()
        }
    }

    func updateProgress(with drives: [Drive]) {
        var hasUpdates = false

        for i in 0..<achievements.count {
            if !achievements[i].isUnlocked {
                let oldProgress = achievements[i].progress
                achievements[i].progress = calculateProgress(for: achievements[i], with: drives)

                if achievements[i].progress >= 1.0 && !achievements[i].isUnlocked {
                    achievements[i].isUnlocked = true
                    achievements[i].unlockedDate = Date()
                    recentUnlocks.append(achievements[i])
                    hasUpdates = true
                }
            }
        }

        if hasUpdates {
            saveAchievements()
        }
    }

    private func calculateProgress(for achievement: Achievement, with drives: [Drive]) -> Double {
        switch achievement.requirement.type {
        case .maxSpeed:
            let maxSpeed = drives.map(\.maxSpeed).max() ?? 0
            return min(1.0, maxSpeed / achievement.requirement.value)

        case .driveCount:
            let filteredDrives: [Drive]
            if let condition = achievement.requirement.condition {
                filteredDrives = filterDrives(drives, for: condition)
            } else {
                filteredDrives = drives
            }
            return min(1.0, Double(filteredDrives.count) / achievement.requirement.value)

        case .totalDistance:
            let totalDistance = drives.reduce(0) { $0 + $1.distance }
            return min(1.0, totalDistance / achievement.requirement.value)

        case .zeroToSixty:
            // Best (lowest) 0-60 time across all drives. Lower is better,
            // so progress approaches 1.0 as the time approaches the
            // requirement threshold; at or under the threshold = unlocked.
            let bestTime = drives.compactMap(\.best060Time).filter { $0 > 0 }.min()
            guard let bestTime else { return 0.0 }
            if bestTime <= achievement.requirement.value {
                return 1.0
            }
            return achievement.requirement.value / bestTime

        case .smoothness:
            // Smoothness proxy: fewer brake events per mile = smoother.
            // 0 brake events/mile -> 100%, 10+ brake events/mile -> 0%.
            let totalDistanceMiles = drives.reduce(0) { $0 + $1.distance } / 1609.34
            guard totalDistanceMiles > 0 else { return 0.0 }
            let totalBrakeEvents = drives.reduce(0) { $0 + $1.brakeEvents }
            let brakeEventsPerMile = Double(totalBrakeEvents) / totalDistanceMiles
            let smoothnessScore = max(0, 100 - (brakeEventsPerMile * 10))
            return min(1.0, smoothnessScore / achievement.requirement.value)

        case .consecutiveDays:
            let consecutive = calculateConsecutiveDays(from: drives)
            return min(1.0, Double(consecutive) / achievement.requirement.value)
        }
    }

    private func filterDrives(_ drives: [Drive], for condition: String) -> [Drive] {
        let calendar = Calendar.current

        return drives.filter { drive in
            switch condition {
            case "weekend":
                let weekday = calendar.component(.weekday, from: drive.startTime)
                return weekday == 1 || weekday == 7

            case "after_midnight":
                let hour = calendar.component(.hour, from: drive.startTime)
                return hour >= 0 && hour < 6

            default:
                return false
            }
        }
    }

    private func calculateConsecutiveDays(from drives: [Drive]) -> Int {
        let sortedDrives = drives.sorted { $0.startTime < $1.startTime }
        guard !sortedDrives.isEmpty else { return 0 }

        let calendar = Calendar.current
        var consecutiveDays = 1
        var maxConsecutive = 1

        for i in 1..<sortedDrives.count {
            let prevDate = calendar.startOfDay(for: sortedDrives[i-1].startTime)
            let currentDate = calendar.startOfDay(for: sortedDrives[i].startTime)
            let dayDiff = calendar.dateComponents([.day], from: prevDate, to: currentDate).day ?? 0

            if dayDiff == 1 {
                consecutiveDays += 1
                maxConsecutive = max(maxConsecutive, consecutiveDays)
            } else if dayDiff == 0 {
                // Same day — don't reset, just continue
                continue
            } else {
                consecutiveDays = 1
            }
        }

        return maxConsecutive
    }

    private func loadAchievements() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let decoded = try? JSONDecoder().decode([Achievement].self, from: data) {
            achievements = decoded
        }
    }

    private func saveAchievements() {
        if let data = try? JSONEncoder().encode(achievements) {
            UserDefaults.standard.set(data, forKey: userDefaultsKey)
        }
    }

    var unlockedAchievements: [Achievement] {
        achievements.filter(\.isUnlocked)
    }

    var lockedAchievements: [Achievement] {
        achievements.filter { !$0.isUnlocked }
    }

    func clearRecentUnlocks() {
        recentUnlocks.removeAll()
    }

    @MainActor
    func resetProgress() {
        recentUnlocks.removeAll()
        achievements = AchievementCatalog.createDefaultAchievements()
        saveAchievements()
    }
}
