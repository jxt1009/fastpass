import XCTest
import SwiftUI
@testable import FastTrack

final class DesignSystemTests: XCTestCase {

    func testStatusLevelColors() {
        XCTAssertEqual(StatusLevel.best.color, Color.ftGold)
        XCTAssertEqual(StatusLevel.improving.color, Color.ftGreen)
        XCTAssertEqual(StatusLevel.nearBest.color, Color.ftAmber)
        XCTAssertEqual(StatusLevel.typical.color, Color.ftBlue)
        XCTAssertEqual(StatusLevel.inactive.color, Color(white: 0.33))
    }

    func testBgGradientsAreDistinct() {
        // ftBgGradient (default) and ftBgGradientWarm (recording) must be different
        // We verify this by confirming they're both accessible and checking their
        // underlying type via description string comparison
        let defaultGrad = Color.ftBgGradient
        let warmGrad = Color.ftBgGradientWarm
        // Both return RadialGradient wrapped as some ShapeStyle.
        // The simplest verifiable property: they are not literally the same value.
        let defaultDesc = String(describing: defaultGrad)
        let warmDesc = String(describing: warmGrad)
        XCTAssertNotEqual(defaultDesc, warmDesc, "ftBgGradient and ftBgGradientWarm should be distinct gradients")
    }

    func testFtGlassCardFillOpacity() {
        let fill = Color.ftGlassCardFill
        XCTAssertNotEqual(fill, Color.clear)
    }
}
