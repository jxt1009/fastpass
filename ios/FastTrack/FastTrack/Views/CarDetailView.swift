import SwiftUI
import Charts

// MARK: - CarDetailView
//
// Pushed from `GarageView` (or a future public profile deep link).
// Showy per-car mini-profile with: hero photo, two large PB gauges
// (Top Speed, Best 0-60), a sparkline of this car's `maxSpeed` per
// drive, a driving-style badge, a stats grid, a per-car PBs list of
// achievements whose source drive belongs to this car, and a
// one-shot confetti animation when a PB is newer than 7 days.
//
// Data is assembled once via `CarDetailData.derive(...)` so the view
// body stays a thin renderer.

struct CarDetailView: View {
    let car: UserCar

    @StateObject private var profileManager = ProfileManager.shared
    @StateObject private var carStatsManager = CarStatsManager.shared
    @StateObject private var achievementManager = AchievementManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject var driveManager: DriveManager
    @State private var zoomedPhoto: AvatarZoomTarget?
    @State private var showConfetti = false
    @State private var confettiTask: Task<Void, Never>?
    /// Guards the one-shot confetti so it doesn't replay on every
    /// `onChange` refresh while the user remains on the view. Reset in
    /// `handleAppear` so navigating away and back re-arms the trigger.
    @State private var hasPlayedConfetti = false

    /// Snapshot of the data the view is rendering. Rebuilt whenever
    /// the source data changes. The view re-evaluates the closure on
    /// every body invocation; the `@State` keeps the *displayed*
    /// snapshot stable across body re-renders that don't actually
    /// change the inputs.
    @State private var data: CarDetailData = CarDetailData(
        car: UserCar(make: "", model: ""),
        stats: nil,
        sparklinePoints: [],
        pbSparklineIndex: nil,
        bestTopSpeed: nil,
        bestZeroToSixty: nil,
        topSpeedPBDate: nil,
        zeroSixtyPBDate: nil,
        drivingStyle: .unknown,
        achievementPBs: [],
        confettiEligible: false
    )

    private var currentData: CarDetailData {
        CarDetailData.derive(
            car: car,
            drives: driveManager.drives,
            carStats: carStatsManager.getStats(for: car.id),
            achievements: achievementManager.achievements,
            now: Date()
        )
    }

    var body: some View {
        content
            .background(Color.ftSurfaceBg.ignoresSafeArea())
            .navigationTitle(car.nickname.isEmpty ? car.shortDisplay : car.nickname)
            .navigationBarTitleDisplayMode(.inline)
            .fullScreenCover(item: $zoomedPhoto, content: photoZoomCover)
            .overlay(alignment: .top, content: confettiOverlay)
            .modifier(LifecycleModifier(
                onAppear: handleAppear,
                onDisappear: handleDisappear,
                driveCount: driveManager.drives.count,
                carStatsCount: carStatsManager.carStats.count,
                achievementCount: achievementManager.achievements.count,
                onChangeRefresh: refresh
            ))
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                pbGauges
                sparklineSection
                drivingStyleRow
                statsGrid
                perCarAchievementsSection
                Spacer(minLength: 16)
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    private func handleAppear() {
        hasPlayedConfetti = false
        refresh()
        triggerConfettiIfEligible()
    }

    private func handleDisappear() {
        confettiTask?.cancel()
        confettiTask = nil
    }

    // MARK: - Hero

    @ViewBuilder
    private var hero: some View {
        ZStack(alignment: .bottomLeading) {
            photo
                .frame(maxWidth: .infinity)
                .frame(height: 260)
                .clipped()
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            LinearGradient(
                colors: [.clear, .black.opacity(0.65)],
                startPoint: .center,
                endPoint: .bottom
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .frame(height: 260)
            .allowsHitTesting(false)

            VStack(alignment: .leading, spacing: 4) {
                if !car.nickname.isEmpty {
                    Text(car.nickname)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .lineLimit(1)
                }
                Text(car.displayString)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.white.opacity(0.9))
                    .lineLimit(1)
            }
            .padding(16)
        }
        .contentShape(Rectangle())
        .onTapGesture { presentPhotoZoom() }
    }

    private var photo: some View {
        CarPhotoView(
            car: car,
            url: car.photoUrl.flatMap { $0.isEmpty ? nil : URL(string: $0) },
            cornerRadius: 0
        )
    }

    // MARK: - PB gauges

    @ViewBuilder
    private var pbGauges: some View {
        HStack(spacing: 12) {
            CarDetailGauge(
                title: "Top Speed",
                value: topSpeedDisplay,
                unit: settings.speedUnit,
                color: SpeedColor.color(for: data.bestTopSpeed ?? 0),
                setOn: data.topSpeedPBDate
            )
            CarDetailGauge(
                title: "Best 0-60",
                value: zeroSixtyDisplay,
                unit: "sec",
                color: .ftAmber,
                setOn: data.zeroSixtyPBDate
            )
        }
    }

    // MARK: - Sparkline

    @ViewBuilder
    private var sparklineSection: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 8) {
                sparklineHeader
                sparklineChart
            }
        }
    }

    private var sparklineHeader: some View {
        HStack {
            Text("Max Speed Trend")
                .font(.headline)
            Spacer()
            if data.sparklinePoints.count > 1 {
                Text("Last \(data.sparklinePoints.count) drives")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sparklineChart: some View {
        if data.sparklinePoints.count > 1 {
            if #available(iOS 16.0, *) {
                sparklineChartBody
            } else {
                sparklineEmptyState
            }
        } else {
            sparklineEmptyState
        }
    }

    @ViewBuilder
    private var sparklineChartBody: some View {
        if #available(iOS 16.0, *) {
            Chart {
                ForEach(Array(data.sparklinePoints.enumerated()), id: \.offset) { item in
                    sparklineLineMark(index: item.offset, speed: item.element)
                }
                if let pbIndex = data.pbSparklineIndex {
                    sparklinePBPointMark(index: pbIndex)
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                    AxisGridLine()
                    AxisValueLabel()
                }
            }
            .frame(height: 160)
        }
    }

    @available(iOS 16.0, *)
    private func sparklineLineMark(index: Int, speed: Double) -> some ChartContent {
        LineMark(
            x: .value("Drive", index),
            y: .value("Max Speed", settings.speedValue(speed)),
            series: .value("Series", "speed")
        )
        .foregroundStyle(Color.ftBlue)
        .interpolationMethod(.monotone)
    }

    @available(iOS 16.0, *)
    private func sparklinePBPointMark(index: Int) -> some ChartContent {
        let speed = data.sparklinePoints[index]
        return PointMark(
            x: .value("Drive", index),
            y: .value("Max Speed", settings.speedValue(speed))
        )
        .foregroundStyle(Color.red)
        .symbolSize(120)
        .annotation(position: .top) {
            Text("PB")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.red)
        }
    }

    private var sparklineEmptyState: some View {
        VStack(spacing: 6) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.title2)
                .foregroundColor(.secondary)
            Text("Record more drives to see the trend")
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 120)
    }

    // MARK: - Driving style

    @ViewBuilder
    private var drivingStyleRow: some View {
        InstrumentCard {
            HStack(alignment: .center, spacing: 12) {
                DrivingStyleBadge(style: data.drivingStyle)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Driving Style")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(data.drivingStyle.explanation)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(.primary)
                }
                Spacer()
            }
        }
    }

    // MARK: - Stats grid

    @ViewBuilder
    private var statsGrid: some View {
        if let stats = data.stats {
            CarStatsRow(stats: stats)
        } else {
            InstrumentCard {
                HStack(spacing: 12) {
                    Image(systemName: "chart.bar")
                        .foregroundColor(.secondary)
                    Text("No driving data yet")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    Spacer()
                }
            }
        }
    }

    // MARK: - Per-car PBs

    @ViewBuilder
    private var perCarAchievementsSection: some View {
        if !data.achievementPBs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Personal Bests")
                ForEach(data.achievementPBs) { achievement in
                    NavigationLink {
                        destination(for: achievement)
                    } label: {
                        perCarAchievementRow(achievement)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func destination(for achievement: Achievement) -> some View {
        switch RecentAchievementsStripLogic.resolveSourceDrive(
            for: achievement,
            in: driveManager.drives
        ) {
        case .local(let drive):
            DriveDetailView(drive: drive)
        case .remote(let driveId):
            RemoteDriveDetailLoader(driveId: driveId)
        case .none:
            AchievementsView()
        }
    }

    private func perCarAchievementRow(_ achievement: Achievement) -> some View {
        InstrumentCard {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: achievement.badgeIcon)
                    .font(.title3)
                    .foregroundColor(achievement.badgeColor)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 2) {
                    Text(achievement.title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                    Text(achievement.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    // MARK: - Display helpers

    private var topSpeedDisplay: String {
        guard let speed = data.bestTopSpeed, speed > 0 else { return "—" }
        return String(format: "%.0f", settings.speedValue(speed))
    }

    private var zeroSixtyDisplay: String {
        guard let time = data.bestZeroToSixty, time > 0 else { return "—" }
        return String(format: "%.2f", time)
    }

    @ViewBuilder
    private func confettiOverlay() -> some View {
        if showConfetti {
            ConfettiView()
                .frame(height: 600)
                .ignoresSafeArea(edges: .top)
        }
    }

    @ViewBuilder
    private func photoZoomCover(_ target: AvatarZoomTarget) -> some View {
        AvatarZoomView(url: target.url, image: target.image) {
            zoomedPhoto = nil
        }
    }

    private func presentPhotoZoom() {
        guard let urlString = car.photoUrl, !urlString.isEmpty,
              let url = URL(string: urlString) else { return }
        zoomedPhoto = AvatarZoomTarget(url: url)
    }

    // MARK: - Lifecycle

    private func refresh() {
        data = currentData
    }

    /// One-shot confetti: schedule it if the freshly-derived data says
    /// the user just hit a PB in the last week. We always cancel the
    /// in-flight task on disappear so navigating away and back doesn't
    /// stack up multiple timers.
    private func triggerConfettiIfEligible() {
        confettiTask?.cancel()
        guard data.confettiEligible else { return }
        showConfetti = true
        confettiTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if Task.isCancelled { return }
            showConfetti = false
            confettiTask = nil
        }
    }
}

// MARK: - Lifecycle modifier
//
// SwiftUI's type checker chokes on long modifier chains when they mix
// multiple `.onChange(of:_:)` overloads (iOS 17 / iOS 18) and an
// `@EnvironmentObject` payload. The classic escape hatch is to move
// the lifecycle modifiers into a dedicated `ViewModifier` whose
// `body(content:)` is a single, narrow expression. That keeps the
// outer `body` shallow and lets the compiler resolve each `.onChange`
// unambiguously.

private struct LifecycleModifier: ViewModifier {
    let onAppear: () -> Void
    let onDisappear: () -> Void
    let driveCount: Int
    let carStatsCount: Int
    let achievementCount: Int
    let onChangeRefresh: () -> Void

    func body(content: Content) -> some View {
        content
            .onAppear(perform: onAppear)
            .onDisappear(perform: onDisappear)
            .onChange(of: driveCount) { _, _ in onChangeRefresh() }
            .onChange(of: carStatsCount) { _, _ in onChangeRefresh() }
            .onChange(of: achievementCount) { _, _ in onChangeRefresh() }
    }
}
