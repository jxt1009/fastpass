import XCTest
import CoreLocation
@testable import FastTrack

final class IncrementalDistanceTests: XCTestCase {

    func test_incrementalDistanceMatchesFullSweep() {
        var coords: [CLLocationCoordinate2D] = []
        for i in 0..<10 {
            coords.append(CLLocationCoordinate2D(latitude: 37.0 + Double(i) * 0.0009, longitude: -122.0))
        }
        let locs = coords.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        var reference: Double = 0
        for i in 1..<locs.count {
            reference += locs[i-1].distance(from: locs[i])
        }

        var cumulative: Double = 0
        var last: CLLocation?
        for loc in locs {
            if let last = last {
                cumulative += last.distance(from: loc)
            }
            last = loc
        }
        XCTAssertEqual(cumulative, reference, accuracy: 0.5)
    }

    func test_zeroDistanceForSinglePoint() {
        let loc = CLLocation(latitude: 0, longitude: 0)
        var cumulative: Double = 0
        var last: CLLocation?
        if let last = last {
            cumulative += last.distance(from: loc)
        }
        last = loc
        XCTAssertEqual(cumulative, 0)
    }
}
