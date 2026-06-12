import Foundation
import CoreLocation

struct Drive: Identifiable, Codable, Equatable {
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

    // Car information
    var carId: String?          // Reference to UserCar.id
    var carMake: String?        // Stored snapshot for history
    var carModel: String?       // Stored snapshot for history
    var carYear: Int?           // Stored snapshot for history
    var carTrim: String?        // Stored snapshot for history
    var carNickname: String?    // Stored snapshot for history

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
    var zeroToSixtyAttempts: [ZeroToSixtyAttempt] = []  // every 0-60 launch detected

    var carDisplayString: String {
        if let nickname = carNickname, !nickname.isEmpty {
            return nickname
        }
        
        let parts: [String] = [
            carYear.map { String($0) } ?? "",
            carMake ?? "",
            carModel ?? "",
            carTrim ?? ""
        ].filter { !$0.isEmpty }
        
        return parts.isEmpty ? "Unknown Car" : parts.joined(separator: " ")
    }

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
        case carId = "car_id"
        case carMake = "car_make"
        case carModel = "car_model"
        case carYear = "car_year"
        case carTrim = "car_trim"
        case carNickname = "car_nickname"
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
        case zeroToSixtyAttempts = "zero_to_sixty_attempts"
    }

    /// Custom decoder so that `null` for the new `zero_to_sixty_attempts`
    /// column (which GORM emits for drives that pre-date the schema change)
    /// is tolerated instead of failing the whole array decode.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id                  = try c.decodeIfPresent(Int.self,                forKey: .id)
        self.userID              = try c.decode(Int.self,                          forKey: .userID)
        self.startTime           = try c.decode(Date.self,                         forKey: .startTime)
        self.endTime             = try c.decode(Date.self,                         forKey: .endTime)
        self.startLatitude       = try c.decode(Double.self,                       forKey: .startLatitude)
        self.startLongitude      = try c.decode(Double.self,                       forKey: .startLongitude)
        self.endLatitude         = try c.decode(Double.self,                       forKey: .endLatitude)
        self.endLongitude        = try c.decode(Double.self,                       forKey: .endLongitude)
        self.distance            = try c.decode(Double.self,                       forKey: .distance)
        self.duration            = try c.decode(Double.self,                       forKey: .duration)
        self.maxSpeed            = try c.decode(Double.self,                       forKey: .maxSpeed)
        self.minSpeed            = try c.decode(Double.self,                       forKey: .minSpeed)
        self.avgSpeed            = try c.decode(Double.self,                       forKey: .avgSpeed)
        self.routeData           = try c.decodeIfPresent(String.self,             forKey: .routeData)
        self.carId               = try c.decodeIfPresent(String.self,             forKey: .carId)
        self.carMake             = try c.decodeIfPresent(String.self,             forKey: .carMake)
        self.carModel            = try c.decodeIfPresent(String.self,             forKey: .carModel)
        self.carYear             = try c.decodeIfPresent(Int.self,                forKey: .carYear)
        self.carTrim             = try c.decodeIfPresent(String.self,             forKey: .carTrim)
        self.carNickname         = try c.decodeIfPresent(String.self,             forKey: .carNickname)
        self.stoppedTime         = try c.decode(Double.self,                       forKey: .stoppedTime)
        self.leftTurns           = try c.decode(Int.self,                          forKey: .leftTurns)
        self.rightTurns          = try c.decode(Int.self,                          forKey: .rightTurns)
        self.brakeEvents         = try c.decode(Int.self,                          forKey: .brakeEvents)
        self.laneChanges         = try c.decode(Int.self,                          forKey: .laneChanges)
        self.maxAcceleration     = try c.decode(Double.self,                       forKey: .maxAcceleration)
        self.maxDeceleration     = try c.decode(Double.self,                       forKey: .maxDeceleration)
        self.peakGForce          = try c.decode(Double.self,                       forKey: .peakGForce)
        self.topCornerSpeed      = try c.decode(Double.self,                       forKey: .topCornerSpeed)
        self.best060Time         = try c.decodeIfPresent(Double.self,              forKey: .best060Time)
        self.zeroToSixtyAttempts = try c.decodeIfPresent([ZeroToSixtyAttempt].self, forKey: .zeroToSixtyAttempts) ?? []
    }

    // Explicit memberwise init — required because `init(from:)` above
    // suppresses the synthesized memberwise init in Swift. Keep the
    // argument order in sync with `CodingKeys` to avoid surprises.
    init(
        id: Int? = nil,
        userID: Int,
        startTime: Date,
        endTime: Date,
        startLatitude: Double,
        startLongitude: Double,
        endLatitude: Double,
        endLongitude: Double,
        distance: Double,
        duration: Double,
        maxSpeed: Double,
        minSpeed: Double,
        avgSpeed: Double,
        routeData: String? = nil,
        carId: String? = nil,
        carMake: String? = nil,
        carModel: String? = nil,
        carYear: Int? = nil,
        carTrim: String? = nil,
        carNickname: String? = nil,
        stoppedTime: Double,
        leftTurns: Int,
        rightTurns: Int,
        brakeEvents: Int,
        laneChanges: Int,
        maxAcceleration: Double,
        maxDeceleration: Double,
        peakGForce: Double,
        topCornerSpeed: Double,
        best060Time: Double? = nil,
        zeroToSixtyAttempts: [ZeroToSixtyAttempt] = []
    ) {
        self.id                  = id
        self.userID              = userID
        self.startTime           = startTime
        self.endTime             = endTime
        self.startLatitude       = startLatitude
        self.startLongitude      = startLongitude
        self.endLatitude         = endLatitude
        self.endLongitude        = endLongitude
        self.distance            = distance
        self.duration            = duration
        self.maxSpeed            = maxSpeed
        self.minSpeed            = minSpeed
        self.avgSpeed            = avgSpeed
        self.routeData           = routeData
        self.carId               = carId
        self.carMake             = carMake
        self.carModel            = carModel
        self.carYear             = carYear
        self.carTrim             = carTrim
        self.carNickname         = carNickname
        self.stoppedTime         = stoppedTime
        self.leftTurns           = leftTurns
        self.rightTurns          = rightTurns
        self.brakeEvents         = brakeEvents
        self.laneChanges         = laneChanges
        self.maxAcceleration     = maxAcceleration
        self.maxDeceleration     = maxDeceleration
        self.peakGForce          = peakGForce
        self.topCornerSpeed      = topCornerSpeed
        self.best060Time         = best060Time
        self.zeroToSixtyAttempts = zeroToSixtyAttempts
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
            carId: "example-car",
            carMake: "Porsche",
            carModel: "911",
            carYear: 2023,
            carTrim: "GT3",
            carNickname: "Track Car",
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

// MARK: - Custom Equatable (avoids @retroactive conformance on CLLocationCoordinate2D)

extension Drive {
    static func == (lhs: Drive, rhs: Drive) -> Bool {
        lhs.id == rhs.id &&
        lhs.userID == rhs.userID &&
        lhs.startTime == rhs.startTime &&
        lhs.endTime == rhs.endTime &&
        lhs.startLatitude == rhs.startLatitude &&
        lhs.startLongitude == rhs.startLongitude &&
        lhs.endLatitude == rhs.endLatitude &&
        lhs.endLongitude == rhs.endLongitude &&
        lhs.distance == rhs.distance &&
        lhs.duration == rhs.duration &&
        lhs.maxSpeed == rhs.maxSpeed &&
        lhs.minSpeed == rhs.minSpeed &&
        lhs.avgSpeed == rhs.avgSpeed &&
        lhs.routeData == rhs.routeData &&
        lhs.carId == rhs.carId &&
        lhs.carMake == rhs.carMake &&
        lhs.carModel == rhs.carModel &&
        lhs.carYear == rhs.carYear &&
        lhs.carTrim == rhs.carTrim &&
        lhs.carNickname == rhs.carNickname &&
        lhs.stoppedTime == rhs.stoppedTime &&
        lhs.leftTurns == rhs.leftTurns &&
        lhs.rightTurns == rhs.rightTurns &&
        lhs.brakeEvents == rhs.brakeEvents &&
        lhs.laneChanges == rhs.laneChanges &&
        lhs.maxAcceleration == rhs.maxAcceleration &&
        lhs.maxDeceleration == rhs.maxDeceleration &&
        lhs.peakGForce == rhs.peakGForce &&
        lhs.topCornerSpeed == rhs.topCornerSpeed &&
        lhs.best060Time == rhs.best060Time &&
        lhs.zeroToSixtyAttempts == rhs.zeroToSixtyAttempts
    }
}


