import ActivityKit
import Foundation

/// Shared Live Activity attributes for the active drive recording.
/// Duplicated in widget extension (must match exactly).
struct DriveActivityAttributes: ActivityAttributes {
    public typealias ContentState = DriveActivityState

    let startDate: Date

    public struct DriveActivityState: Codable, Hashable {
        var speedMph: Double
        var gForce: Double
        var distanceMiles: Double
    }
}
