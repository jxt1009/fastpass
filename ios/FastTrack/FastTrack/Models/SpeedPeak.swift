import Foundation

enum SpeedSource: String, Codable, Equatable {
    case fused
    case gps
}

struct SpeedPeak: Codable, Equatable {
    let timestamp: Date
    let speed: Double
    let source: SpeedSource
    let confidence: Double
}
