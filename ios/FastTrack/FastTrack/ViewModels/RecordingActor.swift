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
    }
}
