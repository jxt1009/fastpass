import XCTest
@testable import FastTrack

// Phase 2 / Track F of #64: the public profile's garage cards are
// tappable (push a read-only per-car detail). These tests guard
// against regressions in two ways:
//
//   1. A line/source-order regression guard on `PublicProfileView`:
//      the garage section must wrap each card in a `NavigationLink` to
//      `PublicCarDetailView`, not just render the card on its own.
//   2. A source assertion on `PublicGarageCard`: the card must render
//      a chevron hint so the "tap to view" affordance survives a
//      redesign that strips wrapping gestures.
//
// Like the other line-order regression guards in this test target
// (`testProfileView_AchievementsStripAboveGarage`), we read the source
// file off disk and assert on the rendered Swift rather than spinning
// up a SwiftUI snapshot harness — the project does not currently use
// ViewInspector.

final class PublicProfileRedesignTests: XCTestCase {

    // MARK: - NavigationLink wiring

    /// The public profile's garage section must wrap each
    /// `PublicGarageCard` in a `NavigationLink` to `PublicCarDetailView`
    /// so tapping a car pushes the per-car detail. Regression guard
    /// for #64 Track F.
    func testPublicProfile_GarageCardsAreTappable() throws {
        let source = try readPublicProfileViewSource()
        let garageBody = try firstSubstring(in: source, open: "Section(\"Garage\")", close: "}\n            }")
        XCTAssertTrue(garageBody.contains("NavigationLink"),
            "PublicProfileView's Garage section must wrap each card in a NavigationLink")
        XCTAssertTrue(garageBody.contains("PublicCarDetailView("),
            "PublicProfileView's Garage section must push PublicCarDetailView")
    }

    // MARK: - Card chevron hint

    /// `PublicGarageCard` must include a trailing chevron hint so the
    /// "tap to view" affordance is visible at a glance, not just
    /// inferred from the navigation behaviour. Regression guard for
    /// #64 Track F.
    func testPublicGarageCard_HasTrailingChevronHint() throws {
        let source = try readPublicGarageCardSource()
        XCTAssertTrue(source.contains("chevron.right"),
            "PublicGarageCard must include a chevron.right hint for tap-to-view")
    }

    /// `PublicGarageCard` must NOT wrap its body in a `Button` (or
    /// `onTapGesture` on the card itself), because the parent
    /// `NavigationLink` is the tap handler. A button-in-button would
    /// double-handle the tap on iOS 17+. Regression guard for #64
    /// Track F.
    func testPublicGarageCard_DoesNotOwnItsOwnTapHandler() throws {
        let source = try readPublicGarageCardSource()
        XCTAssertFalse(source.contains("onTapGesture"),
            "PublicGarageCard must let the parent NavigationLink own the tap; the card itself should not install an onTapGesture")
    }

    // MARK: - Helpers

    private func readPublicProfileViewSource() throws -> String {
        try readSourceFile(name: "PublicProfileView.swift", in: "Views")
    }

    private func readPublicGarageCardSource() throws -> String {
        try readSourceFile(name: "PublicGarageCard.swift", in: "Views")
    }

    /// Reads a Swift file from the `ios/FastTrack/FastTrack/<dir>/<name>`
    /// tree, relative to this test file. Mirrors the path-walking
    /// strategy in `ProfileRedesignTests.readProfileViewSource()` —
    /// see that method for the rationale on the two candidate paths.
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
    /// of `open` (exclusive) and ending at the next occurrence of
    /// `close` (inclusive). Fails the test if either marker is missing.
    private func firstSubstring(in text: String, open: String, close: String) throws -> String {
        struct MarkerMissing: Error { let label: String }
        guard let openRange = text.range(of: open) else {
            XCTFail("Could not find `\(open)` in source.")
            throw MarkerMissing(label: open)
        }
        let start = openRange.upperBound
        guard let closeRange = text.range(of: close, range: start..<text.endIndex) else {
            XCTFail("Could not find closing `\(close)` after `\(open)` in source.")
            throw MarkerMissing(label: close)
        }
        return String(text[start..<closeRange.upperBound])
    }
}
