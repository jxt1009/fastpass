import Foundation

// MARK: - Achievement Catalog

enum AchievementCatalog {
    static func createDefaultAchievements() -> [Achievement] {
        return [
            Achievement(
                id: "first_drive",
                title: "First Drive",
                description: "Complete your first recorded drive",
                category: .milestone,
                icon: "car.fill",
                requirement: AchievementRequirement(type: .driveCount, value: 1, condition: nil)
            ),

            Achievement(
                id: "speed_50",
                title: "Half Century",
                description: "Reach 50 mph",
                category: .speed,
                icon: "gauge.with.needle",
                requirement: AchievementRequirement(type: .maxSpeed, value: 22.352, condition: nil)
            ),

            Achievement(
                id: "speed_100",
                title: "Century Club",
                description: "Join the elite 100 mph club",
                category: .speed,
                icon: "speedometer",
                requirement: AchievementRequirement(type: .maxSpeed, value: 44.704, condition: nil)
            ),

            Achievement(
                id: "speed_150",
                title: "Speed Demon",
                description: "Hit the legendary 150 mph mark",
                category: .speed,
                icon: "bolt.fill",
                requirement: AchievementRequirement(type: .maxSpeed, value: 67.056, condition: nil),
                isSecret: true
            ),

            Achievement(
                id: "distance_10",
                title: "Explorer",
                description: "Drive a total of 10 miles",
                category: .distance,
                icon: "map.fill",
                requirement: AchievementRequirement(type: .totalDistance, value: 16093.4, condition: nil)
            ),

            Achievement(
                id: "distance_100",
                title: "Road Warrior",
                description: "Drive a total of 100 miles",
                category: .distance,
                icon: "road.lanes",
                requirement: AchievementRequirement(type: .totalDistance, value: 160934, condition: nil)
            ),

            Achievement(
                id: "distance_1000",
                title: "Mile Crusher",
                description: "Drive a total of 1,000 miles",
                category: .distance,
                icon: "globe",
                requirement: AchievementRequirement(type: .totalDistance, value: 1609344, condition: nil)
            ),

            Achievement(
                id: "drives_10",
                title: "Getting Started",
                description: "Complete 10 recorded drives",
                category: .milestone,
                icon: "circle.fill",
                requirement: AchievementRequirement(type: .driveCount, value: 10, condition: nil)
            ),

            Achievement(
                id: "drives_50",
                title: "Experienced Driver",
                description: "Complete 50 recorded drives",
                category: .milestone,
                icon: "award.fill",
                requirement: AchievementRequirement(type: .driveCount, value: 50, condition: nil)
            ),

            Achievement(
                id: "drives_100",
                title: "Dedicated Tracker",
                description: "Complete 100 recorded drives",
                category: .milestone,
                icon: "checkmark.circle.fill",
                requirement: AchievementRequirement(type: .driveCount, value: 100, condition: nil)
            ),

            Achievement(
                id: "streak_7",
                title: "Week Warrior",
                description: "Drive on 7 consecutive days",
                category: .consistency,
                icon: "calendar",
                requirement: AchievementRequirement(type: .consecutiveDays, value: 7, condition: nil)
            ),

            Achievement(
                id: "streak_30",
                title: "Monthly Master",
                description: "Drive on 30 consecutive days",
                category: .consistency,
                icon: "star.fill",
                requirement: AchievementRequirement(type: .consecutiveDays, value: 30, condition: nil)
            ),

            Achievement(
                id: "sub_6_club",
                title: "Sub-6-Second Club",
                description: "Achieve 0-60 mph in under 6 seconds",
                category: .performance,
                icon: "timer",
                requirement: AchievementRequirement(type: .zeroToSixty, value: 6.0, condition: nil)
            ),

            Achievement(
                id: "smooth_operator",
                title: "Smooth Operator",
                description: "Maintain 90% driving smoothness score",
                category: .consistency,
                icon: "waveform.path",
                requirement: AchievementRequirement(type: .smoothness, value: 90.0, condition: nil),
                isSecret: true
            ),

            Achievement(
                id: "midnight_driver",
                title: "Midnight Driver",
                description: "Complete a drive after midnight",
                category: .special,
                icon: "moon.stars.fill",
                requirement: AchievementRequirement(type: .driveCount, value: 1, condition: "after_midnight")
            ),

            Achievement(
                id: "weekend_warrior",
                title: "Weekend Warrior",
                description: "Complete 10 drives on weekends",
                category: .special,
                icon: "sun.max",
                requirement: AchievementRequirement(type: .driveCount, value: 10, condition: "weekend")
            )
        ]
    }
}
