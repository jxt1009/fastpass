import Foundation
import CoreLocation

/// Records a single 0-60 mph launch detected during a drive.
/// A drive may contain many attempts; `best060Time` is the minimum of these.
struct ZeroToSixtyAttempt: Codable, Identifiable, Equatable {
    var id: UUID = UUID()
    var startIndex: Int           // index into the rich route point array
    var endIndex: Int             // inclusive end index
    var startTimestamp: Double    // seconds since 1970
    var endTimestamp: Double      // seconds since 1970
    var elapsedSeconds: Double
    var startLatitude: Double
    var startLongitude: Double
    var endLatitude: Double
    var endLongitude: Double
    /// True for attempts synthesised from a pre-existing `best_060_time` on
    /// older drives that did not capture per-launch telemetry. Lets the UI
    /// choose whether to surface them.
    var legacy: Bool = false

    init(
        startIndex: Int,
        endIndex: Int,
        startTimestamp: Double,
        endTimestamp: Double,
        elapsedSeconds: Double,
        startLatitude: Double,
        startLongitude: Double,
        endLatitude: Double,
        endLongitude: Double,
        legacy: Bool = false
    ) {
        self.startIndex = startIndex
        self.endIndex = endIndex
        self.startTimestamp = startTimestamp
        self.endTimestamp = endTimestamp
        self.elapsedSeconds = elapsedSeconds
        self.startLatitude = startLatitude
        self.startLongitude = startLongitude
        self.endLatitude = endLatitude
        self.endLongitude = endLongitude
        self.legacy = legacy
    }

    var startCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: startLatitude, longitude: startLongitude)
    }

    var endCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: endLatitude, longitude: endLongitude)
    }

    var midpointCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(
            latitude: (startLatitude + endLatitude) / 2,
            longitude: (startLongitude + endLongitude) / 2
        )
    }

    // Custom decoder — the server's wire format omits the `id` field (it's
    // an iOS-side identity), so synthesise one on decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id             = (try c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        self.startIndex     = try c.decodeIfPresent(Int.self,    forKey: .startIndex)     ?? 0
        self.endIndex       = try c.decodeIfPresent(Int.self,    forKey: .endIndex)       ?? 0
        self.startTimestamp = try c.decodeIfPresent(Double.self, forKey: .startTimestamp) ?? 0
        self.endTimestamp   = try c.decodeIfPresent(Double.self, forKey: .endTimestamp)   ?? 0
        self.elapsedSeconds = try c.decodeIfPresent(Double.self, forKey: .elapsedSeconds) ?? 0
        self.startLatitude  = try c.decodeIfPresent(Double.self, forKey: .startLatitude)  ?? 0
        self.startLongitude = try c.decodeIfPresent(Double.self, forKey: .startLongitude) ?? 0
        self.endLatitude    = try c.decodeIfPresent(Double.self, forKey: .endLatitude)    ?? 0
        self.endLongitude   = try c.decodeIfPresent(Double.self, forKey: .endLongitude)   ?? 0
        self.legacy         = try c.decodeIfPresent(Bool.self,   forKey: .legacy)         ?? false
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case startIndex     = "start_index"
        case endIndex       = "end_index"
        case startTimestamp = "start_timestamp"
        case endTimestamp   = "end_timestamp"
        case elapsedSeconds = "elapsed_seconds"
        case startLatitude  = "start_latitude"
        case startLongitude = "start_longitude"
        case endLatitude    = "end_latitude"
        case endLongitude   = "end_longitude"
        case legacy
    }
}