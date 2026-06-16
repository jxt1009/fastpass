import UIKit
import SwiftUI
import Combine

@MainActor
final class ScreenWakeController: ObservableObject {
    private var isRecording: Bool = false
    private var keepScreenOn: Bool = true
    private var scenePhase: ScenePhase = .active

    init() {
        apply()
    }

    func update(isRecording: Bool? = nil, keepScreenOn: Bool? = nil, scenePhase: ScenePhase? = nil) {
        if let isRecording = isRecording { self.isRecording = isRecording }
        if let keepScreenOn = keepScreenOn { self.keepScreenOn = keepScreenOn }
        if let scenePhase = scenePhase { self.scenePhase = scenePhase }
        apply()
    }

    private var shouldDisable: Bool {
        isRecording && keepScreenOn && scenePhase == .active
    }

    private func apply() {
        UIApplication.shared.isIdleTimerDisabled = shouldDisable
    }
}
