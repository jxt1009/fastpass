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
        public enum Phase: String, Codable, Hashable {
            case recording
            case ended
        }

        var phase: Phase
        var speedMph: Double
        var gForce: Double
        var distanceMiles: Double
        var maxSpeedMph: Double
        var elapsedSeconds: TimeInterval

        // Explicit init keeps existing call sites compiling and gives every field
        // a default so future additions stay source-compatible.
        init(
            phase: Phase = .recording,
            speedMph: Double = 0,
            gForce: Double = 0,
            distanceMiles: Double = 0,
            maxSpeedMph: Double = 0,
            elapsedSeconds: TimeInterval = 0
        ) {
            self.phase = phase
            self.speedMph = speedMph
            self.gForce = gForce
            self.distanceMiles = distanceMiles
            self.maxSpeedMph = maxSpeedMph
            self.elapsedSeconds = elapsedSeconds
        }

        // Decode with defaults so any in-flight activity payload that
        // predates `phase` / `elapsedSeconds` still decodes.
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            self.phase = try c.decodeIfPresent(Phase.self, forKey: .phase) ?? .recording
            self.speedMph = try c.decodeIfPresent(Double.self, forKey: .speedMph) ?? 0
            self.gForce = try c.decodeIfPresent(Double.self, forKey: .gForce) ?? 0
            self.distanceMiles = try c.decodeIfPresent(Double.self, forKey: .distanceMiles) ?? 0
            self.maxSpeedMph = try c.decodeIfPresent(Double.self, forKey: .maxSpeedMph) ?? 0
            self.elapsedSeconds = try c.decodeIfPresent(TimeInterval.self, forKey: .elapsedSeconds) ?? 0
        }

        private enum CodingKeys: String, CodingKey {
            case phase, speedMph, gForce, distanceMiles, maxSpeedMph, elapsedSeconds
        }
    }
}
