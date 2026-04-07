import ActivityKit
import Foundation

/// Shared Live Activity attributes for the active drive recording.
/// Lives in the main app target; copied into the widget extension target.
struct DriveActivityAttributes: ActivityAttributes {
    public typealias ContentState = DriveActivityState

    /// Static context — set once at start, never changes while the activity is live.
    let startDate: Date

    /// Dynamic state — updated every GPS tick.
    public struct DriveActivityState: Codable, Hashable {
        var speedMph: Double
        var gForce: Double
        var distanceMiles: Double
        var maxSpeedMph: Double
    }
}
