import Foundation
import CoreLocation

extension DriveManager {

    // MARK: - Location processing

    internal func processLocation(_ location: CLLocation) {
        // Skip very old locations (more than 5 seconds old)
        let age = abs(location.timestamp.timeIntervalSinceNow)
        if age > 5.0 {
            #if DEBUG
            print("⚠️ Skipping old location (age: \(age)s)")
            #endif
            return
        }

        #if DEBUG
        print("📍 Processing location: speed=\(location.speed), accuracy=\(location.horizontalAccuracy)m, course=\(location.course)")
        #endif

        // Basic processing on main thread for UI updates
        let speed = routePointSpeed(for: location)
        let speedMph = speed * 2.23694

        recordingLocations.append(location)
        routeCoordinates.append(location.coordinate)
        // Track rich route point with the latest fused speed where possible.
        richRoutePoints.append((
            lat: location.coordinate.latitude,
            lng: location.coordinate.longitude,
            speed: speed,
            ts: location.timestamp.timeIntervalSince1970
        ))

        #if DEBUG
        print("📊 Recorded \(recordingLocations.count) locations, current speed: \(speedMph) mph")
        #endif

        // Update basic stats immediately for UI responsiveness
        if speed > currentMaxSpeed {
            currentMaxSpeed = speed
            #if DEBUG
            print("🏁 New max speed: \(currentMaxSpeed * 2.23694) mph")
            #endif
        }

        // Offload heavy calculations to background queue to prevent UI freezing
        Task.detached { [weak self] in
            await self?.processLocationHeavy(location, speed: speed, speedMph: speedMph)
        }

        // Update drive stats on main thread (lightweight)
        updateCurrentDrive()
        if publishThrottler.shouldPublish() {
            updateLiveActivity(speedMph: speedMph, distanceMiles: currentDrive?.distance.metersToMiles ?? 0)
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

    func processHeadingBackground(course: Double, speed: Double, timestamp: Date) async -> (left: Int, right: Int, lanes: Int)? {
        let window = await MainActor.run { self.headingWindow }
        guard let window = window else {
            await MainActor.run {
                self.headingWindow = (course, timestamp)
                self.headingHistory.append((course, timestamp))
            }
            return nil
        }

        let windowAge = timestamp.timeIntervalSince(window.time)
        guard windowAge >= 2.0 else { return nil }

        var delta = course - window.course
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }

        let lastTurnTime = await MainActor.run { self.lastTurnOrLaneTime }
        let gap = lastTurnTime.map { timestamp.timeIntervalSince($0) } ?? 100

        // Append to rolling history and check for sustained curve before classifying
        let inCurve = await MainActor.run { () -> Bool in
            self.headingHistory.append((course, timestamp))
            // Trim entries older than 10 seconds
            let cutoff = timestamp.addingTimeInterval(-10)
            self.headingHistory.removeAll { $0.time < cutoff }
            return self.isSustainedCurve(upTo: timestamp)
        }

        var leftTurns = 0, rightTurns = 0, laneChanges = 0

        if abs(delta) > 35 && gap > 4 {
            if delta > 0 { rightTurns = 1 } else { leftTurns = 1 }
        } else if abs(delta) >= 10 && abs(delta) <= 35 && speed > 6.7 && gap > 3 && !inCurve {
            // Only count as lane change when NOT in a sustained ramp/curve
            laneChanges = 1
        }

        await MainActor.run { self.headingWindow = (course, timestamp) }

        return leftTurns + rightTurns + laneChanges > 0 ? (leftTurns, rightTurns, laneChanges) : nil
    }

    /// Returns true if the heading history shows a sustained curve (ramp, cloverleaf, etc.)
    /// rather than a brief lane-change deflection. A sustained curve is defined as ≥5 seconds
    /// of consistent heading rotation in a single direction totalling >40°.
    func isSustainedCurve(upTo timestamp: Date) -> Bool {
        let windowStart = timestamp.addingTimeInterval(-8)
        let window = headingHistory.filter { $0.time >= windowStart }
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
        // All deltas in same rotational direction = sustained curve
        let allSame = signs.allSatisfy { $0 == signs[0] }
        return allSame
    }

    // MARK: - Drive stats update

    func updateCurrentDrive() {
        guard var drive = currentDrive,
              let firstLoc = recordingLocations.first,
              let lastLoc  = recordingLocations.last else {
            #if DEBUG
            print("⚠️ UpdateCurrentDrive failed: currentDrive=\(currentDrive != nil), locations=\(recordingLocations.count)")
            #endif
            return
        }

        drive.startLatitude  = firstLoc.coordinate.latitude
        drive.startLongitude = firstLoc.coordinate.longitude
        drive.endLatitude    = lastLoc.coordinate.latitude
        drive.endLongitude   = lastLoc.coordinate.longitude

        var totalDist: Double = 0
        for i in 1..<recordingLocations.count {
            totalDist += recordingLocations[i-1].distance(from: recordingLocations[i])
        }
        drive.distance = totalDist
        if let start = recordingStartTime {
            drive.duration = Date().timeIntervalSince(start)
            #if DEBUG
            print("⏱️ Drive duration updated: \(drive.duration) seconds")
            #endif
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
        #if DEBUG
        print("✅ Current drive updated: distance=\(totalDist), duration=\(drive.duration), maxSpeed=\(drive.maxSpeed)")
        #endif
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
