import SwiftUI

// MARK: - Public Garage Card
//
// Read-only variant of `CarGarageCard` for the public profile garage
// section. Renders a per-car photo thumbnail, year/make/model/trim, the
// nickname (in quotes, when set), and a compact short-stats line drawn
// from the matching `CarStats` if one is present.
//
// The card is a pure content view — it does NOT own a `Button` or any
// tap gesture. The parent (`PublicProfileView`'s garage section) wraps
// each card in a `NavigationLink` with `.buttonStyle(.plain)`, which
// suppresses the system disclosure indicator and lets this view's
// trailing chevron hint serve as the "tap to view" affordance without
// doubling up. (We learned this lesson from the own-profile card — the
// card and the system chevron on top of each other look noisy.)

struct PublicGarageCard: View {
    let car: UserCar
    let stats: CarStats?

    @ObservedObject private var settings = AppSettings.shared

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
                    // Trailing chevron hint — "tap to view". The parent
                    // wraps this card in a NavigationLink with
                    // .buttonStyle(.plain), so the system disclosure
                    // indicator is suppressed and this is the only
                    // chevron the user sees.
                    Image(systemName: "chevron.right")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .accessibilityLabel("View car details")
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
