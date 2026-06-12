import SwiftUI

// MARK: - Public Garage Card
//
// Read-only variant of `CarGarageCard` for the public profile garage
// section. Renders a per-car photo thumbnail, year/make/model/trim, the
// nickname (in quotes, when set), and a compact short-stats line drawn
// from the matching `CarStats` if one is present.
//
// The card is a pure content view — it does NOT own a `Button` or any
// tap gesture, and it does NOT render its own chevron hint. The parent
// (`PublicProfileView`'s garage section) wraps each card in a
// `NavigationLink` inside a `List`; the system disclosure indicator is
// the consistent "tap to view" affordance across the row, matching
// the Stats / Followers / Following rows. Adding a card-local chevron
// on top of the system one produced a doubled-up affordance on iOS
// 17+ that we removed.

struct PublicGarageCard: View {
    let car: UserCar
    let stats: CarStats?

    @EnvironmentObject var settings: AppSettings

    var body: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 12) {
                    CarPhotoView(
                        car: car,
                        url: car.photoUrl.flatMap { $0.isEmpty ? nil : URL(string: $0) },
                        cornerRadius: 10,
                        size: 80
                    )
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

                if let line = shortStatsLine(for: stats) {
                    Text(line)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    /// Read the live unit system from the shared `AppSettings` (no
    /// mutation, no extra `AppSettings()` instance) and ask the
    /// formatter to build the short-stats line.
    private func shortStatsLine(for stats: CarStats?) -> String? {
        GarageCardShortStats.formattedLine(
            for: stats,
            speedUnit: settings.speedUnit,
            distanceUnit: settings.distanceUnit,
            speedFactor: settings.speedFactor,
            distanceFactor: settings.distanceFactor
        )
    }
}
