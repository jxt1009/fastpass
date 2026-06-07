import Foundation

// MARK: - PublicCarDetailData.derive
//
// Pure factory kept in its own file so the struct stays value-only
// and tests can target `derive(...)` without pulling in any view or
// settings dependencies. Adding a new field to `PublicCarDetailData`
// is a one-line change here; the view layer is the only consumer and
// it uses the struct's computed properties.

extension PublicCarDetailData {

    /// Builds the per-car detail bundle from the public-side inputs.
    /// `car` always passes through; `stats` is the matching entry from
    /// the server's `car_stats_data` blob, or `nil` if the blob is
    /// missing/malformed or doesn't include this car id.
    static func derive(car: UserCar, stats: CarStats?) -> PublicCarDetailData {
        PublicCarDetailData(car: car, stats: stats)
    }
}
