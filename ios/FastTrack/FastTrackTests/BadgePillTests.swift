import XCTest
import SwiftUI
@testable import FastTrack

@MainActor
final class BadgePillTests: XCTestCase {

    func testAllStyles_Compile() {
        _ = BadgePill("You", style: .you).body
        _ = BadgePill("Selected", style: .selected).body
        _ = BadgePill("PB 0-60", icon: "trophy.fill", style: .pb060).body
        _ = BadgePill("PB Speed", icon: "flame.fill", style: .pbTopSpeed).body
        _ = BadgePill("My Car", style: .carChip).body
        _ = BadgePill("3", style: .count).body
    }

    func testStyle_Equality() {
        XCTAssertEqual(BadgePill.Style.you, BadgePill.Style.you)
        XCTAssertNotEqual(BadgePill.Style.you, BadgePill.Style.selected)
    }
}
