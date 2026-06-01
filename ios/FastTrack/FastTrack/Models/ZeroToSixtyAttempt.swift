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
}