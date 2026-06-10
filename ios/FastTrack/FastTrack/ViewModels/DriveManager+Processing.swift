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

        // Perform heavy calculations on background thread
        var updates: (
            acceleration: Double?,
            deceleration: Double?,
            brakeCount: Int,
            gForce: Double?,
            cornerSpeed: Double?,
            turnData: (left: Int, right: Int, lanes: Int)?
        ) = (nil, nil, 0, nil, nil, nil)

        // Get recording data safely
        let recordingCount = await MainActor.run { self.recordingLocations.count }
        guard recordingCount >= 2 else {
            return
        }

        let (prev, prevRecordedSpeed) = await MainActor.run {
            (
                self.recordingLocations[recordingCount - 2],
                self.richRoutePoints[recordingCount - 2].speed
            )
        }

        let dt = ts.timeIntervalSince(prev.timestamp)
        let prevSpeed = prevRecordedSpeed

        // Only process if time delta is reasonable (background calculation)
        guard dt > 0 && dt < 5 else {
            return
        }

        // Skip acceleration/G-force calculation if either GPS reading has poor speed accuracy.
        // speedAccuracy is in m/s std dev; -1 means unavailable. Threshold: 2 m/s (~4.5 mph).
        let speedAccuracyOK = location.speedAccuracy > 0 && location.speedAccuracy < 2.0
                           && prev.speedAccuracy > 0 && prev.speedAccuracy < 2.0

        // Heavy calculations on background thread
        let rawAccel = (speed - prevSpeed) / dt
        // Physical sanity cap: > 5G is impossible on a public road; clamp to prevent GPS spikes
        let maxPhysicalAccelMS2 = 5.0 * 9.81  // ~49 m/s²
        let accel = max(-maxPhysicalAccelMS2, min(maxPhysicalAccelMS2, rawAccel))
        let currentMaxAccel = await MainActor.run { self.maxAcceleration }
        let currentMaxDecel = await MainActor.run { self.maxDeceleration }

        if speedAccuracyOK {
            updates.acceleration = accel > currentMaxAccel ? accel : nil
            updates.deceleration = -accel > currentMaxDecel ? -accel : nil
        }

        // Brake event detection (uses raw accel; doesn't need accuracy gate — threshold is high enough)
        if accel < -2.5 {
            let lastBrake = await MainActor.run { self.lastBrakeTime }
            let gap = lastBrake.map { ts.timeIntervalSince($0) } ?? 100
            if gap > 3 {
                updates.brakeCount = 1
            }
        }

        // G-force calculation — only when GPS accuracy is reliable
        let currentTopCornerSpeed = await MainActor.run { self.topCornerSpeed }
        if speedAccuracyOK {
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
            let totalG = (lonG * lonG + latG * latG).squareRoot()

            updates.gForce = totalG
            if latG > 0.15 && speed > currentTopCornerSpeed {
                updates.cornerSpeed = speed
            }
        }

        // Turn detection (background processing)
        if location.course >= 0 && speed > 2.2 {
            updates.turnData = await processHeadingBackground(course: location.course, speed: speed, timestamp: ts)
        }

        // Apply all updates atomically on main thread
        await MainActor.run {
            // Performance metrics
            if let accel = updates.acceleration {
                self.maxAcceleration = accel
            }
            if let decel = updates.deceleration {
                self.maxDeceleration = decel
            }
            if updates.brakeCount > 0 {
                self.brakeEvents += 1
                self.lastBrakeTime = ts
                self.recordedRouteEvents.append((
                    type: "brake",
                    lat: location.coordinate.latitude,
                    lng: location.coordinate.longitude,
                    ts: ts.timeIntervalSince1970
                ))
            }
            if let gForce = updates.gForce {
                if gForce > self.peakGForce { self.peakGForce = gForce }
                self.currentGForce = gForce
            }
            if let cornerSpeed = updates.cornerSpeed {
                self.topCornerSpeed = cornerSpeed
            }

            // Turns
            if let turnData = updates.turnData {
                self.leftTurns += turnData.left
                self.rightTurns += turnData.right
                self.laneChanges += turnData.lanes
                if turnData.left > 0 {
                    self.recordedRouteEvents.append((type: "turn_left", lat: location.coordinate.latitude, lng: location.coordinate.longitude, ts: ts.timeIntervalSince1970))
                }
                if turnData.right > 0 {
                    self.recordedRouteEvents.append((type: "turn_right", lat: location.coordinate.latitude, lng: location.coordinate.longitude, ts: ts.timeIntervalSince1970))
                }
                if turnData.lanes > 0 {
                    self.recordedRouteEvents.append((type: "lane_change", lat: location.coordinate.latitude, lng: location.coordinate.longitude, ts: ts.timeIntervalSince1970))
                }
                if turnData.left > 0 || turnData.right > 0 || turnData.lanes > 0 {
                    self.lastTurnOrLaneTime = ts
                }
            } else if speed < 0.5 {
                self.headingWindow = nil
            }
        }
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

private extension Double {
    var metersToMiles: Double { self / 1609.344 }
}
