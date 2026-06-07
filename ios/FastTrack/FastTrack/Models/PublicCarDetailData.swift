import Foundation

// MARK: - Public car detail (pure value type)
//
// Aggregates the per-car data the public profile has on hand for a
// single car in someone else's garage: the `UserCar` itself plus the
// matching `CarStats` from the public `car_stats_data` blob. The view
// layer renders this struct directly; any unit-system conversion is
// done in the view using `AppSettings` so this stays free of side
// effects and trivial to test.
//
// `bestTopSpeed` and `bestZeroToSixty` are denormalised from `stats`
// for ergonomic access from the gauge layer. Both are `nil` whenever
// `stats` is nil (e.g. the server's `car_stats_data` blob didn't
// include this car id, or the user has no recorded drives on it).
//
// NOTE: a public-side sparkline is intentionally NOT modelled here.
// `CarStats` carries an all-time `bestTopSpeed` but not the per-drive
// maxSpeed samples the own-profile sparkline uses, and the only public
// endpoint for another user today is
// `GET /api/v1/users/:username/achievements` — there is no
// `/users/:username/drives`. The hero gauges + stats grid render
// honestly with what the blob provides. See PR body for the deferral
// rationale; revisit if/when a public drive list endpoint lands.

struct PublicCarDetailData {
    let car: UserCar
    let stats: CarStats?

    /// Best top speed in m/s. `nil` if no stats for this car.
    var bestTopSpeed: Double? {
        guard let stats else { return nil }
        guard stats.bestTopSpeed > 0 else { return nil }
        return stats.bestTopSpeed
    }

    /// Best 0-60 in seconds. `nil` if no stats or no recorded 0-60.
    var bestZeroToSixty: Double? {
        guard let stats, let time = stats.bestZeroToSixty, time > 0 else { return nil }
        return time
    }
}
