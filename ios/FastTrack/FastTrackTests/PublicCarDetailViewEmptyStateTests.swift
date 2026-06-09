import XCTest
@testable import FastTrack

// Source-order regression guard for spec section 4.2.3: the public car
// detail view's empty state must distinguish "no driving data" (blob
// empty) from "stats haven't synced" (blob non-empty but no matching
// key). The simplest, most durable way to assert that is to check
// the new copy exists in the file on disk. Like the other line-order
// guards in `PublicProfileRedesignTests`, we read the source file
// rather than spinning up a SwiftUI snapshot harness.

final class PublicCarDetailViewEmptyStateTests: XCTestCase {

    /// The new copy must be present in the source file. Catches
    /// accidental removal during future refactors of the
    /// `InstrumentCard` empty-state branch.
    func testPublicCarDetailView_HasStatsNotSyncedCopy() throws {
        let source = try readPublicCarDetailViewSource()
        XCTAssertTrue(
            source.contains("Stats haven't synced for this car yet."),
            "PublicCarDetailView must render the new 'Stats haven't synced for this car yet.' copy for the non-empty-blob, no-key-match path"
        )
    }

    /// The legacy "no driving data" copy must still be present for
    /// the empty-blob case. Pinning both strings prevents a future
    /// edit from collapsing them into one (which would lose the
    /// nuance between "never driven" and "stats pending sync").
    func testPublicCarDetailView_KeepsNoDrivingDataCopy() throws {
        let source = try readPublicCarDetailViewSource()
        XCTAssertTrue(
            source.contains("No driving data recorded for this car yet."),
            "PublicCarDetailView must keep the original 'No driving data' copy for the empty-blob case"
        )
    }

    // MARK: - Helpers

    private func readPublicCarDetailViewSource() throws -> String {
        let thisFile = (#filePath as NSString)
        let candidates = [
            thisFile.deletingLastPathComponent + "/../FastTrack/Views/PublicCarDetailView.swift",
            thisFile.deletingLastPathComponent + "/../../FastTrack/FastTrack/Views/PublicCarDetailView.swift",
        ].map { (path: String) -> String in
            (path as NSString).standardizingPath
        }
        for path in candidates {
            if let data = FileManager.default.contents(atPath: path),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        XCTFail("PublicCarDetailView.swift not found at expected locations: \(candidates). Regression guard cannot run.")
        struct FileNotFound: Error {}
        throw FileNotFound()
    }
}
