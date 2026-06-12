import Foundation

/// A value-type snapshot of the route inputs that `stopRecording`
/// hands to the off-main serializer. Copying the arrays out of
/// `DriveManager` first lets the rest of `stopRecording` (and any
/// subsequent `startRecording` reset) proceed without a data race
/// while the JSON is being built.
struct RouteSerializationSnapshot: Sendable {
    let richRoutePoints: [(lat: Double, lng: Double, speed: Double, ts: Double)]
    let recordedRouteEvents: [(type: String, lat: Double, lng: Double, ts: Double)]
    let attempts: [ZeroToSixtyAttempt]
}

struct RouteSerializerOutput: Sendable {
    let v1String: String
    let v2Array: [[String: Any]]
}

/// Builds the v2 `routeData` JSON string for a drive. Pure function;
/// no DriveManager dependency, safe to call from any thread.
enum RouteSerializer {
    static func encodeV2(snapshot: RouteSerializationSnapshot) -> String? {
        let pointDicts: [[String: Any]] = snapshot.richRoutePoints.map { p in
            ["lat": p.lat, "lng": p.lng, "speed": p.speed, "ts": p.ts]
        }
        var eventDicts: [[String: Any]] = snapshot.recordedRouteEvents.map { e in
            ["type": e.type, "lat": e.lat, "lng": e.lng, "ts": e.ts]
        }
        for attempt in snapshot.attempts {
            eventDicts.append([
                "type": "zero_to_sixty",
                "lat": attempt.startLatitude,
                "lng": attempt.startLongitude,
                "ts": attempt.endTimestamp,
                "start_ts": attempt.startTimestamp,
                "end_ts": attempt.endTimestamp,
                "start_index": attempt.startIndex,
                "end_index": attempt.endIndex,
                "time_seconds": attempt.elapsedSeconds
            ])
        }
        let payload: [String: Any] = ["v": 2, "points": pointDicts, "events": eventDicts]
        guard let data = try? JSONSerialization.data(withJSONObject: payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func encode(_ snapshot: RouteSerializationSnapshot) -> RouteSerializerOutput {
        let pointDicts: [[String: Any]] = snapshot.richRoutePoints.map { p in
            ["lat": p.lat, "lng": p.lng, "speed": p.speed, "ts": p.ts]
        }
        let v1Data = try! JSONSerialization.data(withJSONObject: pointDicts)
        let v1String = String(data: v1Data, encoding: .utf8) ?? "[]"
        return RouteSerializerOutput(v1String: v1String, v2Array: pointDicts)
    }
}
