import Foundation
import ActivityKit

@MainActor
class LiveActivityCoordinator {
    var liveActivity: Activity<DriveActivityAttributes>?
    var lastLiveActivityUpdate: Date?

    func startLiveActivity(recordingStartTime: Date?) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let startDate = recordingStartTime else { return }
        lastLiveActivityUpdate = nil
        let attrs = DriveActivityAttributes(startDate: startDate)
        let state = DriveActivityAttributes.DriveActivityState(speedMph: 0, gForce: 0, distanceMiles: 0, maxSpeedMph: 0)
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            liveActivity = try Activity<DriveActivityAttributes>.request(
                attributes: attrs,
                content: content,
                pushType: nil
            )
        } catch {
        }
    }

    func updateLiveActivity(speedMph: Double, distanceMiles: Double, currentGForce: Double, currentMaxSpeed: Double) {
        guard let activity = liveActivity else { return }
        let now = Date()
        if let last = lastLiveActivityUpdate, now.timeIntervalSince(last) < 1.0 {
            return
        }
        lastLiveActivityUpdate = now
        let state = DriveActivityAttributes.DriveActivityState(
            speedMph: speedMph,
            gForce: currentGForce,
            distanceMiles: distanceMiles,
            maxSpeedMph: currentMaxSpeed * 2.23694
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10))
        Task {
            await activity.update(content)
        }
    }

    func endLiveActivity() {
        guard let activity = liveActivity else { return }
        lastLiveActivityUpdate = nil
        let state = DriveActivityAttributes.DriveActivityState(speedMph: 0, gForce: 0, distanceMiles: 0, maxSpeedMph: 0)
        let content = ActivityContent(state: state, staleDate: Date())
        Task {
            await activity.end(content, dismissalPolicy: .immediate)
            await MainActor.run { self.liveActivity = nil }
        }
    }
}
