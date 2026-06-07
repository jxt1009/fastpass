import SwiftUI

// MARK: - Public Garage Card
//
// Read-only variant of `CarGarageCard` for the public profile garage
// section. Renders a per-car photo thumbnail, year/make/model/trim, the
// nickname (in quotes, when set), and a compact short-stats line drawn
// from the matching `CarStats` if one is present. The whole card is
// tappable; per the redesign, the per-car detail view is a follow-up, so
// for now we just no-op on tap.

struct PublicGarageCard: View {
    let car: UserCar
    let stats: CarStats?

    var body: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    CarPhotoThumbnail(photoURL: car.photoUrl, size: 80)
                    VStack(alignment: .leading, spacing: 4) {
                        // Nickname (in quotes, when present) is the headline.
                        if !car.nickname.isEmpty {
                            Text("\"\(car.nickname)\"")
                                .font(.headline)
                                .fontWeight(.semibold)
                                .foregroundColor(.primary)
                        }
                        Text(car.displayString)
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    Spacer(minLength: 0)
                }

                if let line = GarageCardShortStats.formattedLine(
                    for: stats,
                    unitSystem: AppSettings.shared.unitSystem
                ) {
                    Text(line)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }
}
