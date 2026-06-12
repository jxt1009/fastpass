import Foundation

// MARK: - StatInfoEntry (moved from SharedComponents)

struct StatInfoEntry: Decodable {
    let title: String
    let summary: String
    let howCalculated: String
    let unit: String?

    enum CodingKeys: String, CodingKey {
        case title, summary, howCalculated, unit
    }
}

// MARK: - StatInfoLoader

enum StatInfoLoader {
    private static var cache: [String: StatInfoEntry]?

    static var all: [String: StatInfoEntry] {
        if let cache { return cache }
        guard let url = Bundle.main.url(forResource: "stat_info", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([StatInfoEntry].self, from: data) else {
            return [:]
        }
        let ids = loadIds()
        let dict = Dictionary(uniqueKeysWithValues: zip(ids, entries))
        cache = dict
        return dict
    }

    static func entry(for id: String) -> StatInfoEntry? {
        all[id]
    }

    private static func loadIds() -> [String] {
        [
            "brakeEvents", "laneChanges", "leftTurns", "rightTurns",
            "peakGForce", "maxAcceleration", "maxDeceleration", "cornerSpeed",
            "zeroToSixty", "smoothness", "performanceCategory", "avgSpeed",
            "stoppedTime", "drivingScore", "cornering", "consistency",
            "periodComparison", "avgMaxSpeed",
            "maneuversSection", "performanceSection"
        ]
    }
}

// MARK: - StatInfo (legacy API wrapper)

enum StatInfo {
    static var brakeEvents: StatInfoEntry { entry("brakeEvents") }
    static var laneChanges: StatInfoEntry { entry("laneChanges") }
    static var leftTurns: StatInfoEntry { entry("leftTurns") }
    static var rightTurns: StatInfoEntry { entry("rightTurns") }
    static var peakGForce: StatInfoEntry { entry("peakGForce") }
    static var maxAcceleration: StatInfoEntry { entry("maxAcceleration") }
    static var maxDeceleration: StatInfoEntry { entry("maxDeceleration") }
    static var cornerSpeed: StatInfoEntry { entry("cornerSpeed") }
    static var zeroToSixty: StatInfoEntry { entry("zeroToSixty") }
    static var smoothness: StatInfoEntry { entry("smoothness") }
    static var performanceCategory: StatInfoEntry { entry("performanceCategory") }
    static var avgSpeed: StatInfoEntry { entry("avgSpeed") }
    static var stoppedTime: StatInfoEntry { entry("stoppedTime") }
    static var drivingScore: StatInfoEntry { entry("drivingScore") }
    static var cornering: StatInfoEntry { entry("cornering") }
    static var consistency: StatInfoEntry { entry("consistency") }
    static var periodComparison: StatInfoEntry { entry("periodComparison") }
    static var avgMaxSpeed: StatInfoEntry { entry("avgMaxSpeed") }
    static var maneuversSection: StatInfoEntry { entry("maneuversSection") }
    static var performanceSection: StatInfoEntry { entry("performanceSection") }

    private static func entry(_ id: String) -> StatInfoEntry {
        StatInfoLoader.entry(for: id) ?? StatInfoEntry(
            title: id,
            summary: "",
            howCalculated: "",
            unit: nil
        )
    }
}
