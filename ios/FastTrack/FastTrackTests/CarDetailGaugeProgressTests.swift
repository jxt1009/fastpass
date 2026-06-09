import XCTest
@testable import FastTrack

// Tests for the pure progress-math helpers used by `CarDetailGauge` on
// the own-profile `CarDetailView` (PR 1 of the car-detail-polish spec).
//
// The view hands the gauge a `Double?` in `[0, 1]` that drives the
// `.trim(from: 0, to: progress)` arc. The helper enum below keeps the
// math (mapping raw PB values to that range) in a testable spot
// instead of inlined in the SwiftUI body.

final class CarDetailGaugeProgressTests: XCTestCase {

    // MARK: - topSpeedProgress

    /// 0 m/s on a 0..80 m/s scale is 0%.
    func testTopSpeedProgress_Canonical_0Percent() {
        XCTAssertEqual(CarDetailGaugeProgress.topSpeedProgress(speedMps: 0), 0.0, accuracy: 0.0001)
    }

    /// 40 m/s on a 0..80 m/s scale is 50%.
    func testTopSpeedProgress_Canonical_50Percent() {
        XCTAssertEqual(
            CarDetailGaugeProgress.topSpeedProgress(speedMps: 40),
            0.5,
            accuracy: 0.0001
        )
    }

    /// 80 m/s on a 0..80 m/s scale is 100%.
    func testTopSpeedProgress_Canonical_100Percent() {
        XCTAssertEqual(
            CarDetailGaugeProgress.topSpeedProgress(speedMps: 80),
            1.0,
            accuracy: 0.0001
        )
    }

    /// 160 m/s is two full scales; the result must clamp to 1.0, not wrap.
    func testTopSpeedProgress_OutOfRange_AboveClampsToOne() {
        XCTAssertEqual(
            CarDetailGaugeProgress.topSpeedProgress(speedMps: 160),
            1.0,
            accuracy: 0.0001
        )
    }

    /// Negative speeds are nonsensical; the helper must clamp to 0.
    func testTopSpeedProgress_OutOfRange_NegativeClampsToZero() {
        XCTAssertEqual(
            CarDetailGaugeProgress.topSpeedProgress(speedMps: -10),
            0.0,
            accuracy: 0.0001
        )
    }

    /// A custom `fullScaleMps` is honored by the helper so the gauge can
    /// rescale without changing the call site signature.
    func testTopSpeedProgress_CustomFullScale() {
        // 0..40 scale, 20 m/s input -> 0.5
        XCTAssertEqual(
            CarDetailGaugeProgress.topSpeedProgress(speedMps: 20, fullScaleMps: 40),
            0.5,
            accuracy: 0.0001
        )
    }

    // MARK: - zeroSixtyProgress

    /// 2.0 s is the best-case anchor; the helper maps it to 1.0.
    func testZeroSixtyProgress_Canonical_100Percent() {
        XCTAssertEqual(
            CarDetailGaugeProgress.zeroSixtyProgress(seconds: 2.0),
            1.0,
            accuracy: 0.0001
        )
    }

    /// 5.0 s is the midpoint of the 2..8 scale -> 0.5.
    func testZeroSixtyProgress_Canonical_50Percent() {
        XCTAssertEqual(
            CarDetailGaugeProgress.zeroSixtyProgress(seconds: 5.0),
            0.5,
            accuracy: 0.0001
        )
    }

    /// 8.0 s is the worst-case anchor; the helper maps it to 0.0.
    func testZeroSixtyProgress_Canonical_0Percent() {
        XCTAssertEqual(
            CarDetailGaugeProgress.zeroSixtyProgress(seconds: 8.0),
            0.0,
            accuracy: 0.0001
        )
    }

    /// A `nil` seconds (no 0-60 attempt yet) maps to 0 so the
    /// `visualProgress` floor can still draw a sliver.
    func testZeroSixtyProgress_NilSecondsReturnsZero() {
        XCTAssertEqual(
            CarDetailGaugeProgress.zeroSixtyProgress(seconds: nil),
            0.0,
            accuracy: 0.0001
        )
    }

    /// 10.0 s is past the worst-case anchor; clamp to 0, don't go negative.
    func testZeroSixtyProgress_OutOfRange_AboveWorstClampsToZero() {
        XCTAssertEqual(
            CarDetailGaugeProgress.zeroSixtyProgress(seconds: 10.0),
            0.0,
            accuracy: 0.0001
        )
    }

    /// 1.0 s is faster than the best-case anchor; clamp to 1.0, don't exceed.
    func testZeroSixtyProgress_OutOfRange_BelowBestClampsToOne() {
        XCTAssertEqual(
            CarDetailGaugeProgress.zeroSixtyProgress(seconds: 1.0),
            1.0,
            accuracy: 0.0001
        )
    }

    /// Custom best/worst anchors are honored (defensive; the view
    /// relies on the defaults but the helper must not bake them in).
    func testZeroSixtyProgress_CustomAnchors() {
        // best=3, worst=7, 5.0 s -> 0.5
        XCTAssertEqual(
            CarDetailGaugeProgress.zeroSixtyProgress(seconds: 5.0, best: 3.0, worst: 7.0),
            0.5,
            accuracy: 0.0001
        )
    }

    // MARK: - visualProgress

    /// The minimum-visible boost: zero must come back at the floor
    /// (0.12 by default) so a zero PB still renders a sliver of arc.
    func testVisualProgress_ZeroIsBoostedToMinimumVisible() {
        XCTAssertEqual(
            CarDetailGaugeProgress.visualProgress(0.0),
            0.12,
            accuracy: 0.0001
        )
    }

    /// A value just below the floor is also boosted up to it.
    func testVisualProgress_BelowFloorIsBoosted() {
        XCTAssertEqual(
            CarDetailGaugeProgress.visualProgress(0.05),
            0.12,
            accuracy: 0.0001
        )
    }

    /// A value exactly at the floor passes through unchanged.
    func testVisualProgress_AtFloorPassesThrough() {
        XCTAssertEqual(
            CarDetailGaugeProgress.visualProgress(0.12),
            0.12,
            accuracy: 0.0001
        )
    }

    /// A mid-range value passes through unchanged (no boost when
    /// already visible).
    func testVisualProgress_MidRangePassesThrough() {
        XCTAssertEqual(
            CarDetailGaugeProgress.visualProgress(0.5),
            0.5,
            accuracy: 0.0001
        )
    }

    /// A value above the floor but above 1.0 still clamps to 1.0.
    func testVisualProgress_AboveOneClampsToOne() {
        XCTAssertEqual(
            CarDetailGaugeProgress.visualProgress(1.5),
            1.0,
            accuracy: 0.0001
        )
    }

    /// A custom minimumVisible is honored (defensive; view relies on
    /// the default).
    func testVisualProgress_CustomMinimumVisible() {
        // 0.0 is below the custom 0.25 floor -> boosted to 0.25.
        XCTAssertEqual(
            CarDetailGaugeProgress.visualProgress(0.0, minimumVisible: 0.25),
            0.25,
            accuracy: 0.0001
        )
        // 0.3 is above the custom 0.25 floor -> passes through.
        XCTAssertEqual(
            CarDetailGaugeProgress.visualProgress(0.3, minimumVisible: 0.25),
            0.3,
            accuracy: 0.0001
        )
    }
}
