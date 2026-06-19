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
    static func rows(for profile: PublicProfile, settings: AppSettings) -> [PublicProfileStatRow] {
        [
            PublicProfileStatRow(
                icon: "speedometer", color: .ftRed,
                label: "Top Speed",
                value: settings.speedDisplay(profile.topSpeed)
            ),
            PublicProfileStatRow(
                icon: "timer", color: .ftAmber,
                label: "Best 0-60",
                value: best060Display(profile.best060Time)
            ),
            PublicProfileStatRow(
                icon: "map.fill", color: .blue,
                label: "Total Distance",
                value: settings.distanceDisplay(profile.totalDistance)
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

// MARK: - Public profile per-car stats lookup
//
// `PublicProfile.carStatsData` is an opaque text blob the server stores
// as a JSON dictionary keyed by `CarStats.carId` (which equals the
// `UserCar.id` UUID). The public profile view decodes it once per
// render so the garage section can index by id without re-parsing for
// every row.
//
// Promoting this to a static (instead of a `private` method on the
// view) makes the decoder unit-testable and lets us add a `#if DEBUG`
// trace that records the raw key shape — the diagnostic that proves
// the key-mismatch hypothesis for users whose stats aren't rendering
// even though their `car_stats_data` blob is non-empty.

#if DEBUG
import OSLog
private let publicProfileStatsLookupLog = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.fasttrack.app",
    category: "public-profile-stats"
)
#endif

enum PublicProfileStatsLookup {

    /// Decode the per-car stats blob once into a `[carId: CarStats]`
    /// dictionary. Returns an empty dictionary when the blob is
    /// missing, empty, or malformed. Pure: no side effects in release
    /// builds; in debug builds, logs a one-line trace of the decode
    /// shape so we can see why a particular user's car keys aren't
    /// matching.
    static func byCarId(blob: String?) -> [String: CarStats] {
        #if DEBUG
        let blobLength = blob?.count ?? 0
        #endif

        guard let blob, !blob.isEmpty,
              let data = blob.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String: CarStats].self, from: data)
        else {
            #if DEBUG
            if blobLength > 0 {
                publicProfileStatsLookupLog.debug(
                    "statsByCarId decode miss: blob length=\(blobLength, privacy: .public) keyCount=0 sample=(none)"
                )
            }
            #endif
            return [:]
        }

        #if DEBUG
        let keyCount = decoded.count
        let sample = decoded.keys.sorted().first.map { String($0.prefix(8)) } ?? "(none)"
        publicProfileStatsLookupLog.debug(
            "statsByCarId decoded: blob length=\(blobLength, privacy: .public) keyCount=\(keyCount, privacy: .public) sample=\(sample, privacy: .public)"
        )
        #endif

        return decoded
    }

    /// Whether the `car_stats_data` blob actually carries any per-car
    /// stats. True only when the blob decodes to a non-empty
    /// `[String: CarStats]` dictionary. Used by the public car detail
    /// view to distinguish "no driving data" (nil / empty / `{}` /
    /// malformed) from "stats haven't synced for *this* car" (blob
    /// has entries, just none for the car being viewed).
    static func isSyncedBlob(_ blob: String?) -> Bool {
        !byCarId(blob: blob).isEmpty
    }
}
