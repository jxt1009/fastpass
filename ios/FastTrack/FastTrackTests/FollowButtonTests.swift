import XCTest
import SwiftUI
@testable import FastTrack

@MainActor
final class FollowButtonTests: XCTestCase {

    func testOnError_NotCalledOnSuccess() async throws {
        var errored = false
        let binding = Binding<Bool>(get: { false }, set: { _ in })
        let button = FollowButton(
            isFollowing: binding,
            username: "testuser",
            isSelf: false,
            onError: { _ in errored = true }
        )
        _ = button.body
        XCTAssertFalse(errored, "no error expected from initialization")
    }

    func testIsSelf_HidesButton() {
        let binding = Binding<Bool>(get: { false }, set: { _ in })
        let button = FollowButton(
            isFollowing: binding,
            username: "me",
            isSelf: true
        )
        _ = button.body
    }
}
