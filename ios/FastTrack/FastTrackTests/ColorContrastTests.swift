import XCTest
import SwiftUI
import UIKit
@testable import FastTrack

final class ColorContrastTests: XCTestCase {

    private let lightTrait = UITraitCollection(userInterfaceStyle: .light)
    private let darkTrait = UITraitCollection(userInterfaceStyle: .dark)

    private func rgba(of color: Color, trait: UITraitCollection) -> (r: CGFloat, g: CGFloat, b: CGFloat, a: CGFloat) {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(color).resolvedColor(with: trait).getRed(&r, green: &g, blue: &b, alpha: &a)
        return (r, g, b, a)
    }

    private func brightness(r: CGFloat, g: CGFloat, b: CGFloat) -> CGFloat {
        (r + g + b) / 3
    }

    // MARK: - Brand token adaptation

    func testFtGoldAdaptsBetweenLightAndDark() {
        let light = rgba(of: Color.ftGold, trait: lightTrait)
        let dark = rgba(of: Color.ftGold, trait: darkTrait)
        XCTAssertLessThan(brightness(r: light.r, g: light.g, b: light.b),
                          brightness(r: dark.r, g: dark.g, b: dark.b),
                          "Light-mode ftGold should be darker than dark-mode ftGold")
    }

    func testFtAmberAdaptsBetweenLightAndDark() {
        let light = rgba(of: Color.ftAmber, trait: lightTrait)
        let dark = rgba(of: Color.ftAmber, trait: darkTrait)
        XCTAssertLessThan(brightness(r: light.r, g: light.g, b: light.b),
                          brightness(r: dark.r, g: dark.g, b: dark.b),
                          "Light-mode ftAmber should be darker than dark-mode ftAmber")
    }

    func testFtGreenAdaptsBetweenLightAndDark() {
        let light = rgba(of: Color.ftGreen, trait: lightTrait)
        let dark = rgba(of: Color.ftGreen, trait: darkTrait)
        XCTAssertLessThan(brightness(r: light.r, g: light.g, b: light.b),
                          brightness(r: dark.r, g: dark.g, b: dark.b),
                          "Light-mode ftGreen should be darker than dark-mode ftGreen")
    }

    // MARK: - Chokepoint adaptation

    func testStatusLevelBestColorAdapts() {
        let light = rgba(of: StatusLevel.best.color, trait: lightTrait)
        let dark = rgba(of: StatusLevel.best.color, trait: darkTrait)
        XCTAssertLessThan(brightness(r: light.r, g: light.g, b: light.b),
                          brightness(r: dark.r, g: dark.g, b: dark.b),
                          "Light-mode StatusLevel.best.color should be darker than dark-mode")
    }

    func testAchievementCategorySpecialColorAdapts() {
        let light = rgba(of: AchievementCategory.special.color, trait: lightTrait)
        let dark = rgba(of: AchievementCategory.special.color, trait: darkTrait)
        XCTAssertLessThan(brightness(r: light.r, g: light.g, b: light.b),
                          brightness(r: dark.r, g: dark.g, b: dark.b),
                          "Light-mode .special should be darker than dark-mode")
    }

    // MARK: - White-opacity token adaptation

    func testFtShimmer_adaptsBetweenLightAndDark() {
        let light = rgba(of: Color.ftShimmer, trait: lightTrait)
        let dark = rgba(of: Color.ftShimmer, trait: darkTrait)
        XCTAssertLessThan(brightness(r: light.r, g: light.g, b: light.b),
                          brightness(r: dark.r, g: dark.g, b: dark.b),
                          "Light-mode ftShimmer should be black-tinted (darker) than dark-mode white-tinted")
    }

    func testFtHairline_adaptsBetweenLightAndDark() {
        let light = rgba(of: Color.ftHairline, trait: lightTrait)
        let dark = rgba(of: Color.ftHairline, trait: darkTrait)
        XCTAssertLessThan(brightness(r: light.r, g: light.g, b: light.b),
                          brightness(r: dark.r, g: dark.g, b: dark.b),
                          "Light-mode ftHairline should be black-tinted (darker) than dark-mode white-tinted")
    }

    func testFtOnDarkDivider_adaptsBetweenLightAndDark() {
        let light = rgba(of: Color.ftOnDarkDivider, trait: lightTrait)
        let dark = rgba(of: Color.ftOnDarkDivider, trait: darkTrait)
        XCTAssertLessThan(brightness(r: light.r, g: light.g, b: light.b),
                          brightness(r: dark.r, g: dark.g, b: dark.b),
                          "Light-mode ftOnDarkDivider should be black-tinted (darker) than dark-mode white-tinted")
    }

    func testFtGlassSurface_lightModeIsDarkNotWhite() {
        let light = rgba(of: Color.ftGlassSurface, trait: lightTrait)
        XCTAssertLessThan(brightness(r: light.r, g: light.g, b: light.b), 0.5,
                          "Light-mode ftGlassSurface should be a dark surface fill (black@8%), not near-white")
    }

    // MARK: - Fixed tokens (pass AA against white in both modes)

    func testFtBlueAndFtRedRemainConstant() {
        let blueLight = rgba(of: Color.ftBlue, trait: lightTrait)
        let blueDark = rgba(of: Color.ftBlue, trait: darkTrait)
        XCTAssertEqual(blueLight.r, blueDark.r, accuracy: 0.001, "ftBlue should be constant across traits")
        XCTAssertEqual(blueLight.g, blueDark.g, accuracy: 0.001)
        XCTAssertEqual(blueLight.b, blueDark.b, accuracy: 0.001)

        let redLight = rgba(of: Color.ftRed, trait: lightTrait)
        let redDark = rgba(of: Color.ftRed, trait: darkTrait)
        XCTAssertEqual(redLight.r, redDark.r, accuracy: 0.001, "ftRed should be constant across traits")
        XCTAssertEqual(redLight.g, redDark.g, accuracy: 0.001)
        XCTAssertEqual(redLight.b, redDark.b, accuracy: 0.001)
    }
}
