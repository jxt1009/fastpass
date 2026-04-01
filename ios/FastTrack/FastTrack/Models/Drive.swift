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
    var distance: Double  // meters
    var duration: Double  // seconds
    var maxSpeed: Double  // meters per second
    var minSpeed: Double  // meters per second
    var avgSpeed: Double  // meters per second
    var routeData: String?
    
    var durationString: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        let seconds = Int(duration) % 60
        
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, seconds)
        } else {
            return String(format: "%d:%02d", minutes, seconds)
        }
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
            maxSpeed: 35.7632,  // ~80 mph
            minSpeed: 0,        // ~0 mph
            avgSpeed: 22.352,   // ~50 mph
            routeData: nil
        )
    }
}

// MARK: - Extensions

extension CLLocationCoordinate2D: @retroactive Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
