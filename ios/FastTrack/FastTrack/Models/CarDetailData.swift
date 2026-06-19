import Foundation
import SwiftUI

// MARK: - Driving style
//
// Computed from a car's brake-event-per-mile ratio plus its top speed. The
// thresholds are documented in the issue #64 plan. `.unknown` is the
// "no drives yet" state; everything else is mutually exclusive and the
// `.sporty` / `.smooth` checks short-circuit so e.g. a car with both a
// high top speed *and* a very low brake-per-mile ratio is still
// classified rather than falling through to `.balanced` silently.

enum DrivingStyle: Equatable, Hashable, CaseIterable {
    case sporty
    case smooth
    case balanced
    case unknown

    /// Short, title-cased label for the badge.
    var title: String {
        switch self {
        case .sporty:    return "Sporty"
        case .smooth:    return "Smooth"
        case .balanced:  return "Balanced"
        case .unknown:   return "Unknown"
        }
    }

    /// One-line description of what this style means, shown under the
    /// badge on the per-car detail view.
    var explanation: String {
        switch self {
        case .sporty:    return "Aggressive braking profile"
        case .smooth:    return "Smooth & measured"
        case .balanced:  return "Mixed driving pattern"
        case .unknown:   return "Not enough data yet"
        }
    }

    /// Longer explanation used in the style guide sheet.
    var detailedExplanation: String {
        switch self {
        case .sporty:
            return "Higher brake-event frequency with higher top-speed tendency. Usually indicates aggressive acceleration/braking patterns."
        case .smooth:
            return "Lower brake-event frequency with steady pace changes. Inputs are controlled and measured across most drives."
        case .balanced:
            return "Mix of calm and aggressive sessions. Not strongly biased toward either sporty or smooth behavior."
        case .unknown:
            return "Not enough recorded drives for a reliable classification yet."
        }
    }

    static var guideStyles: [DrivingStyle] {
        [.smooth, .balanced, .sporty, .unknown]
    }

    /// Color for the badge — green for safe, amber for moderate, red for
    /// aggressive. The view layer can ignore this and use the system
    /// category color from `CarStats.performanceCategory` instead; this is
    /// the driving-style-specific palette.
    var color: Color {
        switch self {
        case .sporty:    return .ftRed
        case .smooth:    return .ftGreen
        case .balanced:  return .ftAmber
        case .unknown:   return .secondary
        }
    }

    /// Icon for the badge.
    var icon: String {
        switch self {
        case .sporty:    return "bolt.fill"
        case .smooth:    return "leaf.fill"
        case .balanced:  return "arrow.triangle.2.circlepath"
        case .unknown:   return "questionmark.circle"
        }
    }
}

// MARK: - CarDetailData
//
// Pure value type that aggregates everything `CarDetailView` needs. Kept
// view-free so the derivation logic is unit-testable. Construct via
// `CarDetailData.derive(...)`.

struct CarDetailData {
    let car: UserCar
    let stats: CarStats?
    /// `maxSpeed` (m/s) per drive for this car, ordered by start time
    /// ascending, capped to the most recent 30 drives. Empty when the
    /// user has no drives tagged with this car's id.
    let sparklinePoints: [Double]
    /// Index of the max-speed PB inside `sparklinePoints` (nil when
    /// there are no points). The view uses this to highlight the PB
    /// point on the chart.
    let pbSparklineIndex: Int?
    /// The car's overall top speed (m/s). Nil when no drives have been
    /// recorded for it.
    let bestTopSpeed: Double?
    /// The car's best 0-60 (seconds). Nil when no 0-60 attempt has been
    /// captured.
    let bestZeroToSixty: Double?
    /// `startTime` of the drive that set `bestTopSpeed`. Nil when no
    /// drive is responsible.
    let topSpeedPBDate: Date?
    /// `startTime` of the drive that set `bestZeroToSixty`. Nil when
    /// no 0-60 attempt was captured.
    let zeroSixtyPBDate: Date?
    /// Computed driving style.
    let drivingStyle: DrivingStyle
    /// Achievements that the car is responsible for (source drive is
    /// tagged with this car's id). Empty when the car has no recorded
    /// achievements.
    let achievementPBs: [Achievement]
    /// True if any of `achievementPBs` was unlocked within the last 7
    /// days relative to the injected `now`. The view uses this to gate
    /// the one-shot confetti animation.
    let confettiEligible: Bool
    /// Stable token derived from currently eligible recent PB unlocks.
    /// Changes only when the eligible set changes, allowing the view to
    /// persist one-shot confetti behavior across revisits.
    let confettiTriggerToken: String?
    /// Number of recent PB unlocks currently inside the confetti window.
    /// Used for subtle ongoing UI indication after one-shot confetti.
    let recentPBCount: Int
    /// Smoothness score for this car (0-100).
    let smoothnessScore: Double
    /// Consistency score for this car (0-100).
    let consistencyScore: Double
    /// Cornering (peak lateral G) for this car.
    let peakLateralG: Double
    /// Best 0-60 time in seconds for this car (nil if never reached 60).
    let bestZeroToSixtyTime: Double?
    /// Drives for this car, sorted by startTime descending, capped at 5.
    let recentDrives: [Drive]
    /// Distance per drive trend points (last N drives, oldest first).
    let distanceTrendPoints: [Double]
    /// Smoothness per drive trend points (last N drives, oldest first).
    let smoothnessTrendPoints: [Double]
    /// Avg max speed for the previous period, nil if no prior data.
    let prevPeriodAvgMaxSpeed: Double?
}
