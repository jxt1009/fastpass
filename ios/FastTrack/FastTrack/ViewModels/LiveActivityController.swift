import Foundation

@MainActor
protocol LiveActivityController: AnyObject {
    func start(recordingStartTime: Date?)
    func update(speedMph: Double, distanceMiles: Double, currentGForce: Double, currentMaxSpeed: Double) async
    func end(finalState: DriveActivityAttributes.DriveActivityState?, lingerSeconds: TimeInterval) async
    func dismissAllOrphans() async
}
