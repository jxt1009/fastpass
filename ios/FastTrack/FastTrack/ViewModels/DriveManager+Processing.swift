import Foundation
import CoreLocation

extension DriveManager {

    // MARK: - Location processing

    internal func processLocation(_ location: CLLocation) {
        let age = abs(location.timestamp.timeIntervalSinceNow)
        if age > 5.0 { return }

        let speed = routePointSpeed(for: location)
        let speedMph = speed * 2.23694

        // Incremental distance: one O(1) delta per tick instead of O(n) re-sweep.
        if let prev = lastDistanceTickLocation {
            let delta = prev.distance(from: location)
            if delta > 0.5 && delta < 500 {
                runningDistanceMeters += delta
            }
        }
        lastDistanceTickLocation = location

        richRoutePoints.append((
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            speed: speed,
            ts: location.timestamp.timeIntervalSince1970
        ))

        if speed > currentMaxSpeed { currentMaxSpeed = speed }

        Task.detached { [weak self] in
            await self?.processLocationHeavy(location, speed: speed, speedMph: speedMph)
        }

        updateCurrentDrive()
        if publishThrottler.shouldPublish() {
            lastRouteCoordinate = location.coordinate
            updateLiveActivity(speedMph: speedMph, distanceMiles: runningDistanceMeters / 1609.344)
        }
    }

    func processSpeedSample(_ sample: SpeedSample) {
        latestSpeedSample = sample
        speedReadings.append(sample.speed)
        runningSpeedStats.ingest(sample.speed)
        stoppedTimeTracker.ingest(sample)

        if sample.speed > currentMaxSpeed {
            currentMaxSpeed = sample.speed
        }

        let priorAttemptCount = launchTracker.attempts.count
        if let newBest = launchTracker.ingest(sample) {
            best060Time = newBest
            #if DEBUG
            print("🏁 New best 0-60 time: \(newBest)s")
            #endif
        }
        // Drain any newly-recorded attempts into the per-drive list. The
        // location-aware fields (indices, lat/lng) are filled in at flush
        // time against the full `richRoutePoints` array.
        if launchTracker.attempts.count > priorAttemptCount {
            let newOnes = launchTracker.attempts[priorAttemptCount...]
            attempts060.append(contentsOf: newOnes)
        }

        guard var drive = currentDrive else { return }
        drive.stoppedTime = stoppedTimeTracker.totalStoppedTime(at: sample.timestamp)
        drive.best060Time = best060Time
        if publishThrottler.shouldPublish() {
            currentDrive = drive
        }
    }

    func routePointSpeed(for location: CLLocation) -> Double {
        guard let latestSpeedSample,
              abs(latestSpeedSample.timestamp.timeIntervalSince(location.timestamp)) <= 1.0 else {
            return max(location.speed, 0)
        }
        return latestSpeedSample.speed
    }

    func processLocationHeavy(_ location: CLLocation, speed: Double, speedMph: Double) async {
        let ts = location.timestamp

        // Read prev from the actor — single hop, not seven.
        let prevRecord = await RecordingActor.shared.previousRoutePoint()
        guard let prev = prevRecord.location else { return }
        let prevSpeed = prevRecord.speed

        let dt = ts.timeIntervalSince(prev.timestamp)
        guard dt > 0 && dt < 5 else { return }

        let speedAccuracyOK = location.speedAccuracy > 0 && location.speedAccuracy < 2.0
                           && prev.speedAccuracy > 0 && prev.speedAccuracy < 2.0

        // All math runs on the detached task's thread.
        let rawAccel = (speed - prevSpeed) / dt
        let maxPhysicalAccelMS2 = 5.0 * 9.81
        let accel = max(-maxPhysicalAccelMS2, min(maxPhysicalAccelMS2, rawAccel))

        // Single actor hop to ingest everything in one batch.
        let update = RecordingActorUpdate(
            coordinate: location.coordinate,
            speed: speed,
            timestamp: ts.timeIntervalSince1970,
            acceleration: speedAccuracyOK && accel > 0 ? accel : nil,
            deceleration: speedAccuracyOK && -accel > 0 ? -accel : nil,
            brakeDetected: accel < -2.5,
            gForce: speedAccuracyOK ? computedGForce(accel: accel, location: location, prev: prev, speed: speed, dt: dt) : nil,
            cornerSpeed: speedAccuracyOK ? speed : nil
        )
        await RecordingActor.shared.ingest(update)
    }

    func processHeading(course: Double, speed: Double, timestamp: Date) async -> (left: Int, right: Int, lanes: Int)? {
        let result = await RecordingActor.shared.ingestHeading(
            course: course,
            speed: speed,
            timestamp: timestamp.timeIntervalSince1970
        )
        if result.hasAny {
            let left = result.leftTurns
            let right = result.rightTurns
            let lane = result.laneChanges
            await MainActor.run {
                self.leftTurns += left
                self.rightTurns += right
                self.laneChanges += lane
            }
            let totals = await RecordingActor.shared.headingTotals()
            return (totals.left, totals.right, totals.lane)
        }
        return nil
    }

    // MARK: - Drive stats update

    func updateCurrentDrive() {
        guard var drive = currentDrive,
              let first = richRoutePoints.first,
              let last = richRoutePoints.last else { return }

        drive.startLatitude  = first.lat
        drive.startLongitude = first.lng
        drive.endLatitude    = last.lat
        drive.endLongitude   = last.lng

        drive.distance = runningDistanceMeters
        if let start = recordingStartTime {
            drive.duration = Date().timeIntervalSince(start)
        }

        if runningSpeedStats.count > 0 {
            drive.maxSpeed = runningSpeedStats.max
            drive.minSpeed = runningSpeedStats.min
            drive.avgSpeed = runningSpeedStats.avg
        }

        drive.stoppedTime = stoppedTimeTracker.totalStoppedTime(at: Date())
        drive.leftTurns = leftTurns; drive.rightTurns = rightTurns
        drive.brakeEvents = brakeEvents; drive.laneChanges = laneChanges
        drive.maxAcceleration = maxAcceleration; drive.maxDeceleration = maxDeceleration
        drive.peakGForce = peakGForce; drive.topCornerSpeed = topCornerSpeed
        drive.best060Time = best060Time

        currentDrive = drive
    }
}

/// Compute the longitudinal+lat G-force magnitude for a sample.
/// Mirrors the original logic that lived inside processLocationHeavy.
private func computedGForce(
    accel: Double,
    location: CLLocation,
    prev: CLLocation,
    speed: Double,
    dt: TimeInterval
) -> Double {
    var latAccel = 0.0
    if location.course >= 0 && prev.course >= 0 && speed > 1 {
        var dh = location.course - prev.course
        if dh > 180 { dh -= 360 }
        if dh < -180 { dh += 360 }
        let omega = (dh * .pi / 180) / dt
        latAccel = speed * omega
    }
    let lonG = accel / 9.81
    let latG = abs(latAccel) / 9.81
    return (lonG * lonG + latG * latG).squareRoot()
}

private extension Double {
    var metersToMiles: Double { self / 1609.344 }
}
