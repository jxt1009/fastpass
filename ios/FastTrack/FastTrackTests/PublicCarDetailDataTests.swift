import XCTest
@testable import FastTrack

// Tests for the pure `PublicCarDetailData.derive(...)` factory. The
// view layer (`PublicCarDetailView`) is hard to inspect without a
// SwiftUI snapshot harness (the project does not currently use
// ViewInspector), so we exercise the value-type here and trust the
// view to be a thin renderer.

final class PublicCarDetailDataTests: XCTestCase {

    // MARK: - Pull-through

    /// `bestTopSpeed` on the derived struct equals the `CarStats`
    /// value, still in m/s — the view handles the unit conversion.
    func testDerive_PullsTopSpeedFromStats() {
        var stats = CarStats(carId: "c1")
        stats.bestTopSpeed = 30.0  // 67 mph
        let data = PublicCarDetailData.derive(car: makeCar(), stats: stats)
        XCTAssertEqual(data.bestTopSpeed, 30.0)
    }

    /// `bestZeroToSixty` is a `Double?` on `CarStats`; nil in, nil out.
    func testDerive_PullsZeroSixtyFromStats() {
        var stats = CarStats(carId: "c1")
        stats.bestZeroToSixty = 4.5
        let data = PublicCarDetailData.derive(car: makeCar(), stats: stats)
        XCTAssertEqual(data.bestZeroToSixty, 4.5)
    }

    // MARK: - Nil / empty inputs

    /// No stats → no PBs. This is the path the public profile takes
    /// when the server's `car_stats_data` blob didn't include this
    /// car id (additive — older backends may not populate the blob).
    func testDerive_NilStats_NilPBs() {
        let data = PublicCarDetailData.derive(car: makeCar(), stats: nil)
        XCTAssertNil(data.stats)
        XCTAssertNil(data.bestTopSpeed)
        XCTAssertNil(data.bestZeroToSixty)
    }

    /// `bestTopSpeed == 0` is the "never recorded a drive" sentinel
    /// in the local cache; it should not surface as a fake PB.
    func testDerive_ZeroTopSpeedIsTreatedAsMissing() {
        var stats = CarStats(carId: "c1")
        stats.bestTopSpeed = 0
        let data = PublicCarDetailData.derive(car: makeCar(), stats: stats)
        XCTAssertNil(data.bestTopSpeed)
    }

    /// `bestZeroToSixty == nil` on the stats struct means "no 0-60
    /// ever recorded" — must surface as nil on the derived value too.
    func testDerive_NilZeroToSixtyOnStatsIsNilOnDerived() {
        let stats = CarStats(carId: "c1")  // bestZeroToSixty defaults to nil
        let data = PublicCarDetailData.derive(car: makeCar(), stats: stats)
        XCTAssertNil(data.bestZeroToSixty)
    }

    // MARK: - Car passthrough

    /// The input car is the same struct that comes out — no
    /// transformation, no defaults filled in. This is a guard against
    /// someone accidentally adding a mapper that loses fields.
    func testDerive_CarPassesThrough() {
        let car = makeCar(id: "car-7", make: "BMW", model: "M3", year: 2024, trim: "Competition", nickname: "Track Toy")
        let data = PublicCarDetailData.derive(car: car, stats: nil)
        XCTAssertEqual(data.car, car)
    }

    // MARK: - Helpers

    private func makeCar(
        id: String = "car-1",
        make: String = "Honda",
        model: String = "Civic",
        year: Int? = 2018,
        trim: String = "EX",
        nickname: String = ""
    ) -> UserCar {
        UserCar(id: id, make: make, model: model, year: year, trim: trim, nickname: nickname, photoUrl: nil)
    }
}
