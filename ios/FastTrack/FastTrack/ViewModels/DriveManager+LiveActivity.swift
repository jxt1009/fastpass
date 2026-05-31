import Foundation
import ActivityKit

extension DriveManager {

    // MARK: - Live Activity

    func startLiveActivity() {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let startDate = recordingStartTime else { return }
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
            #if DEBUG
            print("⚡ Live Activity start failed: \(error)")
            #endif
        }
    }

    func updateLiveActivity(speedMph: Double, distanceMiles: Double) {
        guard let activity = liveActivity else { return }
        let state = DriveActivityAttributes.DriveActivityState(
            speedMph: speedMph,
            gForce: currentGForce,
            distanceMiles: distanceMiles,
            maxSpeedMph: currentMaxSpeed * 2.23694  // m/s → mph
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10))
        Task {
            await activity.update(content)
        }
    }

    func endLiveActivity() {
        guard let activity = liveActivity else { return }
        let state = DriveActivityAttributes.DriveActivityState(speedMph: 0, gForce: 0, distanceMiles: 0, maxSpeedMph: 0)
        let content = ActivityContent(state: state, staleDate: Date())
        Task {
            // .immediate removes the activity banner/pill right away instead of lingering
            await activity.end(content, dismissalPolicy: .immediate)
            await MainActor.run { self.liveActivity = nil }
        }
    }
}
