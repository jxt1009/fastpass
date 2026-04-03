import XCTest
@testable import FastTrack

// NOTE: To run these tests, add a Unit Testing Bundle target named "FastTrackTests"
// in Xcode: File → New → Target → Unit Testing Bundle, set Host Application to FastTrack.

final class AppSettingsTests: XCTestCase {

    // MARK: - Imperial conversions

    func testSpeedFactor_Imperial() {
        let settings = AppSettings()
        settings.unitSystem = .imperial
        XCTAssertEqual(settings.speedFactor, 2.23694, accuracy: 0.00001)
    }

    func testDistanceFactor_Imperial() {
        let settings = AppSettings()
        settings.unitSystem = .imperial
        XCTAssertEqual(settings.distanceFactor, 0.000621371, accuracy: 0.000000001)
    }

    func testSpeedDisplay_Imperial_60mph() {
        let settings = AppSettings()
        settings.unitSystem = .imperial
        // 60 mph = 26.8224 m/s
        let result = settings.speedDisplay(26.8224)
        XCTAssertEqual(result, "60 mph")
    }

    func testSpeedDisplay_Imperial_0() {
        let settings = AppSettings()
        settings.unitSystem = .imperial
        XCTAssertEqual(settings.speedDisplay(0), "0 mph")
    }

    func testDistanceDisplay_Imperial_OneMile() {
        let settings = AppSettings()
        settings.unitSystem = .imperial
        // 1 mile = 1609.344 meters
        let result = settings.distanceDisplay(1609.344, decimals: 1)
        XCTAssertEqual(result, "1.0 mi")
    }

    // MARK: - Metric conversions

    func testSpeedFactor_Metric() {
        let settings = AppSettings()
        settings.unitSystem = .metric
        XCTAssertEqual(settings.speedFactor, 3.6, accuracy: 0.0001)
    }

    func testDistanceFactor_Metric() {
        let settings = AppSettings()
        settings.unitSystem = .metric
        XCTAssertEqual(settings.distanceFactor, 0.001, accuracy: 0.000001)
    }

    func testSpeedDisplay_Metric_100kph() {
        let settings = AppSettings()
        settings.unitSystem = .metric
        // 100 km/h = 27.7778 m/s
        let result = settings.speedDisplay(27.7778)
        XCTAssertEqual(result, "100 km/h")
    }

    func testDistanceDisplay_Metric_OneKm() {
        let settings = AppSettings()
        settings.unitSystem = .metric
        let result = settings.distanceDisplay(1000.0, decimals: 1)
        XCTAssertEqual(result, "1.0 km")
    }

    // MARK: - Unit labels

    func testSpeedUnit_Imperial() {
        let settings = AppSettings()
        settings.unitSystem = .imperial
        XCTAssertEqual(settings.speedUnit, "mph")
    }

    func testSpeedUnit_Metric() {
        let settings = AppSettings()
        settings.unitSystem = .metric
        XCTAssertEqual(settings.speedUnit, "km/h")
    }

    func testDistanceUnit_Imperial() {
        let settings = AppSettings()
        settings.unitSystem = .imperial
        XCTAssertEqual(settings.distanceUnit, "mi")
    }

    func testDistanceUnit_Metric() {
        let settings = AppSettings()
        settings.unitSystem = .metric
        XCTAssertEqual(settings.distanceUnit, "km")
    }

    // MARK: - Round-trip consistency

    func testSpeedValue_ThenDisplay_Imperial() {
        let settings = AppSettings()
        settings.unitSystem = .imperial
        let ms = 44.704 // 100 mph exactly
        let displayVal = settings.speedValue(ms)
        XCTAssertEqual(displayVal, 100.0, accuracy: 0.01)
    }

    func testSpeedValue_ThenDisplay_Metric() {
        let settings = AppSettings()
        settings.unitSystem = .metric
        let ms = 100.0 / 3.6 // 100 km/h
        let displayVal = settings.speedValue(ms)
        XCTAssertEqual(displayVal, 100.0, accuracy: 0.01)
    }
}
