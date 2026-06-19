import Foundation
import CoreLocation

// MARK: - Heading detection result

struct HeadingResult: Sendable, Equatable {
    let leftTurns: Int
    let rightTurns: Int
    let laneChanges: Int
    var hasAny: Bool { leftTurns + rightTurns + laneChanges > 0 }
}

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
    let course: Double
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

    private var lastIngestedLat: Double = 0
    private var lastIngestedLng: Double = 0
    private var lastIngestedCourse: Double = -1
    private var lastIngestedSpeed: Double = 0
    private var lastIngestedTimestamp: TimeInterval = 0
    private var lastIngestedSpeedAccuracy: Double = 0
    private var hasIngestedOnce: Bool = false

    private var maxAcceleration: Double = 0
    private var maxDeceleration: Double = 0
    private var peakGForce: Double = 0
    private var topCornerSpeed: Double = 0
    private var brakeEventCount: Int = 0

    // MARK: - Heading detection state

    private var headingWindow: (course: Double, timestamp: TimeInterval)?
    private var headingHistory: [(course: Double, timestamp: TimeInterval)] = []
    private var lastTurnOrLaneTime: TimeInterval?
    private var totalLeftTurns: Int = 0
    private var totalRightTurns: Int = 0
    private var totalLaneChanges: Int = 0

    func previousRoutePoint() -> PreviousRoutePoint {
        if !hasIngestedOnce {
            return PreviousRoutePoint(location: nil, speed: 0)
        }
        let loc = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: lastIngestedLat, longitude: lastIngestedLng),
            altitude: 0,
            horizontalAccuracy: 0,
            verticalAccuracy: 0,
            course: lastIngestedCourse,
            speed: lastIngestedSpeed,
            timestamp: Date(timeIntervalSince1970: lastIngestedTimestamp)
        )
        return PreviousRoutePoint(location: loc, speed: lastIngestedSpeed)
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
        lastIngestedLat = update.coordinate.latitude
        lastIngestedLng = update.coordinate.longitude
        lastIngestedCourse = update.course
        lastIngestedSpeed = update.speed
        lastIngestedTimestamp = update.timestamp
        hasIngestedOnce = true
        if routePointCount == 1 {
            runningMinSpeed = update.speed
            runningMaxSpeed = update.speed
        } else {
            if update.speed < runningMinSpeed { runningMinSpeed = update.speed }
            if update.speed > runningMaxSpeed { runningMaxSpeed = update.speed }
        }
        runningSumSpeed += update.speed
        if let accel = update.acceleration, accel > maxAcceleration {
            maxAcceleration = accel
        }
        if let decel = update.deceleration, decel > maxDeceleration {
            maxDeceleration = decel
        }
        if let g = update.gForce, g > peakGForce {
            peakGForce = g
        }
        if let corner = update.cornerSpeed, corner > topCornerSpeed {
            topCornerSpeed = corner
        }
        if update.brakeDetected {
            brakeEventCount += 1
        }
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

    struct ExtendedStats: Sendable, Equatable {
        let maxAcceleration: Double
        let maxDeceleration: Double
        let peakGForce: Double
        let topCornerSpeed: Double
        let brakeEvents: Int
    }

    func extendedStats() -> ExtendedStats {
        ExtendedStats(
            maxAcceleration: maxAcceleration,
            maxDeceleration: maxDeceleration,
            peakGForce: peakGForce,
            topCornerSpeed: topCornerSpeed,
            brakeEvents: brakeEventCount
        )
    }

    func ingestHeading(course: Double, speed: Double, timestamp: TimeInterval) -> HeadingResult {
        defer {
            headingWindow = (course, timestamp)
        }

        guard let window = headingWindow else {
            headingHistory.append((course, timestamp))
            return HeadingResult(leftTurns: 0, rightTurns: 0, laneChanges: 0)
        }

        let windowAge = timestamp - window.timestamp
        guard windowAge >= 2.0 else { return HeadingResult(leftTurns: 0, rightTurns: 0, laneChanges: 0) }

        var delta = course - window.course
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }

        let gap: TimeInterval = lastTurnOrLaneTime.map { timestamp - $0 } ?? 100

        headingHistory.append((course, timestamp))
        let cutoff = timestamp - 10
        headingHistory.removeAll { $0.timestamp < cutoff }
        let inCurve = isSustainedCurve(upToTimestamp: timestamp)

        var left = 0, right = 0, lane = 0
        if abs(delta) > 35 && gap > 4 {
            if delta > 0 { right = 1 } else { left = 1 }
        } else if abs(delta) >= 10 && abs(delta) <= 35 && speed > 6.7 && gap > 3 && !inCurve {
            lane = 1
        }

        totalLeftTurns += left
        totalRightTurns += right
        totalLaneChanges += lane
        if left + right + lane > 0 {
            lastTurnOrLaneTime = timestamp
        }

        return HeadingResult(leftTurns: left, rightTurns: right, laneChanges: lane)
    }

    func headingTotals() -> (left: Int, right: Int, lane: Int) {
        (totalLeftTurns, totalRightTurns, totalLaneChanges)
    }

    func resetHeading() {
        headingWindow = nil
        headingHistory.removeAll()
        lastTurnOrLaneTime = nil
        totalLeftTurns = 0
        totalRightTurns = 0
        totalLaneChanges = 0
    }

    private func isSustainedCurve(upToTimestamp: TimeInterval) -> Bool {
        let windowStart = upToTimestamp - 8
        let window = headingHistory.filter { $0.timestamp >= windowStart }
        guard window.count >= 4 else { return false }

        var cumulative = 0.0
        var signs: [Double] = []
        for i in 1..<window.count {
            var d = window[i].course - window[i-1].course
            if d > 180 { d -= 360 }
            if d < -180 { d += 360 }
            if abs(d) > 0.5 {
                cumulative += abs(d)
                signs.append(d > 0 ? 1 : -1)
            }
        }
        guard cumulative > 40, signs.count >= 3 else { return false }
        let allSame = signs.allSatisfy { $0 == signs[0] }
        return allSame
    }

    func reset() {
        routePointCount = 0
        runningMinSpeed = 0
        runningMaxSpeed = 0
        runningSumSpeed = 0
        lastCoordinate = nil
        lastPublishedAt = .distantPast
        lastIngestedLat = 0
        lastIngestedLng = 0
        lastIngestedCourse = 0
        lastIngestedSpeed = 0
        lastIngestedTimestamp = 0
        lastIngestedSpeedAccuracy = 0
        hasIngestedOnce = false
        maxAcceleration = 0
        maxDeceleration = 0
        peakGForce = 0
        topCornerSpeed = 0
        brakeEventCount = 0
        resetHeading()
    }
}
