import Foundation
import CoreLocation

struct Drive: Identifiable, Codable {
    var id: Int?
    var userID: Int
    var startTime: Date
    var endTime: Date
    var startLatitude: Double
    var startLongitude: Double
    var endLatitude: Double
    var endLongitude: Double
    var distance: Double        // meters
    var duration: Double        // seconds
    var maxSpeed: Double        // meters per second
    var minSpeed: Double        // meters per second
    var avgSpeed: Double        // meters per second
    var routeData: String?

    // Extended stats
    var stoppedTime: Double     // seconds at < 1 mph
    var leftTurns: Int
    var rightTurns: Int
    var brakeEvents: Int
    var laneChanges: Int
    var maxAcceleration: Double  // m/s²
    var maxDeceleration: Double  // m/s² (positive)
    var peakGForce: Double       // G
    var topCornerSpeed: Double   // m/s
    var best060Time: Double?     // seconds; nil if never hit 60 mph

    var durationString: String {
        let h = Int(duration) / 3600
        let m = (Int(duration) % 3600) / 60
        let s = Int(duration) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    enum CodingKeys: String, CodingKey {
        case id
        case userID = "user_id"
        case startTime = "start_time"
        case endTime = "end_time"
        case startLatitude = "start_latitude"
        case startLongitude = "start_longitude"
        case endLatitude = "end_latitude"
        case endLongitude = "end_longitude"
        case distance
        case duration
        case maxSpeed = "max_speed"
        case minSpeed = "min_speed"
        case avgSpeed = "avg_speed"
        case routeData = "route_data"
        case stoppedTime = "stopped_time"
        case leftTurns = "left_turns"
        case rightTurns = "right_turns"
        case brakeEvents = "brake_events"
        case laneChanges = "lane_changes"
        case maxAcceleration = "max_acceleration"
        case maxDeceleration = "max_deceleration"
        case peakGForce = "peak_g_force"
        case topCornerSpeed = "top_corner_speed"
        case best060Time = "best_060_time"
    }

    static var example: Drive {
        Drive(
            id: 1,
            userID: 1,
            startTime: Date().addingTimeInterval(-3600),
            endTime: Date(),
            startLatitude: 37.7749,
            startLongitude: -122.4194,
            endLatitude: 37.8044,
            endLongitude: -122.2712,
            distance: 15000,
            duration: 1800,
            maxSpeed: 35.7632,
            minSpeed: 0,
            avgSpeed: 22.352,
            routeData: nil,
            stoppedTime: 180,
            leftTurns: 12,
            rightTurns: 10,
            brakeEvents: 3,
            laneChanges: 5,
            maxAcceleration: 3.2,
            maxDeceleration: 4.1,
            peakGForce: 0.42,
            topCornerSpeed: 20.0,
            best060Time: 8.4
        )
    }
}

// MARK: - Aggregate stats across all drives

struct UserStats {
    var totalDistance: Double       // meters
    var totalDuration: Double       // seconds
    var totalStoppedTime: Double    // seconds
    var totalTrips: Int
    var topSpeed: Double            // m/s
    var best060Time: Double?        // seconds
    var totalLeftTurns: Int
    var totalRightTurns: Int
    var totalBrakeEvents: Int
    var totalLaneChanges: Int
    var overallMaxAcceleration: Double   // m/s²
    var overallMaxDeceleration: Double   // m/s²
    var overallPeakGForce: Double        // G
    var overallTopCornerSpeed: Double    // m/s
    var totalStops: Int                  // approximate: drives where stopped > 30s

    var avgTripLengthMeters: Double {
        totalTrips > 0 ? totalDistance / Double(totalTrips) : 0
    }

    var turnPreferencePct: Double {
        let total = totalLeftTurns + totalRightTurns
        guard total > 0 else { return 0.5 }
        return Double(totalLeftTurns) / Double(total)
    }

    static func from(drives: [Drive]) -> UserStats {
        var s = UserStats(
            totalDistance: 0, totalDuration: 0, totalStoppedTime: 0,
            totalTrips: drives.count, topSpeed: 0, best060Time: nil,
            totalLeftTurns: 0, totalRightTurns: 0, totalBrakeEvents: 0,
            totalLaneChanges: 0, overallMaxAcceleration: 0, overallMaxDeceleration: 0,
            overallPeakGForce: 0, overallTopCornerSpeed: 0, totalStops: 0
        )
        for d in drives {
            s.totalDistance += d.distance
            s.totalDuration += d.duration
            s.totalStoppedTime += d.stoppedTime
            if d.maxSpeed > s.topSpeed { s.topSpeed = d.maxSpeed }
            if let t = d.best060Time { s.best060Time = min(s.best060Time ?? t, t) }
            s.totalLeftTurns += d.leftTurns
            s.totalRightTurns += d.rightTurns
            s.totalBrakeEvents += d.brakeEvents
            s.totalLaneChanges += d.laneChanges
            if d.maxAcceleration > s.overallMaxAcceleration { s.overallMaxAcceleration = d.maxAcceleration }
            if d.maxDeceleration > s.overallMaxDeceleration { s.overallMaxDeceleration = d.maxDeceleration }
            if d.peakGForce > s.overallPeakGForce { s.overallPeakGForce = d.peakGForce }
            if d.topCornerSpeed > s.overallTopCornerSpeed { s.overallTopCornerSpeed = d.topCornerSpeed }
            if d.stoppedTime > 30 { s.totalStops += 1 }
        }
        return s
    }

    static var empty: UserStats {
        UserStats(
            totalDistance: 0, totalDuration: 0, totalStoppedTime: 0,
            totalTrips: 0, topSpeed: 0, best060Time: nil,
            totalLeftTurns: 0, totalRightTurns: 0, totalBrakeEvents: 0,
            totalLaneChanges: 0, overallMaxAcceleration: 0, overallMaxDeceleration: 0,
            overallPeakGForce: 0, overallTopCornerSpeed: 0, totalStops: 0
        )
    }
}

// MARK: - CLLocationCoordinate2D Equatable

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}


