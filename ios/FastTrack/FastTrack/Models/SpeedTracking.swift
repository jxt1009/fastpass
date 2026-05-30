import Foundation

struct SpeedSample: Equatable {
    let speed: Double
    let rawGPSSpeed: Double
    let speedAccuracy: Double
    let timestamp: Date
    let isZeroLocked: Bool
    let stationaryConfidence: Double

    var speedMph: Double { speed * 2.23694 }
    var isStationary: Bool { isZeroLocked || stationaryConfidence >= 0.8 }
}

struct LaunchTracker {
    private let targetSpeedMph = 60.0
    private let minValidElapsed = 1.0
    private let maxValidElapsed = 30.0

    private(set) var best060Time: Double?
    private var activeLaunchStart: Date?
    private var lastSample: SpeedSample?

    mutating func ingest(_ sample: SpeedSample) -> Double? {
        defer { lastSample = sample }

        if let previous = lastSample, previous.isZeroLocked && !sample.isZeroLocked {
            activeLaunchStart = sample.timestamp
        }

        if sample.isZeroLocked {
            activeLaunchStart = nil
            return nil
        }

        guard let start = activeLaunchStart,
              let previous = lastSample else { return nil }

        if sample.timestamp.timeIntervalSince(start) > maxValidElapsed {
            activeLaunchStart = nil
            return nil
        }

        guard previous.speedMph < targetSpeedMph, sample.speedMph >= targetSpeedMph else {
            return nil
        }

        let crossingTime = interpolatedCrossingTime(from: previous, to: sample, targetSpeedMph: targetSpeedMph)
        let elapsed = crossingTime.timeIntervalSince(start)
        activeLaunchStart = nil

        guard elapsed >= minValidElapsed, elapsed <= maxValidElapsed else {
            return nil
        }

        if let best060Time {
            guard elapsed < best060Time else { return nil }
        }

        best060Time = elapsed
        return elapsed
    }

    mutating func reset() {
        best060Time = nil
        activeLaunchStart = nil
        lastSample = nil
    }

    private func interpolatedCrossingTime(from lower: SpeedSample, to upper: SpeedSample, targetSpeedMph: Double) -> Date {
        let speedDelta = upper.speedMph - lower.speedMph
        let timeDelta = upper.timestamp.timeIntervalSince(lower.timestamp)
        guard speedDelta > 0, timeDelta > 0 else { return upper.timestamp }

        let fraction = (targetSpeedMph - lower.speedMph) / speedDelta
        let clampedFraction = min(max(fraction, 0), 1)
        return lower.timestamp.addingTimeInterval(timeDelta * clampedFraction)
    }
}

struct StoppedTimeTracker {
    private let stopEntrySpeedThreshold = 0.35      // m/s ≈ 0.8 mph
    private let stopExitSpeedThreshold = 0.75       // m/s ≈ 1.7 mph
    private let stopEntryHoldTime = 0.25
    private let stopExitHoldTime = 0.20
    private let stopConfidenceThreshold = 0.7
    private let movingConfidenceThreshold = 0.35

    private(set) var totalStoppedTime: Double = 0
    private(set) var stoppedSince: Date?
    private var stopCandidateSince: Date?
    private var movingCandidateSince: Date?

    mutating func ingest(_ sample: SpeedSample) {
        let stationaryCandidate = sample.isZeroLocked
            || sample.speed <= stopEntrySpeedThreshold
            || (sample.speed <= 0.5 && sample.stationaryConfidence >= stopConfidenceThreshold)
        let movingCandidate = sample.speed >= stopExitSpeedThreshold
            && !sample.isZeroLocked
            && sample.stationaryConfidence <= movingConfidenceThreshold

        if let stoppedSince {
            stopCandidateSince = nil

            if movingCandidate {
                movingCandidateSince = movingCandidateSince ?? sample.timestamp
                if sample.timestamp.timeIntervalSince(movingCandidateSince ?? sample.timestamp) >= stopExitHoldTime {
                    totalStoppedTime += (movingCandidateSince ?? sample.timestamp).timeIntervalSince(stoppedSince)
                    self.stoppedSince = nil
                    movingCandidateSince = nil
                }
            } else {
                movingCandidateSince = nil
            }
            return
        }

        movingCandidateSince = nil

        if stationaryCandidate {
            stopCandidateSince = stopCandidateSince ?? sample.timestamp
            if sample.timestamp.timeIntervalSince(stopCandidateSince ?? sample.timestamp) >= stopEntryHoldTime {
                stoppedSince = stopCandidateSince
                stopCandidateSince = nil
            }
        } else {
            stopCandidateSince = nil
        }
    }

    mutating func finalize(at endTime: Date) {
        if let stoppedSince {
            totalStoppedTime += endTime.timeIntervalSince(stoppedSince)
            self.stoppedSince = nil
        }
        stopCandidateSince = nil
        movingCandidateSince = nil
    }

    func totalStoppedTime(at date: Date) -> Double {
        totalStoppedTime + (stoppedSince.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }

    mutating func reset() {
        totalStoppedTime = 0
        stoppedSince = nil
        stopCandidateSince = nil
        movingCandidateSince = nil
    }
}
