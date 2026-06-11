import XCTest
import SwiftUI
@testable import FastTrack

final class FTGaugeTests: XCTestCase {

    func testStatCell_Compiles() {
        let gauge = FTGauge(
            style: .statCell(unit: "mph"),
            label: "Top Speed",
            value: "—",
            color: .ftRed
        )
        _ = gauge.body
    }

    func testHero_CompilesWithAllParams() {
        let gauge = FTGauge(
            style: .hero(progress: 0.5, setOn: Date()),
            label: "Top Speed",
            value: "120",
            color: .ftAmber
        )
        _ = gauge.body
    }

    func testCompact_Compiles() {
        let gauge = FTGauge(
            style: .compact,
            label: "Distance",
            value: "5.2",
            color: .ftBlue
        )
        _ = gauge.body
    }

    func testStyle_Equality() {
        XCTAssertEqual(FTGauge.Style.compact, FTGauge.Style.compact)
        XCTAssertNotEqual(FTGauge.Style.compact, FTGauge.Style.statCell(unit: nil))
    }
}
