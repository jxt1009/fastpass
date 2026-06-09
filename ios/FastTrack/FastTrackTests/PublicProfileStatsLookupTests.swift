import XCTest
@testable import FastTrack

// Pure unit tests for `PublicProfileStatsLookup.byCarId(blob:)`. The
// helper used to live as a `private` method on `PublicProfileView`; PR
// 2 of the car-detail-gauges-public-stats-hero-photo-design spec
// (section 4.2.2) promotes it to a static enum so it can be exercised
// in isolation. These tests guard the decode behaviour across the
// cases we know about: missing, empty, malformed, single-key,
// multi-key, extra keys, and whitespace.
//
// We construct the JSON by building real `CarStats` instances and
// running them through the same `JSONEncoder` path that
// `CarStatsManager.saveCarStats` uses (`JSONEncoder().encode([String:
// CarStats])`). That guarantees the test data matches the on-the-wire
// shape byte-for-byte; we don't want a hand-rolled JSON literal to
// drift from the actual encoder output.

final class PublicProfileStatsLookupTests: XCTestCase {

    // MARK: - Empty / nil inputs

    func testByCarId_NilBlobReturnsEmpty() {
        XCTAssertTrue(PublicProfileStatsLookup.byCarId(blob: nil).isEmpty)
    }

    func testByCarId_EmptyStringReturnsEmpty() {
        XCTAssertTrue(PublicProfileStatsLookup.byCarId(blob: "").isEmpty)
    }

    func testByCarId_MalformedJSONReturnsEmpty() {
        XCTAssertTrue(PublicProfileStatsLookup.byCarId(blob: "not json").isEmpty)
        XCTAssertTrue(PublicProfileStatsLookup.byCarId(blob: "{[}").isEmpty)
        XCTAssertTrue(
            PublicProfileStatsLookup.byCarId(blob: "{\"c1\": 12345}").isEmpty,
            "Wrong shape (non-CarStats value) should fail to decode and return [:]"
        )
    }

    // MARK: - Single / multiple keys

    func testByCarId_SingleKeyDecodes() throws {
        let stats = makeStats(carId: "c1", totalDrives: 5, bestTopSpeed: 30, bestZeroToSixty: 4.5)
        let blob = try encodeStats([stats])
        let result = PublicProfileStatsLookup.byCarId(blob: blob)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result["c1"]?.carId, "c1")
        XCTAssertEqual(result["c1"]?.totalDrives, 5)
        XCTAssertEqual(result["c1"]?.bestZeroToSixty, 4.5)
    }

    func testByCarId_MultipleKeysDecodes() throws {
        let a = makeStats(carId: "c1", totalDrives: 5, bestTopSpeed: 30, bestZeroToSixty: 4.5)
        let b = makeStats(carId: "c2", totalDrives: 2, bestTopSpeed: 22, bestZeroToSixty: nil)
        let blob = try encodeStats([a, b])
        let result = PublicProfileStatsLookup.byCarId(blob: blob)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result["c1"]?.totalDrives, 5)
        XCTAssertEqual(result["c2"]?.totalDrives, 2)
        XCTAssertNil(result["c2"]?.bestZeroToSixty,
                     "An absent bestZeroToSixty should round-trip as nil")
    }

    func testByCarId_ExtraKeysNotInGarageIgnored() throws {
        // The decoder is total — it returns whatever keys the blob
        // contains. The view's `statsByCarId[car.id]` lookup naturally
        // ignores keys that don't match a garage car. This test pins
        // that behaviour so we don't accidentally filter on the
        // client side (which would change the contract for callers
        // that pass a smaller or partial garage list).
        let a = makeStats(carId: "c1", totalDrives: 1, bestTopSpeed: 10, bestZeroToSixty: nil)
        let b = makeStats(carId: "c2", totalDrives: 2, bestTopSpeed: 20, bestZeroToSixty: nil)
        let blob = try encodeStats([a, b])
        let result = PublicProfileStatsLookup.byCarId(blob: blob)
        XCTAssertEqual(result.keys.sorted(), ["c1", "c2"])
    }

    func testByCarId_LeadingAndTrailingWhitespaceHandled() throws {
        let stats = makeStats(carId: "c1", totalDrives: 1, bestTopSpeed: 10, bestZeroToSixty: nil)
        let inner = try encodeStats([stats])
        let blob = "  " + inner + "\n"
        // `JSONDecoder` is whitespace-tolerant for top-level objects,
        // so this should decode cleanly. If that ever changes (we
        // switched to a stricter parser), this test will tell us.
        let result = PublicProfileStatsLookup.byCarId(blob: blob)
        XCTAssertEqual(result["c1"]?.carId, "c1")
    }

    // MARK: - isSyncedBlob

    /// `isSyncedBlob` is the empty-state discriminator used by
    /// `PublicCarDetailView` to choose between "No driving data" and
    /// "Stats haven't synced" copy. It must return false for the
    /// nil / empty / empty-object / malformed inputs — all of which
    /// are indistinguishable from "user has no driving data" on the
    /// server.
    func testIsSyncedBlob_NilReturnsFalse() {
        XCTAssertFalse(PublicProfileStatsLookup.isSyncedBlob(nil))
    }

    func testIsSyncedBlob_EmptyStringReturnsFalse() {
        XCTAssertFalse(PublicProfileStatsLookup.isSyncedBlob(""))
    }

    func testIsSyncedBlob_EmptyObjectReturnsFalse() {
        XCTAssertFalse(PublicProfileStatsLookup.isSyncedBlob("{}"),
                       "An empty `{}` blob is semantically equivalent to no driving data, not 'stats haven't synced'")
    }

    func testIsSyncedBlob_MalformedJSONReturnsFalse() {
        XCTAssertFalse(PublicProfileStatsLookup.isSyncedBlob("not json"))
        XCTAssertFalse(PublicProfileStatsLookup.isSyncedBlob("{[}"))
        XCTAssertFalse(PublicProfileStatsLookup.isSyncedBlob("{\"c1\": 12345}"),
                       "Wrong shape (non-CarStats value) should fail to decode and read as not-synced")
    }

    /// A blob with at least one entry — even for a different car id —
    /// must read as "synced" so the view shows the "haven't synced for
    /// this car yet" copy. This is the path that distinguishes a
    /// user with stats from a user with no driving data.
    func testIsSyncedBlob_NonEmptyDictReturnsTrue() throws {
        let stats = makeStats(carId: "c1", totalDrives: 5, bestTopSpeed: 30, bestZeroToSixty: 4.5)
        let blob = try encodeStats([stats])
        XCTAssertTrue(PublicProfileStatsLookup.isSyncedBlob(blob))
    }

    func testIsSyncedBlob_EntryForDifferentCarReturnsTrue() throws {
        // The car detail view calls isSyncedBlob on the same blob the
        // car-detail lookup uses. The helper must answer "does the
        // user have *any* synced stats?" — not "does the user have
        // stats for *this* car?". The per-car check is the caller's
        // job (look up `stats` and check for nil).
        let stats = makeStats(carId: "other-car", totalDrives: 1, bestTopSpeed: 10, bestZeroToSixty: nil)
        let blob = try encodeStats([stats])
        XCTAssertTrue(PublicProfileStatsLookup.isSyncedBlob(blob))
    }

    // MARK: - Helpers

    /// Build a `CarStats` with the handful of fields we care about
    /// exercising. The rest take their struct defaults.
    private func makeStats(
        carId: String,
        totalDrives: Int = 0,
        bestTopSpeed: Double = 0,
        bestZeroToSixty: Double? = nil
    ) -> CarStats {
        CarStats(
            carId: carId,
            totalDrives: totalDrives,
            bestTopSpeed: bestTopSpeed,
            bestZeroToSixty: bestZeroToSixty
        )
    }

    /// Mirror `CarStatsManager.saveCarStats`: encode `[carId: stats]`
    /// to JSON, return the string. The lookup helper accepts the same
    /// shape, so this gives us a round-trip-true test fixture.
    private func encodeStats(_ stats: [CarStats]) throws -> String {
        let dict = Dictionary(uniqueKeysWithValues: stats.map { ($0.carId, $0) })
        let data = try JSONEncoder().encode(dict)
        return String(data: data, encoding: .utf8) ?? ""
    }
}
