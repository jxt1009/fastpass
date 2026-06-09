import Foundation

// MARK: - CarDetailData derivation
//
// Pure functions that take everything `CarDetailView` needs (the car,
// the user's drives, the cached `CarStats` blob, and the achievements
// cache) and return a fully-built `CarDetailData`. `now` is injected so
// the confetti-eligible test can pin the clock without monkey-patching
// `Date()`.
//
// All inputs are value types; no `Date()`, no shared singletons, no
// side effects. The view layer is a thin wrapper.

extension CarDetailData {

    /// Maximum number of points the sparkline renders. Older drives fall
    /// off the left edge so the trend stays current. The number matches
    /// the plan and the PR #57 car-centric leaderboard row cap so the
    /// two stay visually consistent.
    static let sparklineCap = 30

    /// Window for the confetti trigger. A PB is considered "new" if its
    /// `unlockedDate` is within this many seconds of `now`.
    static let confettiWindowSeconds: TimeInterval = 7 * 24 * 3600

    /// Builds a `CarDetailData` for the given car from the supplied
    /// drives, per-car stats blob, and achievements. `now` is injected
    /// so the confetti-eligible check is testable.
    static func derive(
        car: UserCar,
        drives: [Drive],
        carStats: CarStats?,
        achievements: [Achievement],
        now: Date
    ) -> CarDetailData {
        // Filter to drives for this car, ordered by start time ascending
        // so the sparkline reads left-to-right chronologically.
        let carDrives = drives
            .filter { $0.carId == car.id }
            .sorted { $0.startTime < $1.startTime }

        // Sparkline = maxSpeed per drive, capped to the most recent N.
        // Drives with `maxSpeed == 0` are kept (they're still real
        // measurements) so the line dips to the floor; the chart can
        // optionally hide them visually. We don't filter here.
        let recent = Array(carDrives.suffix(sparklineCap))
        let points = recent.map { $0.maxSpeed }

        // The PB point: the index of the maximum in the cap'd series.
        // Ties go to the first occurrence (the oldest PB within the
        // window) so the marker is stable across re-derives.
        let pbIndex: Int? = {
            guard !points.isEmpty else { return nil }
            var bestIdx = 0
            var bestValue = points[0]
            for i in 1..<points.count where points[i] > bestValue {
                bestValue = points[i]
                bestIdx = i
            }
            return bestIdx
        }()

        // Resolve the per-car top speed and the date of the drive that
        // set it. Prefer the `CarStats` blob as the authoritative value
        // (it's the union of local + server-side data) and use the
        // filtered drives only to find the timestamp. Fall back to
        // computing from the drives when stats are missing.
        let (bestTopSpeed, topSpeedPBDate) = resolveTopSpeed(
            stats: carStats,
            drives: carDrives
        )

        // Same idea for 0-60: prefer the blob, fall back to drives.
        let (bestZeroToSixty, zeroSixtyPBDate) = resolveZeroToSixty(
            stats: carStats,
            drives: carDrives
        )

        let style = computeDrivingStyle(stats: carStats, drives: carDrives)

        // Per-car achievements: any achievement whose `sourceDriveId`
        // points at a drive tagged with this car's id. We look the
        // drive up in the (full) drives list so the test for source
        // drive is independent of the cap we apply to the sparkline.
        let carAchievements = achievements
            .filter { achievement in
                guard let sourceDriveId = achievement.sourceDriveId else { return false }
                return drives.contains { $0.id == sourceDriveId && $0.carId == car.id }
            }

        let confetti = carAchievements.contains { achievement in
            guard let unlocked = achievement.unlockedDate else { return false }
            // Reject future-dated unlocks explicitly: a negative
            // interval would otherwise pass the `<= window` check
            // whenever the device clock drifts.
            let interval = now.timeIntervalSince(unlocked)
            return interval >= 0 && interval <= confettiWindowSeconds
        }

        // New fields computation
        let smoothnessScore = carStats?.smoothnessScore ?? 0

        let speeds = carDrives.map(\.maxSpeed)
        let mean = speeds.reduce(0, +) / Double(max(1, speeds.count))
        let variance = speeds.map { pow($0 - mean, 2) }.reduce(0, +) / Double(max(1, speeds.count))
        let cv = mean > 0 ? sqrt(variance) / mean : 0
        let consistencyScore = max(0, min(100, 100 - cv * 150))

        let peakLateralG = carStats?.bestLateralG ?? carDrives.map(\.peakGForce).max() ?? 0

        let bestZeroToSixtyTime = bestZeroToSixty

        let recentSorted = carDrives.sorted { $0.startTime > $1.startTime }
        let recentForTrends = Array(recentSorted.prefix(5))
        let recentDrives = recentForTrends

        let distanceTrendPoints = recentForTrends.map { $0.distance }

        let smoothnessTrendPoints = recentForTrends.map { drive in
            guard drive.maxSpeed > 0, drive.duration > 0 else { return 50.0 }
            let speedEfficiency = drive.avgSpeed / max(drive.maxSpeed, 1)
            let accelPenalty = min(drive.maxAcceleration / 9.81, 1.0) * 15
            let decelPenalty = min(drive.maxDeceleration / 9.81, 1.0) * 15
            let gPenalty = min(drive.peakGForce / 2.0, 1.0) * 20
            let brakePenalty = min(Double(drive.brakeEvents) * 2.0, 20)
            return max(0, min(100, speedEfficiency * 100 - accelPenalty - decelPenalty - gPenalty - brakePenalty))
        }

        let prevPeriodAvgMaxSpeed: Double? = {
            let now = Date()
            let lastMonthStart = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
            let prevMonthStart = Calendar.current.date(byAdding: .month, value: -2, to: now) ?? now
            let prevDrives = drives.filter { $0.carId == car.id && $0.startTime >= prevMonthStart && $0.startTime < lastMonthStart }
            guard !prevDrives.isEmpty else { return nil }
            let total = prevDrives.reduce(0.0) { $0 + $1.maxSpeed }
            return total / Double(prevDrives.count)
        }()

        return CarDetailData(
            car: car,
            stats: carStats,
            sparklinePoints: points,
            pbSparklineIndex: pbIndex,
            bestTopSpeed: bestTopSpeed,
            bestZeroToSixty: bestZeroToSixty,
            topSpeedPBDate: topSpeedPBDate,
            zeroSixtyPBDate: zeroSixtyPBDate,
            drivingStyle: style,
            achievementPBs: carAchievements,
            confettiEligible: confetti,
            smoothnessScore: smoothnessScore,
            consistencyScore: consistencyScore,
            peakLateralG: peakLateralG,
            bestZeroToSixtyTime: bestZeroToSixtyTime,
            recentDrives: recentDrives,
            distanceTrendPoints: distanceTrendPoints,
            smoothnessTrendPoints: smoothnessTrendPoints,
            prevPeriodAvgMaxSpeed: prevPeriodAvgMaxSpeed
        )
    }

    // MARK: - Internal helpers (exposed via internal access for tests)

    /// Resolves the per-car best top speed (m/s) plus the drive that
    /// produced it. When the stats blob is missing or zero, falls back
    /// to scanning the supplied drives. When neither source has data,
    /// returns `(nil, nil)`.
    static func resolveTopSpeed(
        stats: CarStats?,
        drives: [Drive]
    ) -> (Double?, Date?) {
        if let stats, stats.bestTopSpeed > 0 {
            let matchingDrive = drives
                .filter { $0.maxSpeed == stats.bestTopSpeed }
                .min { $0.startTime < $1.startTime }
            return (stats.bestTopSpeed, matchingDrive?.startTime)
        }
        guard let maxDrive = drives.max(by: { $0.maxSpeed < $1.maxSpeed }),
              maxDrive.maxSpeed > 0 else {
            return (nil, nil)
        }
        return (maxDrive.maxSpeed, maxDrive.startTime)
    }

    /// Resolves the per-car best 0-60 (seconds) plus the drive that
    /// produced it. `best060Time` is `Double?` on the stats blob, so
    /// we treat nil/zero as "no time". The local-scan fallback filters
    /// out non-positive times for the same reason — a sentinel `0` in
    /// the drive list must not become the minimum.
    static func resolveZeroToSixty(
        stats: CarStats?,
        drives: [Drive]
    ) -> (Double?, Date?) {
        if let stats, let t = stats.bestZeroToSixty, t > 0 {
            // The drive that set the PB is the one with the matching
            // best060Time. Ties go to the earliest.
            let matchingDrive = drives
                .filter { $0.best060Time == t }
                .min { $0.startTime < $1.startTime }
            return (t, matchingDrive?.startTime)
        }
        let positiveTimes = drives
            .compactMap { $0.best060Time }
            .filter { $0 > 0 }
        guard let best = positiveTimes.min(),
              let bestDrive = drives.first(where: { $0.best060Time == best }) else {
            return (nil, nil)
        }
        return (best, bestDrive.startTime)
    }

    /// Classifies a driving style from the car's per-car stats. The
    /// `sporty` / `smooth` checks are independent of each other and
    /// short-circuit to `.balanced` when neither fires. `.unknown`
    /// means "no drives yet" — both the drives list and the stats
    /// blob's `totalDrives` are zero, so classifying further would
    /// be misleading. We treat either signal as "has driven" so
    /// callers can hand in just the stats blob (e.g. when the local
    /// `DriveManager` cache hasn't been hydrated yet).
    static func computeDrivingStyle(
        stats: CarStats?,
        drives: [Drive]
    ) -> DrivingStyle {
        let stats = stats ?? CarStats(carId: "")
        let hasDriven = !drives.isEmpty || stats.totalDrives > 0
        guard hasDriven else { return .unknown }
        let miles = stats.totalDistanceMiles
        guard miles > 0 else { return .balanced }
        let brakePerMile = Double(stats.totalBrakeEvents) / miles
        let topMph = stats.bestTopSpeedMph
        if brakePerMile > 2.0, topMph > 90 { return .sporty }
        if brakePerMile < 0.5, stats.totalDrives >= 5 { return .smooth }
        return .balanced
    }
}
