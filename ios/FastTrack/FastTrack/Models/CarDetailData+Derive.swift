import Foundation

// MARK: - PersonalBests
//
// Pure helper that computes the true current personal-best values for a
// single car directly from its drives — not from achievement source
// drives (which mark the drive that first crossed an unlock threshold,
// not necessarily the all-time best). Use this for the headline PB
// gauges in CarDetailView.

enum PersonalBests {
    /// The true all-time best top speed (m/s) across all drives for
    /// `carId`, together with the drive that produced it.
    /// Returns `(nil, nil)` when the car has no drives with
    /// a positive maxSpeed.
    static func trueTopSpeed(
        carId: String,
        drives: [Drive]
    ) -> (speed: Double, drive: Drive?) {
        let carDrives = drives.filter { $0.carId == carId && $0.maxSpeed > 0 }
        guard let best = carDrives.max(by: { $0.maxSpeed < $1.maxSpeed }) else {
            return (0, nil)
        }
        return (best.maxSpeed, best)
    }

    /// The true all-time best 0-60 time (seconds) across all drives for
    /// `carId`, together with the drive that produced it.
    /// Returns `(nil, nil)` when the car has no drives with a
    /// positive best060Time.
    static func trueZeroToSixty(
        carId: String,
        drives: [Drive]
    ) -> (time: Double, drive: Drive?) {
        let carDrives = drives.filter { $0.carId == carId }
        let candidates = carDrives.compactMap { drive -> (Drive, Double)? in
            guard let t = drive.best060Time, t > 0 else { return nil }
            return (drive, t)
        }
        guard let best = candidates.min(by: { $0.1 < $1.1 }) else {
            return (0, nil)
        }
        return (best.1, best.0)
    }
}

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
        // set it. Always scan actual drives for the true maximum so the
        // headline PB reflects the real all-time best, not the
        // achievement-source drive. Fall back to the `CarStats` blob
        // only when no drives are available locally.
        let (bestTopSpeed, topSpeedPBDate) = resolveTopSpeed(
            carId: car.id,
            stats: carStats,
            drives: carDrives
        )

        // Same idea for 0-60: true minimum from drive data first.
        let (bestZeroToSixty, zeroSixtyPBDate) = resolveZeroToSixty(
            carId: car.id,
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
            confettiEligible: confetti
        )
    }

    // MARK: - Internal helpers (exposed via internal access for tests)

    /// Resolves the per-car best top speed (m/s) plus the date of the
    /// drive that produced it. The true maximum is always computed from
    /// actual drive data via `PersonalBests.trueTopSpeed`. The `CarStats`
    /// blob is used only as a fallback when no drives are present locally
    /// (e.g. stats were restored from the server before drives loaded).
    /// Returns `(nil, nil)` when neither source has data.
    static func resolveTopSpeed(
        carId: String,
        stats: CarStats?,
        drives: [Drive]
    ) -> (Double?, Date?) {
        let (trueSpeed, trueDrive) = PersonalBests.trueTopSpeed(carId: carId, drives: drives)
        if trueSpeed > 0 {
            return (trueSpeed, trueDrive?.startTime)
        }
        // No drives available locally — fall back to the cached stats blob.
        if let stats, stats.bestTopSpeed > 0 {
            return (stats.bestTopSpeed, nil)
        }
        return (nil, nil)
    }

    /// Resolves the per-car best 0-60 (seconds) plus the date of the
    /// drive that produced it. The true minimum is always computed from
    /// actual drive data via `PersonalBests.trueZeroToSixty`. The
    /// `CarStats` blob is used only as a fallback when no drives are
    /// present locally. Non-positive sentinel values are filtered out
    /// in `PersonalBests` so a `0` in a legacy drive never becomes the
    /// all-time minimum.
    static func resolveZeroToSixty(
        carId: String,
        stats: CarStats?,
        drives: [Drive]
    ) -> (Double?, Date?) {
        let (trueTime, trueDrive) = PersonalBests.trueZeroToSixty(carId: carId, drives: drives)
        if trueTime > 0 {
            return (trueTime, trueDrive?.startTime)
        }
        // No drives available locally — fall back to the cached stats blob.
        if let stats, let t = stats.bestZeroToSixty, t > 0 {
            return (t, nil)
        }
        return (nil, nil)
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
