import XCTest
@testable import FastTrack

final class RunningSpeedStatsTests: XCTestCase {

    func test_emptyStatsReportZeros() {
        let s = RunningSpeedStats()
        XCTAssertEqual(s.count, 0)
        XCTAssertEqual(s.min, 0)
        XCTAssertEqual(s.max, 0)
        XCTAssertEqual(s.avg, 0)
    }

    func test_ingestSingleSample() {
        var s = RunningSpeedStats()
        s.ingest(10.0)
        XCTAssertEqual(s.count, 1)
        XCTAssertEqual(s.min, 10.0)
        XCTAssertEqual(s.max, 10.0)
        XCTAssertEqual(s.avg, 10.0)
    }

    func test_ingestManySamplesMatchesOnePassScan() {
        var s = RunningSpeedStats()
        let samples: [Double] = (0..<10_000).map { _ in Double.random(in: 0...50) }
        for v in samples { s.ingest(v) }
        XCTAssertEqual(s.count, samples.count)
        XCTAssertEqual(s.min, samples.min() ?? -1, accuracy: 1e-9)
        XCTAssertEqual(s.max, samples.max() ?? -1, accuracy: 1e-9)
        let expectedAvg = samples.reduce(0, +) / Double(samples.count)
        XCTAssertEqual(s.avg, expectedAvg, accuracy: 1e-6)
    }

    func test_ingestHandlesZeroAndNegative() {
        var s = RunningSpeedStats()
        s.ingest(0)
        s.ingest(-1)        // filtered (e.g. GPS glitch)
        s.ingest(15.0)
        XCTAssertEqual(s.count, 2)              // -1 is filtered
        XCTAssertEqual(s.min, 0)                // min over the 2 valid samples
        XCTAssertEqual(s.max, 15.0)
    }

    func test_resetClearsState() {
        var s = RunningSpeedStats()
        s.ingest(10.0); s.ingest(20.0)
        s.reset()
        XCTAssertEqual(s.count, 0)
        XCTAssertEqual(s.min, 0)
        XCTAssertEqual(s.max, 0)
        XCTAssertEqual(s.avg, 0)
    }
}
