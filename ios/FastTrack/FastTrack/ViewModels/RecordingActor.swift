import Foundation
import CoreLocation

/// Coalesced view-facing snapshot of the recording path's hot state.
/// Produced by `RecordingActor` at most every 100 ms and consumed
/// on the main actor by `DriveManager` / `ContentView`.
struct DriveStatsSnapshot: Sendable, Equatable {
    let routePointCount: Int
    let runningMaxSpeed: Double
    let runningMinSpeed: Double
    let runningAvgSpeed: Double
    let lastCoordinate: CLLocationCoordinate2D?
    let publishedAt: Date
}

/// A per-tick update handed to the actor. All fields except the
/// coordinate and timestamp are optional so callers can decide
/// which events to surface (e.g. brake events are rare).
struct RecordingActorUpdate: Sendable {
    let coordinate: CLLocationCoordinate2D
    let speed: Double
    let timestamp: TimeInterval
    let acceleration: Double?
    let deceleration: Double?
    let brakeDetected: Bool
    let gForce: Double?
    let cornerSpeed: Double?
}

/// Returns the previous route point + its recorded speed, used by
/// the per-tick accel/G-force math. Nil on the first sample.
struct PreviousRoutePoint: Sendable {
    let location: CLLocation?
    let speed: Double
}

/// Owns all the recording-path state that was previously mutated on
/// the main actor (route points, extended tracking scalars, running
/// stats). All `ingest*` methods are O(1). `snapshot()` returns a
/// Sendable value-type view of the current state and is rate-limited
/// to 10 Hz to avoid hammering the SwiftUI re-render path.
@globalActor
actor RecordingActor {
    static let shared = RecordingActor()

    private var routePointCount: Int = 0
    private var runningMinSpeed: Double = 0
    private var runningMaxSpeed: Double = 0
    private var runningSumSpeed: Double = 0
    private var lastCoordinate: CLLocationCoordinate2D?

    private var lastPublishedAt: Date = .distantPast
    private let publishInterval: TimeInterval = 0.1

    private var lastIngestedLocation: CLLocation?
    private var lastIngestedSpeed: Double = 0

    func previousRoutePoint() -> PreviousRoutePoint {
        PreviousRoutePoint(location: lastIngestedLocation, speed: lastIngestedSpeed)
    }

    func ingestRoutePoint(_ coord: CLLocationCoordinate2D, speed: Double, timestamp: TimeInterval) {
        routePointCount += 1
        lastCoordinate = coord
        if routePointCount == 1 {
            runningMinSpeed = speed
            runningMaxSpeed = speed
        } else {
            if speed < runningMinSpeed { runningMinSpeed = speed }
            if speed > runningMaxSpeed { runningMaxSpeed = speed }
        }
        runningSumSpeed += speed
    }

    func ingest(_ update: RecordingActorUpdate) {
        routePointCount += 1
        lastCoordinate = update.coordinate
        lastIngestedLocation = CLLocation(
            coordinate: update.coordinate,
            altitude: 0,
            horizontalAccuracy: 0,
            verticalAccuracy: 0,
            course: 0,
            speed: update.speed,
            timestamp: Date(timeIntervalSince1970: update.timestamp)
        )
        lastIngestedSpeed = update.speed
        if routePointCount == 1 {
            runningMinSpeed = update.speed
            runningMaxSpeed = update.speed
        } else {
            if update.speed < runningMinSpeed { runningMinSpeed = update.speed }
            if update.speed > runningMaxSpeed { runningMaxSpeed = update.speed }
        }
        runningSumSpeed += update.speed
    }

    /// Returns a coalesced snapshot. If `now` is within
    /// `publishInterval` of the last publish, the same publishedAt
    /// is returned and the underlying values are NOT re-read — the
    /// caller is expected to use the most recent snapshot it has.
    func snapshot(now: Date = Date()) -> DriveStatsSnapshot {
        if now.timeIntervalSince(lastPublishedAt) < publishInterval {
            // Re-use the previous publishedAt so callers can dedupe.
            return DriveStatsSnapshot(
                routePointCount: routePointCount,
                runningMaxSpeed: runningMaxSpeed,
                runningMinSpeed: runningMinSpeed,
                runningAvgSpeed: routePointCount > 0 ? runningSumSpeed / Double(routePointCount) : 0,
                lastCoordinate: lastCoordinate,
                publishedAt: lastPublishedAt
            )
        }
        lastPublishedAt = now
        return DriveStatsSnapshot(
            routePointCount: routePointCount,
            runningMaxSpeed: runningMaxSpeed,
            runningMinSpeed: runningMinSpeed,
            runningAvgSpeed: routePointCount > 0 ? runningSumSpeed / Double(routePointCount) : 0,
            lastCoordinate: lastCoordinate,
            publishedAt: now
        )
    }

    func reset() {
        routePointCount = 0
        runningMinSpeed = 0
        runningMaxSpeed = 0
        runningSumSpeed = 0
        lastCoordinate = nil
        lastPublishedAt = .distantPast
        lastIngestedLocation = nil
        lastIngestedSpeed = 0
    }
}
