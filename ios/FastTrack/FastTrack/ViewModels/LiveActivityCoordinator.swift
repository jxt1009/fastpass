import Foundation
import ActivityKit
import os

@MainActor
final class LiveActivityCoordinator: LiveActivityController {
    private static let log = Logger(subsystem: "app.fasttrack", category: "live-activity")
    private var liveActivity: Activity<DriveActivityAttributes>?
    private var lastUpdate: Date?

    func start(recordingStartTime: Date?) async {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Self.log.error("Live Activities not authorized")
            return
        }
        guard let startDate = recordingStartTime else {
            Self.log.error("start() called with nil recordingStartTime")
            return
        }
        lastUpdate = nil
        let attrs = DriveActivityAttributes(startDate: startDate)
        let state = DriveActivityAttributes.DriveActivityState(
            phase: .recording,
            speedMph: 0, gForce: 0, distanceMiles: 0, maxSpeedMph: 0,
            elapsedSeconds: 0
        )
        let content = ActivityContent(state: state, staleDate: nil)
        do {
            liveActivity = try Activity<DriveActivityAttributes>.request(
                attributes: attrs, content: content, pushType: nil
            )
            Self.log.info("Live Activity started for drive at \(startDate, privacy: .public)")
        } catch {
            Self.log.error("Failed to start Live Activity: \(error.localizedDescription, privacy: .public)")
        }
    }

    func update(speedMph: Double, distanceMiles: Double, currentGForce: Double, currentMaxSpeed: Double) async {
        guard let activity = liveActivity else { return }
        let now = Date()
        if let last = lastUpdate, now.timeIntervalSince(last) < 1.0 { return }
        lastUpdate = now
        let state = DriveActivityAttributes.DriveActivityState(
            phase: .recording,
            speedMph: speedMph,
            gForce: currentGForce,
            distanceMiles: distanceMiles,
            maxSpeedMph: currentMaxSpeed * 2.23694,
            elapsedSeconds: now.timeIntervalSince(activity.attributes.startDate)
        )
        await activity.update(ActivityContent(state: state, staleDate: now.addingTimeInterval(10)))
    }

    func end(finalState: DriveActivityAttributes.DriveActivityState?, lingerSeconds: TimeInterval) async {
        guard let activity = liveActivity else {
            Self.log.error("end() called with no stored live activity — sweeping orphans")
            await dismissAllOrphans()
            return
        }
        lastUpdate = nil
        let final = finalState ?? DriveActivityAttributes.DriveActivityState(
            phase: .ended, speedMph: 0, gForce: 0, distanceMiles: 0, maxSpeedMph: 0, elapsedSeconds: 0
        )
        let policy: ActivityUIDismissalPolicy = lingerSeconds > 0
            ? .after(Date().addingTimeInterval(lingerSeconds))
            : .immediate
        await activity.end(
            ActivityContent(state: final, staleDate: Date().addingTimeInterval(lingerSeconds + 5)),
            dismissalPolicy: policy
        )
        liveActivity = nil
        // Failsafe: end any activity still tracked by the system. If the
        // stored Activity reference was stale/invalidated the call above is a
        // no-op and the Live Activity would keep running; this catches it.
        for remaining in Activity<DriveActivityAttributes>.activities {
            Self.log.error("Found orphan after explicit end — cleaning up")
            await remaining.end(nil, dismissalPolicy: .immediate)
        }
    }

    func dismissAllOrphans() async {
        let orphans = Activity<DriveActivityAttributes>.activities
        if !orphans.isEmpty {
            Self.log.info("Sweeping \(orphans.count) orphaned Live Activity(s)")
        }
        for activity in orphans {
            await activity.end(nil, dismissalPolicy: .immediate)
        }
        liveActivity = nil
    }
}
