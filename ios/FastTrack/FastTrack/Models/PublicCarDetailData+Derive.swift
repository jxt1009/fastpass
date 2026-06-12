import Foundation

// MARK: - PublicCarDetailData.derive

extension PublicCarDetailData {

    static func derive(car: UserCar, stats: CarStats?) -> PublicCarDetailData {
        PublicCarDetailData(car: car, stats: stats)
    }
}
