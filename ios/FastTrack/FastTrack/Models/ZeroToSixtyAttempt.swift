import Foundation
import CoreLocation

/// Records a single 0-60 mph launch detected during a drive.
/// A drive may contain many attempts; `best060Time` is the minimum of these.
struct ZeroToSixtyAttempt: Codable, Identifiable, Equatable, Sendable {
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
    // an iOS-side identity), so synthesise one on decode. All other fields
    // are required: a wire-format mismatch should fail loudly rather than
    // produce an all-zero attempt (which would render as a phantom overlay
    // at (0,0) and a 0.0s elapsed time).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id             = (try c.decodeIfPresent(UUID.self, forKey: .id)) ?? UUID()
        self.startIndex     = try c.decode(Int.self,    forKey: .startIndex)
        self.endIndex       = try c.decode(Int.self,    forKey: .endIndex)
        self.startTimestamp = try c.decode(Double.self, forKey: .startTimestamp)
        self.endTimestamp   = try c.decode(Double.self, forKey: .endTimestamp)
        self.elapsedSeconds = try c.decode(Double.self, forKey: .elapsedSeconds)
        self.startLatitude  = try c.decode(Double.self, forKey: .startLatitude)
        self.startLongitude = try c.decode(Double.self, forKey: .startLongitude)
        self.endLatitude    = try c.decode(Double.self, forKey: .endLatitude)
        self.endLongitude   = try c.decode(Double.self, forKey: .endLongitude)
        self.legacy         = (try c.decodeIfPresent(Bool.self, forKey: .legacy)) ?? false
    }

    // JSON keys mirror the Go `ZeroToSixtyAttempt` struct in
    // `backend/internal/app/models.go` exactly. Don't rename these without
    // updating the server-side struct in lockstep.
    private enum CodingKeys: String, CodingKey {
        case id
        case startIndex     = "start_index"
        case endIndex       = "end_index"
        case startTimestamp = "start_ts"
        case endTimestamp   = "end_ts"
        case elapsedSeconds = "elapsed_s"
        case startLatitude  = "start_lat"
        case startLongitude = "start_lng"
        case endLatitude    = "end_lat"
        case endLongitude   = "end_lng"
        case legacy
    }
}