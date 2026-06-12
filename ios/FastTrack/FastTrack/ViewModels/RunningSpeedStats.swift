import Foundation

/// Incremental running statistics for the per-tick speed samples
/// emitted by `LocationManager` at ~25 Hz. Designed for O(1) ingest
/// so the recording hot path never has to rescan the full history.
///
/// Negative samples are filtered (treated as GPS glitches). Zero
/// samples are kept — they reflect a stationary car.
struct RunningSpeedStats: Equatable, Sendable {
    private(set) var count: Int = 0
    private(set) var min: Double = 0
    private(set) var max: Double = 0
    private(set) var sum: Double = 0

    var avg: Double { count > 0 ? sum / Double(count) : 0 }

    mutating func ingest(_ value: Double) {
        if value < 0 { return }  // filter negative glitches
        if count == 0 {
            min = value
            max = value
        } else {
            if value < min { min = value }
            if value > max { max = value }
        }
        sum += value
        count += 1
    }

    mutating func reset() {
        count = 0
        min = 0
        max = 0
        sum = 0
    }
}
