import Foundation

struct LaunchAnalyzer {
    struct Config {
        var accelerationSlopeMps2: Double = 1.5
        var minEventDurationSamples: Int = 5
        var backwardSearchWindow: Int = 200
        var stationarySpeedMps: Double = 0.3
        var stationaryConfidenceThreshold: Double = 0.8
        var targetSpeedMph: Double = 60.0
        var minValidElapsed: Double = 1.0
        var maxValidElapsed: Double = 30.0
    }

    var config: Config = .init()

    func analyze(stream: [(TimeInterval, Double, Bool, Double)]) -> [ZeroToSixtyAttempt] {
        guard stream.count > 10 else { return [] }

        var events: [(startIndex: Int, endIndex: Int)] = []
        var runStart: Int?
        for i in 1..<stream.count {
            let dt = stream[i].0 - stream[i - 1].0
            guard dt > 0 else { continue }
            let slope = (stream[i].1 - stream[i - 1].1) / dt
            if slope >= config.accelerationSlopeMps2 {
                if runStart == nil { runStart = i - 1 }
            } else {
                if let s = runStart, i - 1 - s >= config.minEventDurationSamples {
                    events.append((s, i - 1))
                }
                runStart = nil
            }
        }
        if let s = runStart, stream.count - 1 - s >= config.minEventDurationSamples {
            events.append((s, stream.count - 1))
        }

        var attempts: [ZeroToSixtyAttempt] = []
        for event in events {
            guard let attempt = processEvent(event, in: stream) else { continue }
            attempts.append(attempt)
        }
        return attempts
    }

    private func processEvent(
        _ event: (startIndex: Int, endIndex: Int),
        in stream: [(TimeInterval, Double, Bool, Double)]
    ) -> ZeroToSixtyAttempt? {
        let searchStart = max(0, event.startIndex - config.backwardSearchWindow)
        var launchStartIndex = event.startIndex
        for i in stride(from: event.startIndex, through: searchStart, by: -1) {
            let (_, speed, locked, conf) = stream[i]
            if speed < config.stationarySpeedMps && (locked || conf >= config.stationaryConfidenceThreshold) {
                launchStartIndex = i + 1
                break
            }
        }
        guard launchStartIndex < event.endIndex else { return nil }

        let startTime = stream[launchStartIndex].0
        let targetMps = config.targetSpeedMph / 2.23694

        var crossingTime: TimeInterval?
        for i in launchStartIndex..<stream.count {
            if stream[i].1 >= targetMps {
                if i > launchStartIndex {
                    let prev = stream[i - 1]
                    let curr = stream[i]
                    let dSpeed = curr.1 - prev.1
                    let dTime = curr.0 - prev.0
                    if dSpeed > 0, dTime > 0 {
                        let frac = (targetMps - prev.1) / dSpeed
                        let clamped = min(max(frac, 0), 1)
                        crossingTime = prev.0 + dTime * clamped
                    } else {
                        crossingTime = curr.0
                    }
                } else {
                    crossingTime = stream[i].0
                }
                break
            }
        }
        guard let crossingTime else { return nil }
        let elapsed = crossingTime - startTime
        guard elapsed >= config.minValidElapsed, elapsed <= config.maxValidElapsed else { return nil }

        let confidence = computeConfidence(startIndex: launchStartIndex, endIndex: event.endIndex, in: stream)

        return ZeroToSixtyAttempt(
            startIndex: launchStartIndex,
            endIndex: event.endIndex,
            startTimestamp: startTime,
            endTimestamp: crossingTime,
            elapsedSeconds: elapsed,
            startLatitude: 0,
            startLongitude: 0,
            endLatitude: 0,
            endLongitude: 0,
            confidence: confidence,
            legacy: false
        )
    }

    private func computeConfidence(
        startIndex: Int,
        endIndex: Int,
        in stream: [(TimeInterval, Double, Bool, Double)]
    ) -> Double {
        var score: Double = 1.0
        let elapsedBeforeLaunch = startIndex > 0 ? stream[startIndex].0 - stream[0].0 : 0
        if elapsedBeforeLaunch < 0.5 { score -= 0.2 }
        if endIndex - startIndex < 50 { score -= 0.1 }
        if endIndex - startIndex > 1 {
            var deltas: [Double] = []
            for i in (startIndex + 1)...endIndex {
                deltas.append(stream[i].1 - stream[i - 1].1)
            }
            let mean = deltas.reduce(0, +) / Double(deltas.count)
            let variance = deltas.map { pow($0 - mean, 2) }.reduce(0, +) / Double(deltas.count)
            let std = sqrt(variance)
            let cv = mean > 0 ? std / mean : 1
            if cv > 0.5 { score -= 0.2 }
        }
        return max(0, min(1, score))
    }
}
