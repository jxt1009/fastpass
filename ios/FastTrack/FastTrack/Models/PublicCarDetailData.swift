import Foundation

// MARK: - Public car detail (pure value type)

struct PublicCarDetailData {
    let car: UserCar
    let stats: CarStats?

    var bestTopSpeed: Double? {
        guard let stats else { return nil }
        guard stats.bestTopSpeed > 0 else { return nil }
        return stats.bestTopSpeed
    }

    var bestZeroToSixty: Double? {
        guard let stats, let time = stats.bestZeroToSixty, time > 0 else { return nil }
        return time
    }

    var drivingStyle: DrivingStyle {
        computeDrivingStyle(stats: stats, drives: [])
    }
}
