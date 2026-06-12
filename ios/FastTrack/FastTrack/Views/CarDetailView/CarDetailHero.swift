import SwiftUI

// MARK: - CarDetailHero

struct CarDetailHero: View {
    let car: UserCar?
    let data: CarDetailData?
    let settings: AppSettings
    let onTapPhoto: () -> Void
    let onTapEditPhoto: () -> Void
    let onTapStyleGuide: () -> Void

    private var topSpeedDisplay: String {
        guard let speed = data?.bestTopSpeed, speed > 0 else { return "—" }
        return String(format: "%.0f", settings.speedValue(speed))
    }

    private var zeroSixtyDisplay: String {
        guard let time = data?.bestZeroToSixty, time > 0 else { return "—" }
        return String(format: "%.2f", time)
    }

    private var totalDrivesCount: Int {
        if let count = data?.stats?.totalDrives { return count }
        return 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            heroSection
            pbGauges
            topSummaryRow
        }
    }

    @ViewBuilder
    private var heroSection: some View {
        ZStack(alignment: .bottomLeading) {
            photo
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))

            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.xxl, style: .continuous))
            .frame(height: 260)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                if let nickname = car?.nickname, !nickname.isEmpty {
                    Text(nickname)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Text(car?.displayString ?? "")
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(16)

            heroPhotoEditButton
        }
        .contentShape(Rectangle())
        .onTapGesture { onTapPhoto() }
    }

    private var heroPhotoEditButton: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                Button {
                    onTapEditPhoto()
                } label: {
                    Image(systemName: "pencil.circle.fill")
                        .font(FTFont.sectionCaption).minimumScaleFactor(0.6)
                        .foregroundColor(.white)
                        .padding(10)
                        .background(Circle().fill(Color.ftScrim))
                }
                .frame(width: 44, height: 44)
                .accessibilityLabel("Edit car photo")
            }
        }
        .padding(8)
    }

    @ViewBuilder
    private var photo: some View {
        if let car {
            CarPhotoView(
                car: car,
                url: car.photoUrl.flatMap { $0.isEmpty ? nil : URL(string: $0) },
                cornerRadius: 0
            )
        }
    }

    @ViewBuilder
    private var pbGauges: some View {
        HStack(spacing: 12) {
            FTGauge(
                style: .hero(
                    progress: data.map { d in
                        let raw = d.bestTopSpeed.map { CarDetailGaugeProgress.topSpeedProgress(speedMps: $0) } ?? 0
                        return CarDetailGaugeProgress.visualProgress(raw)
                    },
                    setOn: data?.topSpeedPBDate
                ),
                label: "Top Speed",
                value: "\(topSpeedDisplay) \(settings.speedUnit)",
                color: SpeedColor.color(for: data?.bestTopSpeed ?? 0)
            )
            FTGauge(
                style: .hero(
                    progress: data.map { d in
                        CarDetailGaugeProgress.visualProgress(
                            CarDetailGaugeProgress.zeroSixtyProgress(seconds: d.bestZeroToSixty)
                        )
                    },
                    setOn: data?.zeroSixtyPBDate
                ),
                label: "Best 0-60",
                value: "\(zeroSixtyDisplay) sec",
                color: .ftAmber
            )
        }
    }

    private var topSummaryRow: some View {
        InstrumentCard {
            HStack(spacing: 12) {
                DrivingStyleBadge(style: data?.drivingStyle ?? .unknown)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Total Drives")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text("\(totalDrivesCount)")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                Spacer()
                Button {
                    onTapStyleGuide()
                } label: {
                    Label("Style Guide", systemImage: "info.circle")
                        .font(.caption.weight(.semibold))
                }
                .buttonStyle(.plain)
                .foregroundColor(.ftBlue)
            }
        }
    }
}
