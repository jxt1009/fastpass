import XCTest
import SwiftUI
@testable import FastTrack

final class StatusDotTests: XCTestCase {

    func testBestLevelUsesGoldColor() {
        XCTAssertEqual(StatusLevel.best.color, Color.ftGold)
    }

    func testImprovingLevelUsesGreenColor() {
        XCTAssertEqual(StatusLevel.improving.color, Color.ftGreen)
    }

    func testNearBestLevelUsesAmberColor() {
        XCTAssertEqual(StatusLevel.nearBest.color, Color.ftAmber)
    }

    func testTypicalLevelUsesBlueColor() {
        XCTAssertEqual(StatusLevel.typical.color, Color.ftBlue)
    }

    func testInactiveLevelUsesGrayColor() {
        XCTAssertEqual(StatusLevel.inactive.color, Color(white: 0.33))
    }

    func testStatusDotInstantiates() {
        let dot = StatusDot(level: .best, label: "Personal Best")
        XCTAssertNotNil(dot)
    }
}
