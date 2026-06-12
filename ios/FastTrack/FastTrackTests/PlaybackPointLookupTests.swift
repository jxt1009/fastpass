import XCTest
@testable import FastTrack

final class PlaybackPointLookupTests: XCTestCase {

    func test_nearestIndex_binarySearch() {
        let timestamps: [TimeInterval] = [1000, 1001, 1002, 1003, 1004]
        let index = findNearestIndex(timestamps, target: 1002.5)
        XCTAssertEqual(index, 3)
    }

    func test_nearestIndex_exactMatch() {
        let timestamps: [TimeInterval] = [1000, 1001, 1002, 1003]
        let index = findNearestIndex(timestamps, target: 1002)
        XCTAssertEqual(index, 2)
    }

    func test_nearestIndex_beforeFirst() {
        let timestamps: [TimeInterval] = [1000, 1001, 1002]
        let index = findNearestIndex(timestamps, target: 999)
        XCTAssertEqual(index, 0)
    }

    func test_nearestIndex_afterLast() {
        let timestamps: [TimeInterval] = [1000, 1001, 1002]
        let index = findNearestIndex(timestamps, target: 2000)
        XCTAssertEqual(index, 2)
    }

    func test_nearestIndex_emptyReturnsZero() {
        let index = findNearestIndex([], target: 1000)
        XCTAssertEqual(index, 0)
    }

    private func findNearestIndex(_ timestamps: [TimeInterval], target: TimeInterval) -> Int {
        guard !timestamps.isEmpty else { return 0 }
        var lo = 0
        var hi = timestamps.count - 1
        while lo < hi {
            let mid = (lo + hi) / 2
            if timestamps[mid] < target {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        if lo > 0 && lo < timestamps.count {
            let prev = lo - 1
            if abs(timestamps[prev] - target) < abs(timestamps[lo] - target) {
                return prev
            }
        }
        return lo
    }
}
