import Foundation
import SwiftUI

// MARK: - Public profile stat rows (Top Speed, 0-60, Total Distance)
//
// The redesigned public profile renders the headline stats in this fixed
// order — dropping "Total Drives" per the #57 redesign. Lives in its own
// model file so unit tests can drive the formatter without touching a View.

struct PublicProfileStatRow: Equatable, Identifiable {
    let icon: String
    let color: Color
    let label: String
    let value: String
    let id: String

    init(icon: String, color: Color, label: String, value: String) {
        self.icon = icon
        self.color = color
        self.label = label
        self.value = value
        self.id = label
    }
}

enum PublicProfileStats {

    /// The locked-in display order. Top Speed first, Best 0-60 second
    /// (moved up from below Total Distance), Total Distance last. Total
    /// Drives is dropped entirely.
    static func rows(for profile: PublicProfile) -> [PublicProfileStatRow] {
        [
            PublicProfileStatRow(
                icon: "speedometer", color: .red,
                label: "Top Speed",
                value: AppSettings.shared.speedDisplay(profile.topSpeed)
            ),
            PublicProfileStatRow(
                icon: "timer", color: .orange,
                label: "Best 0-60",
                value: best060Display(profile.best060Time)
            ),
            PublicProfileStatRow(
                icon: "map.fill", color: .blue,
                label: "Total Distance",
                value: AppSettings.shared.distanceDisplay(profile.totalDistance)
            ),
        ]
    }

    static func best060Display(_ time: Double?) -> String {
        guard let time else { return "N/A" }
        return String(format: "%.2f sec", time)
    }
}

// MARK: - Garage card short stats
//
// The per-car "short stats" line on the redesigned garage overview is a
// single inline string like
//   "Top: 124 mph · Best 0-60: 4.32s · Total: 1.2 mi"
// Hidden entirely when all three are zero.
//
// The formatter is intentionally side-effect free: callers pass in the
// unit label + conversion factors so the helper doesn't have to
// instantiate `AppSettings` (whose `unitSystem` setter writes
// UserDefaults and triggers a server sync, which would surprise tests
// and view renderers alike).

enum GarageCardShortStats {

    /// Returns the formatted short-stats line, or `nil` if every stat is
    /// zero (or the input has no stats at all). The caller can then decide
    /// to render an "empty" placeholder or simply omit the line.
    static func formattedLine(
        for stats: CarStats?,
        speedUnit: String,
        distanceUnit: String,
        speedFactor: Double,
        distanceFactor: Double
    ) -> String? {
        guard let stats else { return nil }

        let segments: [String] = [
            topSpeedSegment(stats: stats, speedUnit: speedUnit, speedFactor: speedFactor),
            best060Segment(stats: stats),
            totalDistanceSegment(stats: stats, distanceUnit: distanceUnit, distanceFactor: distanceFactor),
        ].compactMap { $0 }

        return segments.isEmpty ? nil : segments.joined(separator: " · ")
    }

    static func topSpeedSegment(stats: CarStats, speedUnit: String, speedFactor: Double) -> String? {
        guard stats.bestTopSpeed > 0 else { return nil }
        return String(
            format: "Top: %.0f %@",
            stats.bestTopSpeed * speedFactor,
            speedUnit
        )
    }

    static func best060Segment(stats: CarStats) -> String? {
        guard let time = stats.bestZeroToSixty, time > 0 else { return nil }
        return String(format: "Best 0-60: %.2fs", time)
    }

    static func totalDistanceSegment(stats: CarStats, distanceUnit: String, distanceFactor: Double) -> String? {
        guard stats.totalDistance > 0 else { return nil }
        return String(
            format: "Total: %.1f %@",
            stats.totalDistance * distanceFactor,
            distanceUnit
        )
    }
}

// MARK: - Followers / Following endpoint URLs (testable URL builder)
//
// `APIService` constructs URLs through `get(endpoint:)` which does string
// interpolation. The simple helper below mirrors that so we can assert on
// the produced path without making a real network call.

enum FollowListEndpoint {

    /// Single path-segment character set: everything in `.urlPathAllowed`
    /// except `/`, so a username containing `/` is encoded as `%2F`
    /// instead of being treated as a path separator.
    private static var pathSegment: CharacterSet {
        var set = CharacterSet.urlPathAllowed
        set.remove(charactersIn: "/")
        return set
    }

    static func followersPath(username: String) -> String {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: pathSegment) ?? username
        return "/users/\(encoded)/followers"
    }

    static func followingPath(username: String) -> String {
        let encoded = username.addingPercentEncoding(withAllowedCharacters: pathSegment) ?? username
        return "/users/\(encoded)/following"
    }
}

// MARK: - Garage JSON parsing helper
//
// The public profile returns `garage` as a JSON string. This decodes it
// into `[UserCar]`, returning an empty array if the blob is empty,
// missing, or malformed — so the view can render an empty garage state
// without catching DecodingError itself.

enum GarageBlob {

    static func decode(_ blob: String?) -> [UserCar] {
        guard let blob, !blob.isEmpty,
              let data = blob.data(using: .utf8) else { return [] }
        return (try? JSONDecoder().decode([UserCar].self, from: data)) ?? []
    }
}
