import SwiftUI

// MARK: - Supporting Types

enum TimeFrame: CaseIterable {
    case week, month, quarter, year
    
    var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .quarter: return "3 Months"
        case .year: return "Year"
        }
    }
    
    var dateComponent: Calendar.Component {
        switch self {
        case .week: return .day
        case .month: return .month
        case .quarter: return .month
        case .year: return .year
        }
    }
    
    var value: Int {
        switch self {
        case .week: return 7
        case .month: return 1
        case .quarter: return 3
        case .year: return 1
        }
    }
}

enum AnalyticsMetric: CaseIterable {
    case speed, distance, smoothness, acceleration
    
    var displayName: String {
        switch self {
        case .speed: return "Max Speed"
        case .distance: return "Distance"
        case .smoothness: return "Smoothness"
        case .acceleration: return "Max Acceleration"
        }
    }
    
    var unit: String {
        let s = AppSettings.shared
        switch self {
        case .speed: return s.speedUnit
        case .distance: return s.distanceUnit
        case .smoothness: return "score"
        case .acceleration: return "G"
        }
    }
    
    var color: Color {
        switch self {
        case .speed: return .red
        case .distance: return .blue
        case .smoothness: return .green
        case .acceleration: return .orange
        }
    }
    
    func getValue(from drive: Drive) -> Double {
        let s = AppSettings.shared
        switch self {
        case .speed: return drive.maxSpeed * s.speedFactor
        case .distance: return drive.distance * s.distanceFactor
        case .smoothness: return AnalyticsData.smoothnessScore(for: drive)
        case .acceleration: return drive.peakGForce
        }
    }
}

enum TrendDirection {
    case up, down, neutral
    
    var icon: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .neutral: return "minus"
        }
    }
    
    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .neutral: return .gray
        }
    }
    
    var label: String {
        switch self {
        case .up: return "Up"
        case .down: return "Down"
        case .neutral: return "Same"
        }
    }
}

// MARK: - Analytics Data Model

struct AnalyticsData {
    let drives: [Drive]
    
    var totalDistance: Double {
        drives.reduce(0) { $0 + $1.distance }
    }
    
    var avgMaxSpeed: Double {
        guard !drives.isEmpty else { return 0 }
        return drives.reduce(0) { $0 + $1.maxSpeed } / Double(drives.count)
    }
    
    var overallDrivingScore: Double {
        guard !drives.isEmpty else { return 0 }
        let smoothComponent    = avgSmoothness * 0.40
        let consistencyComp    = consistency   * 0.30
        let perfComp           = min(avgMaxSpeed / (160 / 3.6) * 100, 100) * 0.30
        return max(0, min(100, smoothComponent + consistencyComp + perfComp))
    }
    
    var speedTrend: TrendDirection {
        guard drives.count >= 2 else { return .neutral }
        let recent = drives.prefix(drives.count / 2).map(\.maxSpeed)
        let older = drives.suffix(drives.count / 2).map(\.maxSpeed)
        
        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let olderAvg = older.reduce(0, +) / Double(older.count)
        
        if recentAvg > olderAvg * 1.05 { return .up }
        if recentAvg < olderAvg * 0.95 { return .down }
        return .neutral
    }
    
    var scoreTrend: TrendDirection {
        guard drives.count >= 4 else { return .neutral }
        let half = drives.count / 2
        let recentScore = AnalyticsData(drives: Array(drives.prefix(half))).overallDrivingScore
        let olderScore  = AnalyticsData(drives: Array(drives.suffix(half))).overallDrivingScore
        if recentScore > olderScore + 3 { return .up }
        if recentScore < olderScore - 3 { return .down }
        return .neutral
    }
    
    var bestZeroToSixty: Double? {
        drives.compactMap(\.best060Time).min()
    }
    
    var zeroToSixtyCategory: String {
        guard let time = bestZeroToSixty else { return "Unknown" }
        switch time {
        case 0..<3.0: return "Hypercar"
        case 3.0..<4.0: return "Supercar"
        case 4.0..<6.0: return "Sports Car"
        default: return "Quick"
        }
    }
    
    var maxLateralG: Double {
        drives.map(\.peakGForce).max() ?? 0
    }
    
    var corneringGrade: String {
        switch maxLateralG {
        case 0.8...: return "Race Driver"
        case 0.6..<0.8: return "Enthusiast"
        default: return "Spirited"
        }
    }
    
    var avgSmoothness: Double {
        guard !drives.isEmpty else { return 0 }
        let scores = drives.map { AnalyticsData.smoothnessScore(for: $0) }
        return scores.reduce(0, +) / Double(scores.count)
    }

    /// Smoothness score 0–100 for a single drive.
    /// Penalises harsh acceleration, hard braking, and high G-force events.
    static func smoothnessScore(for drive: Drive) -> Double {
        guard drive.maxSpeed > 0, drive.duration > 0 else { return 50 }
        let speedEfficiency = drive.avgSpeed / max(drive.maxSpeed, 1)   // 0–1: higher is smoother
        let accelPenalty    = min(drive.maxAcceleration / 9.81, 1.0) * 15
        let decelPenalty    = min(drive.maxDeceleration / 9.81, 1.0) * 15
        let gPenalty        = min(drive.peakGForce / 2.0, 1.0) * 20
        let brakePenalty    = min(Double(drive.brakeEvents) * 2.0, 20)
        return max(0, min(100, speedEfficiency * 100 - accelPenalty - decelPenalty - gPenalty - brakePenalty))
    }
    
    var drivingStyle: String {
        switch avgSmoothness {
        case 90...: return "Silk Smooth"
        case 80..<90: return "Very Smooth"
        case 70..<80: return "Smooth"
        default: return "Moderate"
        }
    }
    
    var consistency: Double {
        guard drives.count >= 3 else { return drives.isEmpty ? 0 : 85 }
        let speeds = drives.map(\.maxSpeed)
        let mean   = speeds.reduce(0, +) / Double(speeds.count)
        guard mean > 0 else { return 0 }
        let variance = speeds.map { pow($0 - mean, 2) }.reduce(0, +) / Double(speeds.count)
        let cv = sqrt(variance) / mean  // coefficient of variation: lower = more consistent
        return max(0, min(100, 100 - cv * 150))
    }
    
    var consistencyGrade: String {
        switch consistency {
        case 90...: return "Exceptional"
        case 80..<90: return "Excellent"
        case 70..<80: return "Good"
        default: return "Average"
        }
    }
    
    var topSpeedDrives: [Drive] {
        drives.sorted { $0.maxSpeed > $1.maxSpeed }
    }

    /// Average max speed over a pre-filtered set of drives (used for prior-period comparison).
    static func avgMaxSpeed(for drives: [Drive]) -> Double? {
        guard !drives.isEmpty else { return nil }
        return drives.reduce(0) { $0 + $1.maxSpeed } / Double(drives.count)
    }
}
