import SwiftUI

// MARK: - Public Car Detail View
//
// Read-only per-car detail for the public profile (the one another user
// sees when they tap a user from the leaderboard and drill into a car
// in the garage section). Pushed from `PublicProfileView`'s garage
// section. Mirrors the structure of the own-profile `CarDetailView`
// (Track E) but with three deliberate omissions, all driven by what
// the public `car_stats_data` blob can and can't supply:
//
//   1. No sparkline. The public blob carries each car's all-time
//      `bestTopSpeed` and `bestZeroToSixty`, but it does NOT carry
//      per-drive maxSpeed samples — the own-profile sparkline is
//      built from those. The only public endpoint for another user
//      today is `GET /api/v1/users/:username/achievements`; there is
//      no `/users/:username/drives`. Adding a public drive list is a
//      backend change tracked separately; revisit then.
//   2. No driving-style / category badge. That data is computed from
//      per-user-per-drive events the server doesn't expose publicly.
//   3. No PBs list. PBs are surfaced via the public profile's
//      Achievements section, not here — this view is about the car.
//
// The hero photo, year/make/model/trim header, two PB gauges, and
// stats grid (drives, total distance, top speed, category) are all
// drawn from the `UserCar` and `CarStats` the parent already has
// decoded.

struct PublicCarDetailView: View {
    let username: String
    let car: UserCar
    let stats: CarStats?
    /// Raw `car_stats_data` blob from the parent profile. Used only by
    /// the empty-state copy: when the blob is non-empty but the car id
    /// doesn't appear in it, we know stats exist for the user but
    /// haven't synced for this car yet (a different state from "no
    /// driving data recorded"). Optional so pre-existing call sites
    /// keep working; pass it through from the public profile.
    let carStatsData: String?

    @EnvironmentObject var settings: AppSettings

    init(
        username: String,
        car: UserCar,
        stats: CarStats?,
        carStatsData: String? = nil
    ) {
        self.username = username
        self.car = car
        self.stats = stats
        self.carStatsData = carStatsData
    }

    private var data: PublicCarDetailData {
        PublicCarDetailData.derive(car: car, stats: stats)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroSection
                pbgaugeRow
                statsGrid
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(Color.ftSurfaceBg.ignoresSafeArea())
        .navigationTitle(titleText)
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Title

    private var titleText: String {
        let make = car.make.isEmpty ? "Car" : car.make
        return "@\(username)'s \(make)"
    }

    // MARK: - Hero

    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            heroBackground
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: 4) {
                if !car.nickname.isEmpty {
                    Text("\"\(car.nickname)\"")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.white.opacity(0.85))
                }
                Text(car.displayString)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                    .lineLimit(2)
            }
            .padding(16)
        }
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }

    private var heroBackground: some View {
        CarPhotoView(
            car: car,
            url: car.hasPhoto ? (car.photoUrl.flatMap { $0.isEmpty ? nil : URL(string: $0) }) : nil,
            cornerRadius: 0
        )
    }

    // MARK: - PB gauges

    private var pbgaugeRow: some View {
        HStack(spacing: 12) {
            FTGauge(
                style: .statCell(unit: settings.speedUnit),
                label: "TOP SPEED",
                value: topSpeedDisplay ?? "—",
                color: .ftRed
            )
            FTGauge(
                style: .statCell(unit: "sec"),
                label: "BEST 0-60",
                value: zeroToSixtyDisplay ?? "—",
                color: .ftAmber
            )
        }
    }

    private var topSpeedDisplay: String? {
        guard let mps = data.bestTopSpeed else { return nil }
        return String(format: "%.0f", settings.speedValue(mps))
    }

    private var zeroToSixtyDisplay: String? {
        guard let seconds = data.bestZeroToSixty else { return nil }
        return String(format: "%.2f", seconds)
    }

    // MARK: - Stats grid

    @ViewBuilder
    private var statsGrid: some View {
        if let stats {
            InstrumentCard {
                VStack(spacing: 0) {
                    statRow(icon: "flag.fill", color: .green,
                            label: "Drives",
                            value: "\(stats.totalDrives)")
                    Divider().padding(.vertical, 8)
                    statRow(icon: "map.fill", color: .ftBlue,
                            label: "Total Distance",
                            value: settings.distanceDisplay(stats.totalDistance))
                    Divider().padding(.vertical, 8)
                    // Use `data.bestTopSpeed` (the same Double? the gauges
                    // consume) so the `bestTopSpeed == 0` "no drives"
                    // sentinel renders as "—" instead of a misleading
                    // "0 mph" / "City Car".
                    statRow(icon: "speedometer", color: .red,
                            label: "Top Speed",
                            value: data.bestTopSpeed.map { settings.speedDisplay($0) } ?? "—")
                    Divider().padding(.vertical, 8)
                    statRow(icon: "tag.fill", color: .purple,
                            label: "Category",
                            value: data.bestTopSpeed == nil ? "—" : stats.performanceCategory)
                }
            }
        } else {
            ContentUnavailableView(
                "Stats not synced",
                systemImage: "chart.bar",
                description: Text(statsNotSyncedCopy)
            )
            .frame(maxWidth: .infinity)
        }
    }

    /// Copy for the empty state when the user has stats for other cars
    /// but none for this one. Distinguished from "no driving data at
    /// all" so users don't think their car was never driven.
    private var noDataCopy: String {
        "No driving data recorded for this car yet."
    }

    private var statsNotSyncedCopy: String {
        if PublicProfileStatsLookup.isSyncedBlob(carStatsData) {
            return "Stats haven't synced for this car yet."
        }
        return noDataCopy
    }

    private func statRow(icon: String, color: Color, label: String, value: String) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 24)
            Text(label)
                .foregroundStyle(.primary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
                .foregroundStyle(.secondary)
        }
        .font(.subheadline)
    }
}
