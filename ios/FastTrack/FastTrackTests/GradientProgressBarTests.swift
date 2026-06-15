import XCTest
import SwiftUI
@testable import FastTrack

final class GradientProgressBarTests: XCTestCase {

    func testFractionClampedAtZero() {
        let bar = GradientProgressBar(value: -10, range: 0...100, size: .compact)
        XCTAssertEqual(bar.fraction, 0.0, accuracy: 0.001)
    }

    func testFractionClampedAtOne() {
        let bar = GradientProgressBar(value: 200, range: 0...100, size: .compact)
        XCTAssertEqual(bar.fraction, 1.0, accuracy: 0.001)
    }

    func testFractionMidpoint() {
        let bar = GradientProgressBar(value: 50, range: 0...100, size: .compact)
        XCTAssertEqual(bar.fraction, 0.5, accuracy: 0.001)
    }

    func testCompactDimensions() {
        let bar = GradientProgressBar(value: 50, range: 0...100, size: .compact)
        XCTAssertEqual(bar.trackHeight, 5.0, accuracy: 0.001)
        XCTAssertEqual(bar.dotDiameter, 9.0, accuracy: 0.001)
    }

    func testHeroDimensions() {
        let bar = GradientProgressBar(value: 50, range: 0...100, size: .hero)
        XCTAssertEqual(bar.trackHeight, 8.0, accuracy: 0.001)
        XCTAssertEqual(bar.dotDiameter, 14.0, accuracy: 0.001)
    }
}
