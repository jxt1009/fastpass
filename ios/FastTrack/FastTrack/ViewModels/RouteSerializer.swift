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
    let speedStream: [(TimeInterval, Double, Bool, Double)]
    let speedPeaks: [SpeedPeak]
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

    static func encodeV3(snapshot: RouteSerializationSnapshot) -> String? {
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
                "time_seconds": attempt.elapsedSeconds,
                "confidence": attempt.confidence
            ])
        }
        let speedStreamEncoded = encodeSpeedStream(snapshot.speedStream)
        let speedPeaksEncoded: [[String: Any]] = snapshot.speedPeaks.map { p in
            [
                "timestamp": p.timestamp.timeIntervalSince1970,
                "speed": p.speed,
                "source": p.source.rawValue,
                "confidence": p.confidence
            ]
        }
        let payload: [String: Any] = [
            "v": 3,
            "points": pointDicts,
            "events": eventDicts,
            "speed_stream": speedStreamEncoded,
            "speed_peaks": speedPeaksEncoded
        ]
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

    static func encodeSpeedStream(_ stream: [(TimeInterval, Double, Bool, Double)]) -> [[Any]] {
        guard !stream.isEmpty else { return [] }
        var out: [[Any]] = []
        out.reserveCapacity(stream.count)
        out.append([stream[0].0, stream[0].1, stream[0].2 ? 1 : 0, stream[0].3])
        var lastTs = stream[0].0
        for i in 1..<stream.count {
            let (ts, speed, locked, conf) = stream[i]
            let deltaMs = Int(((ts - lastTs) * 1000).rounded())
            out.append([deltaMs, speed, locked ? 1 : 0, conf])
            lastTs = ts
        }
        return out
    }

    static func decodeSpeedStream(_ encoded: [[Any]]) -> [(TimeInterval, Double, Bool, Double)] {
        guard !encoded.isEmpty else { return [] }
        var out: [(TimeInterval, Double, Bool, Double)] = []
        out.reserveCapacity(encoded.count)
        if let first = encoded.first, first.count >= 4,
           let ts = (first[0] as? Double) ?? (first[0] as? NSNumber)?.doubleValue,
           let speed = (first[1] as? Double) ?? (first[1] as? NSNumber)?.doubleValue {
            let locked = ((first[2] as? Int) ?? 0) != 0
            let conf = ((first[3] as? Double) ?? (first[3] as? NSNumber)?.doubleValue) ?? 0
            out.append((ts, speed, locked, conf))
            var lastTs = ts
            for i in 1..<encoded.count {
                let row = encoded[i]
                guard row.count >= 4,
                      let deltaMs = (row[0] as? Int) ?? (row[0] as? NSNumber)?.intValue,
                      let speed = (row[1] as? Double) ?? (row[1] as? NSNumber)?.doubleValue else { continue }
                let locked = ((row[2] as? Int) ?? 0) != 0
                let conf = ((row[3] as? Double) ?? (row[3] as? NSNumber)?.doubleValue) ?? 0
                let ts = lastTs + Double(deltaMs) / 1000.0
                out.append((ts, speed, locked, conf))
                lastTs = ts
            }
        }
        return out
    }
}
