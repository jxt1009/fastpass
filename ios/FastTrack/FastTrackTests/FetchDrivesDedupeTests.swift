import XCTest
@testable import FastTrack

final class FetchDrivesDedupeTests: XCTestCase {

    func test_inflightTaskClearedAfterCall() async {
        let api = APIService()
        _ = try? await api.fetchDrives()
        await MainActor.run {
            XCTAssertNil(api.inflightFetchDrives)
        }
    }
}
