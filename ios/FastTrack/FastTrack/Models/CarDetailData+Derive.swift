import Foundation

// MARK: - PersonalBests

enum PersonalBests {
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

// MARK: - Free helpers

func resolveTopSpeed(
    carId: String,
    stats: CarStats?,
    drives: [Drive]
) -> (Double?, Date?) {
    let (trueSpeed, trueDrive) = PersonalBests.trueTopSpeed(carId: carId, drives: drives)
    if trueSpeed > 0 {
        return (trueSpeed, trueDrive?.startTime)
    }
    if let stats, stats.bestTopSpeed > 0 {
        return (stats.bestTopSpeed, nil)
    }
    return (nil, nil)
}

func resolveZeroToSixty(
    carId: String,
    stats: CarStats?,
    drives: [Drive]
) -> (Double?, Date?) {
    let (trueTime, trueDrive) = PersonalBests.trueZeroToSixty(carId: carId, drives: drives)
    if trueTime > 0 {
        return (trueTime, trueDrive?.startTime)
    }
    if let stats, let t = stats.bestZeroToSixty, t > 0 {
        return (t, nil)
    }
    return (nil, nil)
}

func computeDrivingStyle(
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

// MARK: - Free function (pure derive logic)

let sparklineCap = 30
let confettiWindowSeconds: TimeInterval = 7 * 24 * 3600

func deriveCarDetailData(
    car: UserCar,
    drives: [Drive],
    carStats: CarStats?,
    achievements: [Achievement],
    now: Date,
    calculateSmoothness: ([Drive]) -> Double = { CarStatsManager.shared.calculateSmoothnessScore(for: $0) }
) -> CarDetailData {
    let carDrives = drives
        .filter { $0.carId == car.id }
        .sorted { $0.startTime < $1.startTime }

    let recent = Array(carDrives.suffix(sparklineCap))
    let points = recent.map { $0.maxSpeed }

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

    let (bestTopSpeed, topSpeedPBDate) = resolveTopSpeed(
        carId: car.id,
        stats: carStats,
        drives: carDrives
    )

    let (bestZeroToSixty, zeroSixtyPBDate) = resolveZeroToSixty(
        carId: car.id,
        stats: carStats,
        drives: carDrives
    )

    let style = computeDrivingStyle(stats: carStats, drives: carDrives)

    let carAchievements = achievements
        .filter { achievement in
            guard let sourceDriveId = achievement.sourceDriveId else { return false }
            return drives.contains { $0.id == sourceDriveId && $0.carId == car.id }
        }

    let recentPBUnlocks = carAchievements.compactMap { achievement -> (id: String, unlocked: Date)? in
        guard let unlocked = achievement.unlockedDate else { return nil }
        let interval = now.timeIntervalSince(unlocked)
        guard interval >= 0 && interval <= confettiWindowSeconds else { return nil }
        return (achievement.id, unlocked)
    }

    let confetti = !recentPBUnlocks.isEmpty
    let confettiToken = recentPBUnlocks
        .sorted { lhs, rhs in
            if lhs.unlocked != rhs.unlocked { return lhs.unlocked < rhs.unlocked }
            return lhs.id < rhs.id
        }
        .map { "\($0.id):\(Int($0.unlocked.timeIntervalSince1970))" }
        .joined(separator: "|")

    let smoothnessScore = carStats?.smoothnessScore ?? 0

    let speeds = carDrives.map(\.maxSpeed)
    let mean = speeds.reduce(0, +) / Double(max(1, speeds.count))
    let variance = speeds.map { pow($0 - mean, 2) }.reduce(0, +) / Double(max(1, speeds.count))
    let cv = mean > 0 ? sqrt(variance) / mean : 0
    let consistencyScore = max(0, min(100, 100 - cv * 150))

    let peakLateralG = carStats?.bestLateralG ?? carDrives.map(\.peakGForce).max() ?? 0

    let bestZeroToSixtyTime = bestZeroToSixty

    let recentSorted = carDrives.sorted { $0.startTime > $1.startTime }
    let recentForTrendsNewestFirst = Array(recentSorted.prefix(5))
    let recentForTrends = recentForTrendsNewestFirst.reversed()
    let recentDrives = recentForTrendsNewestFirst

    let distanceTrendPoints = recentForTrends.map { $0.distance }

    let smoothnessTrendPoints = recentForTrends.map { drive in
        calculateSmoothness([drive])
    }

    let prevPeriodAvgMaxSpeed: Double? = {
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
        confettiTriggerToken: confettiToken.isEmpty ? nil : confettiToken,
        recentPBCount: recentPBUnlocks.count,
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

// MARK: - Extension (thin wrapper)

extension CarDetailData {
    static func derive(
        car: UserCar,
        drives: [Drive],
        carStats: CarStats?,
        achievements: [Achievement],
        now: Date
    ) -> CarDetailData {
        deriveCarDetailData(
            car: car,
            drives: drives,
            carStats: carStats,
            achievements: achievements,
            now: now
        )
    }
}
