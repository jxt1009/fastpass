import Foundation

// MARK: - CarDetailGaugeProgress
//
// Pure math helpers that turn the raw personal-best values from
// `CarDetailData` into a `[0, 1]` progress fraction for
// `CarDetailGauge`. Kept as a `case`-less `enum` (namespacing only —
// no instances) so the call sites read as
// `CarDetailGaugeProgress.topSpeedProgress(...)` and so the math is
// unit-testable without spinning up SwiftUI.
//
// Three statics:
// - `topSpeedProgress(speedMps:fullScaleMps:)` — linear fraction on
//   a 0..fullScaleMps scale, clamped to `[0, 1]`. Default 80 m/s
//   (≈ 179 mph) covers everything from a commuter car through a
//   supercar.
// - `zeroSixtyProgress(seconds:best:worst:)` — inverted linear
//   fraction on a `worst..best` scale, clamped to `[0, 1]`. Default
//   best=2 s, worst=8 s. Faster = higher progress.
// - `visualProgress(_:minimumVisible:)` — safety boost so a tiny
//   (including zero) progress still renders a visible sliver of arc.

enum CarDetailGaugeProgress {

    /// Maps a raw top speed in m/s to a `[0, 1]` progress fraction
    /// on a 0..`fullScaleMps` scale. The default `fullScaleMps = 80`
    /// corresponds to ≈ 179 mph.
    static func topSpeedProgress(speedMps: Double, fullScaleMps: Double = 80) -> Double {
        guard fullScaleMps > 0 else { return 0 }
        return min(max(speedMps / fullScaleMps, 0), 1)
    }

    /// Maps a raw 0-60 time in seconds to a `[0, 1]` progress
    /// fraction on a `best..worst` scale, inverted so faster = higher
    /// progress. A `nil` `seconds` (no 0-60 attempt yet) returns 0
    /// so the caller can still draw a `visualProgress` floor.
    static func zeroSixtyProgress(seconds: Double?, best: Double = 2, worst: Double = 8) -> Double {
        guard let seconds, worst > best else { return 0 }
        let fraction = (worst - seconds) / (worst - best)
        return min(max(fraction, 0), 1)
    }

    /// Boosts tiny progress values up to `minimumVisible` (default
    /// 0.12) so the arc always renders a visible sliver. Values
    /// already at or above the floor pass through unchanged. Both
    /// `value` and `minimumVisible` are clamped to `[0, 1]` so the
    /// result always stays in `[0, 1]`.
    static func visualProgress(_ value: Double, minimumVisible: Double = 0.12) -> Double {
        let clampedValue = min(max(value, 0), 1)
        let clampedFloor = min(max(minimumVisible, 0), 1)
        if clampedValue < clampedFloor { return clampedFloor }
        return clampedValue
    }
}
