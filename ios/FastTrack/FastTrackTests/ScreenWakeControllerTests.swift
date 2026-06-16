import XCTest
import SwiftUI
@testable import FastTrack

@MainActor
final class ScreenWakeControllerTests: XCTestCase {

    final class FakeIdleTimer: IdleTimerControlling {
        private(set) var history: [Bool] = []
        var isIdleTimerDisabled: Bool = false {
            didSet { history.append(isIdleTimerDisabled) }
        }
    }

    func test_idleTimerEnabled_whenAppActive_recording_andSettingOn() {
        let timer = FakeIdleTimer()
        let c = ScreenWakeController(idleTimer: timer)
        c.update(isRecording: true, keepScreenOn: true, scenePhase: .active)
        XCTAssertTrue(timer.isIdleTimerDisabled)
    }

    func test_idleTimerEnabled_onlyWhileRecording_whenSettingOn() {
        let timer = FakeIdleTimer()
        let c = ScreenWakeController(idleTimer: timer)
        c.update(isRecording: false, keepScreenOn: true, scenePhase: .active)
        XCTAssertFalse(timer.isIdleTimerDisabled)
    }

    func test_settingOff_neverDisablesIdleTimer() {
        let timer = FakeIdleTimer()
        let c = ScreenWakeController(idleTimer: timer)
        c.update(isRecording: true, keepScreenOn: false, scenePhase: .active)
        XCTAssertFalse(timer.isIdleTimerDisabled)
    }

    func test_backgroundedScene_alwaysReleasesIdleTimer() {
        let timer = FakeIdleTimer()
        let c = ScreenWakeController(idleTimer: timer)
        c.update(isRecording: true, keepScreenOn: true, scenePhase: .active)
        XCTAssertTrue(timer.isIdleTimerDisabled)
        c.update(isRecording: true, keepScreenOn: true, scenePhase: .background)
        XCTAssertFalse(timer.isIdleTimerDisabled)
    }

    func test_repeatedSameInput_doesNotChurnFlag() {
        let timer = FakeIdleTimer()
        let c = ScreenWakeController(idleTimer: timer)
        c.update(isRecording: true, keepScreenOn: true, scenePhase: .active)
        c.update(isRecording: true, keepScreenOn: true, scenePhase: .active)
        c.update(isRecording: true, keepScreenOn: true, scenePhase: .active)
        XCTAssertEqual(timer.history, [true])
    }
}
