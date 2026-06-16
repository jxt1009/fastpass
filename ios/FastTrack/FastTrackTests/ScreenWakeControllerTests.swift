import XCTest
import SwiftUI
@testable import FastTrack

@MainActor
final class ScreenWakeControllerTests: XCTestCase {

    func testNotRecording() {
        let controller = ScreenWakeController()
        controller.update(isRecording: false, keepScreenOn: true, scenePhase: .active)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    func testRecordingAndKeepScreenOnAndActive() {
        let controller = ScreenWakeController()
        controller.update(isRecording: true, keepScreenOn: true, scenePhase: .active)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
    }

    func testRecordingButKeepScreenOnOff() {
        let controller = ScreenWakeController()
        controller.update(isRecording: true, keepScreenOn: false, scenePhase: .active)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    func testRecordingButAppBackgrounded() {
        let controller = ScreenWakeController()
        controller.update(isRecording: true, keepScreenOn: true, scenePhase: .inactive)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
    }

    func testTogglingKeepScreenOnMidRecording() {
        let controller = ScreenWakeController()
        controller.update(isRecording: true, keepScreenOn: true, scenePhase: .active)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
        controller.update(keepScreenOn: false)
        XCTAssertFalse(UIApplication.shared.isIdleTimerDisabled)
        controller.update(keepScreenOn: true)
        XCTAssertTrue(UIApplication.shared.isIdleTimerDisabled)
    }
}
