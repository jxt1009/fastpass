import XCTest
import SwiftUI
import UIKit
@testable import FastTrack

final class StatusDotTests: XCTestCase {

    /// Adaptive brand colors resolve to identical RGBA values as the
    /// `StatusLevel.color` chokepoint in both light and dark traits.
    private func rgba(of color: Color, trait: UITraitCollection) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: trait).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    func testBestLevelUsesGoldColor() {
        for trait in [UITraitCollection(userInterfaceStyle: .light),
                      UITraitCollection(userInterfaceStyle: .dark)] {
            let levelRGBA = rgba(of: StatusLevel.best.color, trait: trait)
            let tokenRGBA = rgba(of: Color.ftGold, trait: trait)
            XCTAssertEqual(levelRGBA.r, tokenRGBA.r, accuracy: 0.001)
            XCTAssertEqual(levelRGBA.g, tokenRGBA.g, accuracy: 0.001)
            XCTAssertEqual(levelRGBA.b, tokenRGBA.b, accuracy: 0.001)
        }
    }

    func testImprovingLevelUsesGreenColor() {
        for trait in [UITraitCollection(userInterfaceStyle: .light),
                      UITraitCollection(userInterfaceStyle: .dark)] {
            let levelRGBA = rgba(of: StatusLevel.improving.color, trait: trait)
            let tokenRGBA = rgba(of: Color.ftGreen, trait: trait)
            XCTAssertEqual(levelRGBA.r, tokenRGBA.r, accuracy: 0.001)
            XCTAssertEqual(levelRGBA.g, tokenRGBA.g, accuracy: 0.001)
            XCTAssertEqual(levelRGBA.b, tokenRGBA.b, accuracy: 0.001)
        }
    }

    func testNearBestLevelUsesAmberColor() {
        for trait in [UITraitCollection(userInterfaceStyle: .light),
                      UITraitCollection(userInterfaceStyle: .dark)] {
            let levelRGBA = rgba(of: StatusLevel.nearBest.color, trait: trait)
            let tokenRGBA = rgba(of: Color.ftAmber, trait: trait)
            XCTAssertEqual(levelRGBA.r, tokenRGBA.r, accuracy: 0.001)
            XCTAssertEqual(levelRGBA.g, tokenRGBA.g, accuracy: 0.001)
            XCTAssertEqual(levelRGBA.b, tokenRGBA.b, accuracy: 0.001)
        }
    }

    func testTypicalLevelUsesBlueColor() {
        // ftBlue is a fixed color (not adaptive), so direct equality holds.
        XCTAssertEqual(StatusLevel.typical.color, Color.ftBlue)
    }

    func testInactiveLevelUsesGrayColor() {
        for trait in [UITraitCollection(userInterfaceStyle: .light),
                      UITraitCollection(userInterfaceStyle: .dark)] {
            let levelRGBA = rgba(of: StatusLevel.inactive.color, trait: trait)
            let expected = trait.userInterfaceStyle == .dark
                ? rgba(of: Color(white: 0.33), trait: trait)
                : rgba(of: Color(white: 0.55), trait: trait)
            XCTAssertEqual(levelRGBA.r, expected.r, accuracy: 0.001)
            XCTAssertEqual(levelRGBA.g, expected.g, accuracy: 0.001)
            XCTAssertEqual(levelRGBA.b, expected.b, accuracy: 0.001)
        }
    }

    func testStatusDotInstantiates() {
        let dot = StatusDot(level: .best, label: "Personal Best")
        XCTAssertNotNil(dot)
    }
}
