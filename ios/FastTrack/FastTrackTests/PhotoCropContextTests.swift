import XCTest
@testable import FastTrack

final class PhotoCropContextTests: XCTestCase {
    func testAvatarContext_UsesAvatarSpecificLabelsAndSquareCrop() {
        XCTAssertEqual(PhotoCropContext.avatar.navigationTitle, "Adjust Avatar")
        XCTAssertEqual(PhotoCropContext.avatar.aspectRatio, 1)
        XCTAssertTrue(PhotoCropContext.avatar.locksAspectRatio)
    }

    func testCarContext_UsesCarSpecificLabelsAndSquareCrop() {
        XCTAssertEqual(PhotoCropContext.car.navigationTitle, "Adjust Photo")
        XCTAssertEqual(PhotoCropContext.car.aspectRatio, 1)
        XCTAssertTrue(PhotoCropContext.car.locksAspectRatio)
    }
}
