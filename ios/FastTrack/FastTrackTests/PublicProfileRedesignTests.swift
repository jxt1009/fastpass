import XCTest
@testable import FastTrack

// Phase 2 / Track F of #64: the public profile's garage cards are
// tappable (push a read-only per-car detail). These tests guard
// against regressions in the following ways:
//
//   1. A source assertion on `PublicProfileView`: the garage grid
//      must wrap each card in a `NavigationLink` to
//      `PublicCarDetailView`, not just render the card on its own.
//   2. The inline card function must not own a tap handler — the
//      wrapping `NavigationLink` is the only gesture.
//
// `PublicGarageCard` was deleted in the Task-12 redesign and replaced
// by an inline `publicCarCard` function in `PublicProfileView`.
//
// Like the other line-order regression guards in this test target
// (`testProfileView_AchievementsStripAboveGarage`), we read the source
// file off disk and assert on the rendered Swift rather than spinning
// up a SwiftUI snapshot harness — the project does not currently use
// ViewInspector.

final class PublicProfileRedesignTests: XCTestCase {

    // MARK: - NavigationLink wiring

    /// The public profile's garage grid must wrap each card in a
    /// `NavigationLink` to `PublicCarDetailView` so tapping a car
    /// pushes the per-car detail. Regression guard for #64 Track F.
    func testPublicProfile_GarageCardsAreTappable() throws {
        let source = try readPublicProfileViewSource()
        XCTAssertTrue(source.contains("NavigationLink"),
            "PublicProfileView's garage grid must wrap each card in a NavigationLink")
        XCTAssertTrue(source.contains("PublicCarDetailView("),
            "PublicProfileView's garage grid must push PublicCarDetailView")
    }

    /// Explicit guard that the public profile still wires
    /// `NavigationLink { PublicCarDetailView(...) }` (not some other
    /// view). The Task-12 redesign replaced the List+PublicGarageCard
    /// with a ScrollView+LazyVGrid; this test makes sure the navigation
    /// behaviour itself didn't regress.
    func testPublicProfileView_KeepsNavigationLinkToPublicCarDetailView() throws {
        let source = try readPublicProfileViewSource()
        XCTAssertTrue(source.contains("NavigationLink"),
            "PublicProfileView's garage grid must wrap each card in a NavigationLink")
        XCTAssertTrue(source.contains("PublicCarDetailView("),
            "PublicProfileView's garage grid must push PublicCarDetailView")
    }

    // MARK: - Inline card tap-handler guard

    /// The inline `publicCarCard` function must NOT install an
    /// `onTapGesture` on the card content; the wrapping `NavigationLink`
    /// is the tap handler. A gesture-in-link would double-handle on iOS 17+.
    func testPublicCarCard_DoesNotOwnItsOwnTapHandler() throws {
        let source = try readPublicProfileViewSource()
        // Extract just the publicCarCard function body
        guard let funcRange = source.range(of: "private func publicCarCard(") else {
            XCTFail("publicCarCard function not found in PublicProfileView.swift")
            return
        }
        let cardBody = String(source[funcRange.lowerBound...])
        XCTAssertFalse(cardBody.contains("onTapGesture"),
            "publicCarCard must let the parent NavigationLink own the tap; the card itself should not install an onTapGesture")
    }

    // MARK: - ScrollView layout guard

    /// The redesigned public profile must use a `ScrollView` + `VStack`
    /// layout, not the old `List` / `.insetGrouped` pattern.
    func testPublicProfileView_UsesScrollViewLayout() throws {
        let source = try readPublicProfileViewSource()
        XCTAssertTrue(source.contains("ScrollView"),
            "PublicProfileView must use ScrollView layout after Task-12 redesign")
        XCTAssertFalse(source.contains(".insetGrouped"),
            "PublicProfileView must not use .insetGrouped List style after Task-12 redesign")
    }

    /// The public car detail view must distinguish "no data recorded"
    /// from "stats haven't synced for this car yet" in its empty
    /// state. This is a source-order guard for spec section 4.2.3:
    /// the new copy must exist on disk so the client-side fix doesn't
    /// regress.
    func testPublicCarDetailView_HasStatsNotSyncedEmptyStateCopy() throws {
        let source = try readPublicCarDetailViewSource()
        XCTAssertTrue(source.contains("Stats haven't synced for this car yet."),
            "PublicCarDetailView must render the new 'Stats haven't synced' copy when the blob is non-empty but has no key for this car")
    }

    // MARK: - Helpers

    private func readPublicProfileViewSource() throws -> String {
        try readSourceFile(name: "PublicProfileView.swift", in: "Views")
    }

    private func readPublicCarDetailViewSource() throws -> String {
        try readSourceFile(name: "PublicCarDetailView.swift", in: "Views")
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
}
