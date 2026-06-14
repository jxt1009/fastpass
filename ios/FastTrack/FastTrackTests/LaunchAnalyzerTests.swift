import XCTest
@testable import FastTrack

final class LaunchAnalyzerTests: XCTestCase {
    private func makeStream(elapsed: Double, startSpeed: Double = 0.0) -> [(TimeInterval, Double, Bool, Double)] {
        let t0: TimeInterval = 1000.0
        var out: [(TimeInterval, Double, Bool, Double)] = []
        for i in 0..<200 {
            out.append((t0 + Double(i) * 0.01, startSpeed, true, 1.0))
        }
        let targetMps = 60.0 / 2.23694
        let steps = Int(elapsed / 0.01)
        for i in 0...steps {
            let frac = Double(i) / Double(steps)
            let speed = targetMps * frac
            out.append((t0 + 2.0 + Double(i) * 0.01, speed, false, 0.0))
        }
        return out
    }

    func test_findsLaunch_withinTolerance() {
        let stream = makeStream(elapsed: 2.5)
        let analyzer = LaunchAnalyzer()
        let attempts = analyzer.analyze(stream: stream)
        XCTAssertFalse(attempts.isEmpty)
        guard let best = attempts.min(by: { $0.elapsedSeconds < $1.elapsedSeconds }) else { return }
        XCTAssertEqual(best.elapsedSeconds, 2.5, accuracy: 0.05)
        XCTAssertGreaterThan(best.confidence, 0.0)
    }
}
