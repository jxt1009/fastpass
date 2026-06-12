import XCTest
@testable import FastTrack

@MainActor
final class ToastManagerTests: XCTestCase {

    override func setUp() async throws {
        // Reset shared state between tests
        ToastManager.shared.dismiss()
    }

    func testShow_SetsCurrentMessage() {
        let manager = ToastManager.shared
        manager.show(ToastMessage(text: "Saved"))
        XCTAssertEqual(manager.current?.text, "Saved")
        XCTAssertNil(manager.current?.actionLabel)
    }

    func testShow_WithAction_KeepsActionLabel() {
        let manager = ToastManager.shared
        var actionFired = false
        manager.show(ToastMessage(text: "Deleted", actionLabel: "Undo") { actionFired = true })
        XCTAssertEqual(manager.current?.actionLabel, "Undo")
        XCTAssertNotNil(manager.current?.action)
    }

    func testShow_ReplacesExistingToast() {
        let manager = ToastManager.shared
        manager.show(ToastMessage(text: "First"))
        manager.show(ToastMessage(text: "Second"))
        XCTAssertEqual(manager.current?.text, "Second")
    }

    func testDismiss_ClearsCurrent() {
        let manager = ToastManager.shared
        manager.show(ToastMessage(text: "Hi"))
        XCTAssertNotNil(manager.current)
        manager.dismiss()
        XCTAssertNil(manager.current)
    }

    func testShow_AutoDismissesAfterDelay() async throws {
        let manager = ToastManager.shared
        manager.show(ToastMessage(text: "Bye"), autoDismissAfter: 0.1)
        XCTAssertNotNil(manager.current)
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNil(manager.current)
    }

    func testShow_WithAction_UsesLongerDelay() async throws {
        let manager = ToastManager.shared
        manager.show(ToastMessage(text: "Deleted", actionLabel: "Undo", action: {}),
                     autoDismissAfter: 0.1)
        // 0.1s delay was provided, but action present bumps to 4s minimum.
        try await Task.sleep(nanoseconds: 250_000_000)
        XCTAssertNotNil(manager.current, "Toast with action should still be visible after 0.25s")
    }
}
