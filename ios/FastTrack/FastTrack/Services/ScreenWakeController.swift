import SwiftUI
import UIKit

protocol IdleTimerControlling: AnyObject {
    var isIdleTimerDisabled: Bool { get set }
}

extension UIApplication: IdleTimerControlling {}

/// Single owner of `UIApplication.shared.isIdleTimerDisabled`. Recomputes the
/// flag from `(isRecording, keepScreenOn, scenePhase)` so any caller can flip
/// one input and the controller keeps the system flag in sync.
@MainActor
final class ScreenWakeController {
    private let idleTimer: IdleTimerControlling
    private var lastApplied: Bool?

    init(idleTimer: IdleTimerControlling = UIApplication.shared) {
        self.idleTimer = idleTimer
    }

    func update(isRecording: Bool, keepScreenOn: Bool, scenePhase: ScenePhase) {
        let shouldDisable = isRecording && keepScreenOn && scenePhase == .active
        guard shouldDisable != lastApplied else { return }
        lastApplied = shouldDisable
        idleTimer.isIdleTimerDisabled = shouldDisable
    }
}
