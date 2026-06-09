import XCTest
@testable import FastTrack

// Source-order regression guard for PR 1 of the car-detail-polish spec:
// the own-profile `CarDetailView` must pass a non-nil `progress`
// argument to both `CarDetailGauge` calls inside `pbGauges`, derived
// from the new `CarDetailGaugeProgress` helper. Mirrors the
// `readSourceFile` pattern in `PublicProfileRedesignTests`.

final class CarDetailGaugeProgressWiringTests: XCTestCase {

    /// The two `CarDetailGauge(` calls inside `pbGauges` must each pass
    /// a `progress:` argument, and the call must read from
    /// `CarDetailGaugeProgress`. A regression here means the gauge
    /// reverts to a decorative arc without animation.
    func testCarDetailView_pbGauges_PassesProgressFromHelper() throws {
        let source = try readCarDetailViewSource()

        // Both calls must include `progress:` so the gauge has something
        // to animate. Use the helper symbol as the marker.
        XCTAssertTrue(
            source.contains("CarDetailGaugeProgress"),
            """
            CarDetailView must derive `progress` for its gauges via \
            CarDetailGaugeProgress; helper reference not found in source.
            """
        )

        // The pbGauges body should contain at least two `progress:`
        // assignments — one per CarDetailGauge. Bound the body to
        // everything between the `private var pbGauges` declaration
        // and the next `private var ` declaration (any other computed
        // property). Both `CarDetailGauge(` calls in `pbGauges` must
        // have a `progress:` line each.
        let pbGaugesBody = try firstSubstringUpToNext(
            in: source,
            open: "private var pbGauges: some View {",
            terminator: "    private var "
        )
        let progressCount = pbGaugesBody.components(separatedBy: "progress:").count - 1
        let gaugeCount = pbGaugesBody.components(separatedBy: "CarDetailGauge(").count - 1
        XCTAssertGreaterThanOrEqual(
            gaugeCount,
            2,
            "pbGauges must render at least two CarDetailGauge calls (found \(gaugeCount))."
        )
        XCTAssertGreaterThanOrEqual(
            progressCount,
            gaugeCount,
            "pbGauges must wire `progress:` for every CarDetailGauge call (found \(progressCount) progress: lines for \(gaugeCount) gauges)."
        )
    }

    /// PR 1 follow-up: both gauges must gate their `progress:` on
    /// `data` being non-nil, so a car-removed state falls back to the
    /// decorative arc. The previous `data?.bestTopSpeed.map { ... }`
    /// and the always-non-nil `visualProgress(zeroSixtyProgress(...))`
    /// both leaked the minimum-visible floor into the car-removed
    /// fallback. A regression here re-introduces the trimmed/animated
    /// arc on the "Car Removed" screen.
    func testCarDetailView_pbGauges_GatesProgressOnDataPresence() throws {
        let source = try readCarDetailViewSource()

        XCTAssertTrue(
            source.contains("progress: data.map"),
            """
            Both CarDetailGauge `progress:` arguments must be derived \
            via `data.map { ... }` so they evaluate to nil when `data` \
            is nil (e.g. car removed). Found a progress: line that \
            does not gate on `data.map`.
            """
        )

        // Make sure neither gauge still uses the unguarded patterns
        // the review flagged. Both are still allowed to reference
        // `data?` for other fields (e.g. value, setOn), but the
        // `progress:` argument specifically must gate on data.
        let pbGaugesBody = try firstSubstringUpToNext(
            in: source,
            open: "private var pbGauges: some View {",
            terminator: "    private var "
        )
        XCTAssertFalse(
            pbGaugesBody.contains("data?.bestTopSpeed.map"),
            "Top Speed progress must no longer derive from `data?.bestTopSpeed.map`; gate on data presence instead."
        )
        XCTAssertFalse(
            pbGaugesBody.contains("visualProgress(\n                    CarDetailGaugeProgress.zeroSixtyProgress"),
            "Best 0-60 progress must no longer call `visualProgress` unconditionally; gate on data presence instead."
        )
    }

    // MARK: - Helpers

    private func readCarDetailViewSource() throws -> String {
        try readSourceFile(name: "CarDetailView.swift", in: "Views")
    }

    /// Reads a Swift file from the `ios/FastTrack/FastTrack/<dir>/<name>`
    /// tree, relative to this test file. Same approach as
    /// `PublicProfileRedesignTests.readSourceFile` — see that method
    /// for rationale on the two candidate paths.
    private func readSourceFile(name: String, in dir: String) throws -> String {
        let thisFile = (#filePath as NSString)
        let candidates = [
            thisFile.deletingLastPathComponent + "/../FastTrack/\(dir)/\(name)",
            thisFile.deletingLastPathComponent + "/../../FastTrack/FastTrack/\(dir)/\(name)",
        ].map { (path: String) -> String in
            (path as NSString).standardizingPath
        }
        for path in candidates {
            if let data = FileManager.default.contents(atPath: path),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        XCTFail("\(name) not found at expected locations: \(candidates). Regression guard cannot run.")
        struct FileNotFound: Error {}
        throw FileNotFound()
    }

    /// Returns the substring of `text` starting at the first occurrence
    /// of `open` (exclusive) and ending just before the next occurrence
    /// of `terminator` (which marks the start of a sibling declaration).
    /// Fails the test if either marker is missing.
    private func firstSubstringUpToNext(
        in text: String,
        open: String,
        terminator: String
    ) throws -> String {
        struct MarkerMissing: Error { let label: String }
        guard let openRange = text.range(of: open) else {
            XCTFail("Could not find `\(open)` in source.")
            throw MarkerMissing(label: open)
        }
        let start = openRange.upperBound
        guard let termRange = text.range(of: terminator, range: start..<text.endIndex) else {
            XCTFail("Could not find terminator `\(terminator)` after `\(open)` in source.")
            throw MarkerMissing(label: terminator)
        }
        return String(text[start..<termRange.lowerBound])
    }
}
