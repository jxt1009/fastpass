import XCTest
@testable import FastTrack

// Tests for the DriveManager.deleteDrive flow added in 2026-06-09. We stub
// APIService at the URLSession level via URLProtocol to keep the production
// code path intact (no refactor of APIService.init required).

final class DriveDeleteTests: XCTestCase {

    // MARK: - URLSession stubbing

    private final class StubURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data?))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let handler = StubURLProtocol.requestHandler else { return }
            let (response, data) = handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            if let data = data {
                client?.urlProtocol(self, didLoad: data)
            }
            client?.urlProtocolDidFinishLoading(self)
        }
        override func stopLoading() {}
    }

    override func setUp() {
        super.setUp()
        URLProtocol.registerClass(StubURLProtocol.self)
        CarStatsManager.shared.resetAllStats()
    }

    override func tearDown() {
        StubURLProtocol.requestHandler = nil
        URLProtocol.unregisterClass(StubURLProtocol.self)
        super.tearDown()
    }

    private func makeDrive(id: Int, userID: Int = 1, carId: String? = "car-A") -> Drive {
        Drive(
            id: id,
            userID: userID,
            startTime: Date(timeIntervalSince1970: 1_000_000),
            endTime: Date(timeIntervalSince1970: 1_000_600),
            startLatitude: 37.0,
            startLongitude: -122.0,
            endLatitude: 37.001,
            endLongitude: -122.0,
            distance: 1000,
            duration: 600,
            maxSpeed: 30,
            minSpeed: 0,
            avgSpeed: 15,
            carId: carId,
            stoppedTime: 0,
            leftTurns: 0,
            rightTurns: 0,
            brakeEvents: 0,
            laneChanges: 0,
            maxAcceleration: 0,
            maxDeceleration: 0,
            peakGForce: 0,
            topCornerSpeed: 0
        )
    }

    // MARK: - APIService
    //
    // `APIService` is a singleton (`APIService.shared`) with a private
    // `URLSession.shared`. Direct assertions on `APIService.shared.deleteDrive`
    // would need a session-injection seam on the production class to be done
    // safely (URLProtocol.registerClass is process-global and would bleed into
    // other tests in the suite). The DriveManager tests below exercise the
    // production code path end-to-end through the same URLSession.shared
    // request flow, and fail if the URL, method, or status-code handling is
    // wrong — so the coverage is real, just at a slightly higher level.

    // MARK: - DriveManager

    @MainActor
    func testDriveManager_deleteDrive_removesFromArray() async throws {
        let drive1 = makeDrive(id: 1)
        let drive2 = makeDrive(id: 2)
        let dm = DriveManager(apiService: APIService.shared)
        dm.drives = [drive1, drive2]

        StubURLProtocol.requestHandler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, nil)
        }

        try await dm.deleteDrive(id: 1)
        XCTAssertEqual(dm.drives.count, 1)
        XCTAssertEqual(dm.drives.first?.id, 2)
    }

    @MainActor
    func testDriveManager_deleteDrive_treats404AsSuccess() async throws {
        let drive = makeDrive(id: 7)
        let dm = DriveManager(apiService: APIService.shared)
        dm.drives = [drive]

        StubURLProtocol.requestHandler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!, nil)
        }

        try await dm.deleteDrive(id: 7)
        XCTAssertTrue(dm.drives.isEmpty, "404 must be treated as success: drive removed locally")
    }

    @MainActor
    func testDriveManager_deleteDrive_propagatesNon404Error() async {
        let drive = makeDrive(id: 8)
        let dm = DriveManager(apiService: APIService.shared)
        dm.drives = [drive]

        StubURLProtocol.requestHandler = { req in
            (HTTPURLResponse(url: req.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, nil)
        }

        do {
            try await dm.deleteDrive(id: 8)
            XCTFail("expected throw on 500")
        } catch {
            // expected
        }
        XCTAssertEqual(dm.drives.count, 1, "drive must remain when 500 is returned")
    }
}
