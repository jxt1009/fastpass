import SwiftUI
import UIKit
import Combine

protocol IdleTimerControlling: AnyObject {
    var isIdleTimerDisabled: Bool { get set }
}

extension UIApplication: IdleTimerControlling {}

/// Single owner of `UIApplication.shared.isIdleTimerDisabled`. Recomputes the
/// flag from `(isRecording, keepScreenOn, scenePhase)` so any caller can flip
/// one input and the controller keeps the system flag in sync.
final class ScreenWakeController {
    private let idleTimer: IdleTimerControlling
    private var lastApplied: Bool?

    init(idleTimer: IdleTimerControlling = UIApplication.shared) {
        self.idleTimer = idleTimer
    }

    @MainActor
    func update(isRecording: Bool, keepScreenOn: Bool, scenePhase: ScenePhase) {
        let shouldDisable = isRecording && keepScreenOn && scenePhase == .active
        print("🔵⚡ screenWake.update: rec=\(isRecording) keep=\(keepScreenOn) phase=\(scenePhase) → disable=\(shouldDisable) lastApplied=\(String(describing: lastApplied))")
        guard shouldDisable != lastApplied else { return }
        lastApplied = shouldDisable
        idleTimer.isIdleTimerDisabled = shouldDisable
        print("🔵⚡ idleTimer.isIdleTimerDisabled = \(shouldDisable)")
    }
}

/// SwiftUI-friendly wrapper so the app can hold a `ScreenWakeController` as a
/// `@StateObject` and pass it into the view tree as an `@EnvironmentObject`.
@MainActor
final class ScreenWakeControllerObservable: ObservableObject {
    let inner: ScreenWakeController
    @Published private(set) var lastAppliedDisabled: Bool?
    nonisolated init(inner: ScreenWakeController = ScreenWakeController()) {
        self.inner = inner
    }
}
