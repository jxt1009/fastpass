import XCTest
import UIKit
@testable import FastTrack

// Tests for the hero photo editor sheet in `CarDetailView` (PR 3 of the
// 2026-06-09 design). The sheet's "use existing photo" path downloads
// the photo via `URLSession.shared.data(from:)` and decodes the bytes
// to a `UIImage`; that download is the only network entry point we
// stub. The source-order guards then assert the wiring in
// `CarDetailView` itself: a `pencil.circle.fill` overlay on the hero
// and a sheet that presents `CarHeroPhotoEditorSheet`.

final class CarHeroPhotoEditorSheetTests: XCTestCase {

    // MARK: - URLSession stubbing

    private final class StubURLProtocol: URLProtocol {
        static var requestHandler: ((URLRequest) -> (HTTPURLResponse, Data?))?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            guard let handler = StubURLProtocol.requestHandler else {
                let response = HTTPURLResponse(
                    url: request.url!,
                    statusCode: 500,
                    httpVersion: nil,
                    headerFields: nil
                )!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocolDidFinishLoading(self)
                return
            }
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
    }

    override func tearDown() {
        StubURLProtocol.requestHandler = nil
        URLProtocol.unregisterClass(StubURLProtocol.self)
        super.tearDown()
    }

    // MARK: - Download existing photo

    /// A 1x1 white PNG. Smallest valid PNG that survives a round-trip
    /// through UIImage(data:) on the iOS test simulators.
    private let tinyPng: Data = Data([
        0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
        0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
        0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
        0x08, 0x02, 0x00, 0x00, 0x00, 0x90, 0x77, 0x53,
        0xDE, 0x00, 0x00, 0x00, 0x0C, 0x49, 0x44, 0x41,
        0x54, 0x08, 0xD7, 0x63, 0xF8, 0xCF, 0xC0, 0x00,
        0x00, 0x00, 0x03, 0x00, 0x01, 0x5B, 0x9C, 0x8E,
        0x9B, 0x00, 0x00, 0x00, 0x00, 0x49, 0x45, 0x4E,
        0x44, 0xAE, 0x42, 0x60, 0x82
    ])

    func testLoadImage_decodesServerResponse() async throws {
        let url = URL(string: "https://example.com/cars/abc/photo.png")!
        StubURLProtocol.requestHandler = { req in
            XCTAssertEqual(req.url, url)
            return (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                self.tinyPng
            )
        }

        let image = try await CarHeroPhotoEditorSheet.loadImage(from: url)
        XCTAssertGreaterThan(image.size.width * image.size.height, 0,
            "Downloaded bytes must decode to a non-empty UIImage")
    }

    func testLoadImage_throwsOnNonImageResponse() async {
        let url = URL(string: "https://example.com/cars/abc/photo.html")!
        StubURLProtocol.requestHandler = { req in
            (
                HTTPURLResponse(url: req.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!,
                Data("not an image".utf8)
            )
        }

        do {
            _ = try await CarHeroPhotoEditorSheet.loadImage(from: url)
            XCTFail("Expected loadImage to throw when the response is not a valid image")
        } catch {
            // expected
        }
    }

    func testLoadImage_propagatesHTTPError() async {
        let url = URL(string: "https://example.com/cars/missing/photo.png")!
        StubURLProtocol.requestHandler = { req in
            (
                HTTPURLResponse(url: req.url!, statusCode: 404, httpVersion: nil, headerFields: nil)!,
                nil
            )
        }

        do {
            _ = try await CarHeroPhotoEditorSheet.loadImage(from: url)
            XCTFail("Expected loadImage to throw on a 404 response")
        } catch {
            // expected
        }
    }

    /// `resizedForAvatar` is a no-op when the source is already at or
    /// below the max dimension. This guards the assumption the upload
    /// path depends on: a 1x1 image survives the resize step
    /// unchanged.
    func testResizedForAvatar_isNoopBelowMaxDimension() {
        let image = UIImage(data: tinyPng)!
        let resized = image.resizedForAvatar(maxDimension: 800)
        XCTAssertEqual(resized.size, image.size,
            "1x1 source must be returned unchanged by resize(maxDimension: 800)")
    }

    // MARK: - Source-order guards

    func testCarDetailView_heroHasPencilCircleFillOverlay() throws {
        let source = try readCarDetailViewSource()
        XCTAssertTrue(source.contains("pencil.circle.fill"),
            "CarDetailView must include a pencil.circle.fill overlay for hero photo edits")
    }

    func testCarDetailView_presentsCarHeroPhotoEditorSheet() throws {
        let source = try readCarDetailViewSource()
        XCTAssertTrue(source.contains("CarHeroPhotoEditorSheet"),
            "CarDetailView must present CarHeroPhotoEditorSheet")
        XCTAssertTrue(source.contains("showingHeroPhotoEditor"),
            "CarDetailView must own the showingHeroPhotoEditor state")
    }

    func testCarDetailView_doesNotRemoveExistingEditCarEntry() throws {
        let source = try readCarDetailViewSource()
        XCTAssertTrue(source.contains("showingEditCar = true"),
            "The toolbar pencil must still open the full EditCarView")
        XCTAssertTrue(source.contains("EditCarView(carId: carId)"),
            "The EditCarView sheet must remain in the modifier chain")
    }

    // MARK: - Helpers

    private func readCarDetailViewSource() throws -> String {
        let thisFile = (#filePath as NSString)
        let candidates = [
            thisFile.deletingLastPathComponent + "/../FastTrack/Views/CarDetailView.swift",
            thisFile.deletingLastPathComponent + "/../../FastTrack/FastTrack/Views/CarDetailView.swift",
        ].map { (path: String) -> String in
            (path as NSString).standardizingPath
        }
        for path in candidates {
            if let data = FileManager.default.contents(atPath: path),
               let text = String(data: data, encoding: .utf8) {
                return text
            }
        }
        XCTFail("CarDetailView.swift not found at expected locations: \(candidates).")
        struct FileNotFound: Error {}
        throw FileNotFound()
    }
}
