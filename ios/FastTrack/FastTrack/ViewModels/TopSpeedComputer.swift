import Foundation

struct TopSpeedComputer {
    struct Result: Equatable {
        let fusedMaxSpeed: Double
        let gpsMaxSpeed: Double
        let maxSpeed: Double
    }

    static func compute(
        speedStream: [(TimeInterval, Double, Bool, Double)],
        gpsMaxSpeed: Double,
        nearestGpsAccuracyMeters: Double,
        windowSize: Int = 50
    ) -> Result {
        let fusedMax = rollingMedianMax(stream: speedStream.map { $0.1 }, window: windowSize)
        let gpsConfident = nearestGpsAccuracyMeters > 0 && nearestGpsAccuracyMeters < 50
        let maxSpeed: Double
        if gpsConfident, gpsMaxSpeed > 0 {
            maxSpeed = max(gpsMaxSpeed, fusedMax * 0.95)
        } else {
            maxSpeed = fusedMax
        }
        return Result(fusedMaxSpeed: fusedMax, gpsMaxSpeed: gpsMaxSpeed, maxSpeed: maxSpeed)
    }

    private static func rollingMedianMax(stream: [Double], window: Int) -> Double {
        guard !stream.isEmpty else { return 0 }
        var best: Double = stream[0]
        let n = stream.count
        let half = window / 2
        for i in 0..<n {
            let lo = max(0, i - half)
            let hi = min(n, i + half + 1)
            let slice = stream[lo..<hi].sorted()
            let median = slice[slice.count / 2]
            if median > best { best = median }
        }
        return best
    }
}
