import XCTest
import SwiftUI
import UIKit
@testable import FastTrack

final class DesignSystemTests: XCTestCase {

    /// Resolve a SwiftUI `Color` (which may wrap a dynamic UIColor) into a
    /// concrete RGBA tuple against a specific trait collection. Required for
    /// comparing adaptive brand colors that differ across light/dark.
    private func rgba(of color: Color, trait: UITraitCollection) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: trait).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    func testStatusLevelColors() {
        // Adaptive tokens resolve to identical RGBA values as `StatusLevel.color`
        // (which returns the same token) — verified in both light and dark traits.
        let pairs: [(StatusLevel, Color)] = [
            (.best, .ftGold),
            (.improving, .ftGreen),
            (.nearBest, .ftAmber),
            (.typical, .ftBlue),
        ]
        for trait in [
            UITraitCollection(userInterfaceStyle: .light),
            UITraitCollection(userInterfaceStyle: .dark),
        ] {
            for (level, token) in pairs {
                let levelRGBA = rgba(of: level.color, trait: trait)
                let tokenRGBA = rgba(of: token, trait: trait)
                XCTAssertEqual(levelRGBA.r, tokenRGBA.r, accuracy: 0.001, "\(level) red mismatch")
                XCTAssertEqual(levelRGBA.g, tokenRGBA.g, accuracy: 0.001, "\(level) green mismatch")
                XCTAssertEqual(levelRGBA.b, tokenRGBA.b, accuracy: 0.001, "\(level) blue mismatch")
            }
        }
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
