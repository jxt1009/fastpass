import Foundation
import CoreLocation

/// Ramer–Douglas–Peucker polyline simplification, used to keep the
/// live recording map's polyline short. Pure function; safe to call
/// from any thread. `toleranceMeters` controls how aggressively
/// near-collinear points are collapsed (smaller = more detail);
/// `maxOutput` is a hard cap so a 10-min drive never blows past
/// the GPU's redraw budget.
enum RouteDecimator {

    static func decimate(
        _ points: [CLLocationCoordinate2D],
        toleranceMeters: Double,
        maxOutput: Int = 500
    ) -> [CLLocationCoordinate2D] {
        guard points.count > 2 else { return points }

        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true

        rdp(points: points, start: 0, end: points.count - 1, tolerance: toleranceMeters, keep: &keep)

        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(min(maxOutput, points.count))
        for i in 0..<points.count where keep[i] {
            out.append(points[i])
        }

        // Hard cap: if we still exceed maxOutput, do uniform down-sample.
        if out.count > maxOutput {
            out = uniformStride(out, maxOutput: maxOutput)
        }
        return out
    }

    private static func rdp(
        points: [CLLocationCoordinate2D],
        start: Int, end: Int,
        tolerance: Double,
        keep: inout [Bool]
    ) {
        if end <= start + 1 { return }
        var maxDist = 0.0
        var maxIdx = start
        for i in (start + 1)..<end {
            let d = perpendicularDistanceMeters(
                points[i], points[start], points[end]
            )
            if d > maxDist {
                maxDist = d
                maxIdx = i
            }
        }
        if maxDist > tolerance {
            keep[maxIdx] = true
            rdp(points: points, start: start, end: maxIdx, tolerance: tolerance, keep: &keep)
            rdp(points: points, start: maxIdx, end: end, tolerance: tolerance, keep: &keep)
        }
    }

    /// Perpendicular distance from `p` to the great-circle line
    /// between `a` and `b`, in meters. Uses the equirectangular
    /// approximation — fine for the small spans in a polyline.
    private static func perpendicularDistanceMeters(
        _ p: CLLocationCoordinate2D,
        _ a: CLLocationCoordinate2D,
        _ b: CLLocationCoordinate2D
    ) -> Double {
        let lat0 = (a.latitude + b.latitude) / 2 * .pi / 180
        let mPerDegLat = 111_320.0
        let mPerDegLng = 111_320.0 * cos(lat0)

        let ax = a.longitude * mPerDegLng, ay = a.latitude * mPerDegLat
        let bx = b.longitude * mPerDegLng, by = b.latitude * mPerDegLat
        let px = p.longitude * mPerDegLng, py = p.latitude * mPerDegLat

        let dx = bx - ax, dy = by - ay
        let len2 = dx * dx + dy * dy
        if len2 == 0 {
            let ex = px - ax, ey = py - ay
            return (ex * ex + ey * ey).squareRoot()
        }
        let t = max(0, min(1, ((px - ax) * dx + (py - ay) * dy) / len2))
        let projX = ax + t * dx, projY = ay + t * dy
        let ex = px - projX, ey = py - projY
        return (ex * ex + ey * ey).squareRoot()
    }

    private static func uniformStride(
        _ points: [CLLocationCoordinate2D],
        maxOutput: Int
    ) -> [CLLocationCoordinate2D] {
        guard points.count > maxOutput else { return points }
        var out: [CLLocationCoordinate2D] = []
        out.reserveCapacity(maxOutput)
        let stride = Double(points.count - 1) / Double(maxOutput - 1)
        for i in 0..<maxOutput {
            let idx = Int((Double(i) * stride).rounded())
            out.append(points[min(idx, points.count - 1)])
        }
        return out
    }
}
