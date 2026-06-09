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
    let carId: String

    @StateObject private var profileManager = ProfileManager.shared
    @StateObject private var carStatsManager = CarStatsManager.shared
    @StateObject private var achievementManager = AchievementManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject var driveManager: DriveManager

    private var car: UserCar? {
        profileManager.profile?.garage.first(where: { $0.id == carId })
    }

    private var isActiveCar: Bool {
        profileManager.profile?.selectedCarId == carId
    }

    @State private var zoomedPhoto: AvatarZoomTarget?
    @State private var showConfetti = false
    @State private var confettiTask: Task<Void, Never>?
    @State private var showingEditCar = false
    /// Guards the one-shot confetti so it doesn't replay on every
    /// `onChange` refresh while the user remains on the view. Reset in
    /// `handleAppear` so navigating away and back re-arms the trigger.
    @State private var hasPlayedConfetti = false

    /// Snapshot of the data the view is rendering. Rebuilt whenever
    /// the source data changes. Nil until the first `refresh()` call
    /// or when the car has been removed from the garage.
    @State private var data: CarDetailData?

    private var currentData: CarDetailData? {
        guard let car else { return nil }
        return CarDetailData.derive(
            car: car,
            drives: driveManager.drives,
            carStats: carStatsManager.getStats(for: car.id),
            achievements: achievementManager.achievements,
            now: Date()
        )
    }

    var body: some View {
        Group {
            if car != nil {
                content
                    .fullScreenCover(item: $zoomedPhoto, content: photoZoomCover)
                    .sheet(isPresented: $showingEditCar) {
                        EditCarView(carId: carId)
                    }
                    .overlay(alignment: .top, content: confettiOverlay)
                    .modifier(LifecycleModifier(
                        onAppear: handleAppear,
                        onDisappear: handleDisappear,
                        driveCount: driveManager.drives.count,
                        carStatsCount: carStatsManager.carStats.count,
                        achievementCount: achievementManager.achievements.count,
                        onChangeRefresh: refresh
                    ))
            } else {
                ContentUnavailableView(
                    "Car Removed",
                    systemImage: "car.fill",
                    description: Text("This car is no longer in your garage.")
                )
            }
        }
        .background(Color.ftSurfaceBg.ignoresSafeArea())
        .navigationTitle(car.map { $0.nickname.isEmpty ? $0.shortDisplay : $0.nickname } ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                HStack(spacing: 12) {
                    if car != nil {
                        Button {
                            showingEditCar = true
                        } label: {
                            Image(systemName: "pencil")
                                .foregroundColor(.ftBlue)
                        }
                    }
                    if isActiveCar {
                        Text("Active")
                            .font(.caption)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.ftBlue))
                    } else if car != nil {
                        Button("Set Active") {
                            setActiveCar()
                        }
                        .foregroundColor(.ftBlue)
                    }
                }
            }
        }
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                hero
                pbGauges
                performanceBreakdown
                periodComparison
                trendSparklines
                sparklineSection
                drivingStyleRow
                statsGrid
                perCarAchievementsSection
                recentDrivesSection
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

    private func setActiveCar() {
        guard var profile = profileManager.profile else { return }
        profile.selectCar(id: carId)
        profileManager.saveProfile(profile)
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
        }
        .contentShape(Rectangle())
        .onTapGesture { presentPhotoZoom() }
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

    // MARK: - PB gauges

    @ViewBuilder
    private var pbGauges: some View {
        HStack(spacing: 12) {
            CarDetailGauge(
                title: "Top Speed",
                value: topSpeedDisplay,
                unit: settings.speedUnit,
                color: SpeedColor.color(for: data?.bestTopSpeed ?? 0),
                setOn: data?.topSpeedPBDate
            )
            CarDetailGauge(
                title: "Best 0-60",
                value: zeroSixtyDisplay,
                unit: "sec",
                color: .ftAmber,
                setOn: data?.zeroSixtyPBDate
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
            if (data?.sparklinePoints.count ?? 0) > 1 {
                Text("Last \(data?.sparklinePoints.count ?? 0) drives")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @ViewBuilder
    private var sparklineChart: some View {
        if (data?.sparklinePoints.count ?? 0) > 1 {
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
                ForEach(Array((data?.sparklinePoints ?? []).enumerated()), id: \.offset) { item in
                    sparklineLineMark(index: item.offset, speed: item.element)
                }
                if let pbIndex = data?.pbSparklineIndex {
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
        let speed = data?.sparklinePoints[index] ?? 0
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
                DrivingStyleBadge(style: data?.drivingStyle ?? .unknown)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Driving Style")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Text(data?.drivingStyle.explanation ?? DrivingStyle.unknown.explanation)
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
        if let stats = data?.stats {
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
        if let pbs = data?.achievementPBs, !pbs.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                SectionHeader(title: "Personal Bests")
                ForEach(pbs) { achievement in
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

    // MARK: - Performance Breakdown

    private var zeroToSixtyCategory: String {
        guard let time = data?.bestZeroToSixty else { return "N/A" }
        switch time {
        case 0..<3.0: return "Hypercar"
        case 3.0..<4.0: return "Supercar"
        case 4.0..<6.0: return "Sports Car"
        default: return "Quick"
        }
    }

    private var corneringCategory: String {
        switch data?.peakLateralG ?? 0 {
        case 0.8...: return "Race Driver"
        case 0.6..<0.8: return "Enthusiast"
        default: return "Spirited"
        }
    }

    private var consistencyCategory: String {
        switch data?.consistencyScore ?? 0 {
        case 90...: return "Exceptional"
        case 80..<90: return "Excellent"
        case 70..<80: return "Good"
        default: return "Average"
        }
    }

    private var performanceBreakdown: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Performance")
                .font(.headline)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                PerformanceBreakdownCard(
                    title: "Best 0-60",
                    value: data?.bestZeroToSixty.map { String(format: "%.1fs", $0) } ?? "N/A",
                    category: zeroToSixtyCategory,
                    icon: "bolt.fill",
                    color: .red
                )
                PerformanceBreakdownCard(
                    title: "Cornering",
                    value: String(format: "%.2fG", data?.peakLateralG ?? 0),
                    category: corneringCategory,
                    icon: "arrow.triangle.turn.up.right.circle.fill",
                    color: .purple
                )
                PerformanceBreakdownCard(
                    title: "Driving Style",
                    value: String(format: "%.0f%%", data?.smoothnessScore ?? 0),
                    category: data?.drivingStyle.title ?? DrivingStyle.unknown.title,
                    icon: "waveform.path",
                    color: .cyan
                )
                PerformanceBreakdownCard(
                    title: "Consistency",
                    value: String(format: "%.0f%%", data?.consistencyScore ?? 0),
                    category: consistencyCategory,
                    icon: "target",
                    color: .mint
                )
            }
        }
    }

    // MARK: - Period Comparison

    private enum TimePeriod {
        case lastMonth
        case previousMonth
    }

    private func drives(of carId: String, in period: TimePeriod) -> [Drive] {
        let now = Date()
        let start: Date
        switch period {
        case .lastMonth:
            start = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
        case .previousMonth:
            let lastMonthStart = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
            start = Calendar.current.date(byAdding: .month, value: -1, to: lastMonthStart) ?? lastMonthStart
            return driveManager.drives.filter { $0.carId == carId && $0.startTime >= start && $0.startTime < lastMonthStart }
        }
        return driveManager.drives.filter { $0.carId == carId && $0.startTime >= start }
    }

    private var periodComparison: some View {
        let currentAvg: Double? = {
            guard let carId = car?.id else { return nil }
            let drives = self.drives(of: carId, in: .lastMonth)
            guard !drives.isEmpty else { return nil }
            return drives.reduce(0.0) { $0 + $1.maxSpeed } / Double(drives.count)
        }()
        let prevAvg = data?.prevPeriodAvgMaxSpeed

        let (valueText, trend): (String, TrendDirection?) = {
            guard let cur = currentAvg, let prev = prevAvg, prev > 0 else {
                return ("—", nil)
            }
            let delta = (cur - prev) * settings.speedFactor
            let sign = delta >= 0 ? "+" : ""
            let t: TrendDirection = delta > 0.5 ? .up : (delta < -0.5 ? .down : .neutral)
            return (String(format: "%@%.1f %@", sign, delta, settings.speedUnit), t)
        }()

        return AnalyticsCard(
            title: "vs Last Month",
            value: valueText,
            icon: "arrow.up.arrow.down",
            iconColor: .purple,
            trend: trend,
            info: StatInfo.periodComparison
        )
    }

    // MARK: - Trend Sparklines

    private var trendSparklines: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Trends")
                .font(.headline)

            if #available(iOS 16.0, *) {
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 10) {
                    sparklineCard(
                        title: "Max Speed",
                        values: data?.sparklinePoints ?? [],
                        unit: settings.speedUnit,
                        formatValue: { String(format: "%.0f", settings.speedValue($0)) }
                    )
                    sparklineCard(
                        title: "Distance",
                        values: data?.distanceTrendPoints ?? [],
                        unit: settings.distanceUnit,
                        formatValue: { String(format: "%.1f", settings.distanceValue($0)) }
                    )
                    sparklineCard(
                        title: "Smoothness",
                        values: data?.smoothnessTrendPoints ?? [],
                        unit: "%",
                        formatValue: { String(format: "%.0f", $0) }
                    )
                }
            } else {
                Text("iOS 16+ required for trend charts")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }

    @available(iOS 16.0, *)
    private func sparklineCard(title: String, values: [Double], unit: String, formatValue: @escaping (Double) -> String) -> some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Spacer()
                    if let last = values.last, last > 0 {
                        Text(formatValue(last))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                }
                if values.count > 1 {
                    Chart {
                        ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                            LineMark(
                                x: .value("Drive", index),
                                y: .value(title, value)
                            )
                            .foregroundStyle(Color.ftBlue)
                            .interpolationMethod(.monotone)
                        }
                    }
                    .chartYAxis(.hidden)
                    .chartXAxis(.hidden)
                    .frame(height: 60)
                } else {
                    Text("Need more drives")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    // MARK: - Recent Drives

    @ViewBuilder
    private var recentDrivesSection: some View {
        let carRecentDrives = data?.recentDrives ?? []

        let topSpeedPBDriveId: Int? = {
            guard let carId = car?.id,
                  let drive = driveManager.drives.filter({ $0.carId == carId }).max(by: { $0.maxSpeed < $1.maxSpeed }),
                  drive.maxSpeed == data?.bestTopSpeed else { return nil }
            return drive.id
        }()

        let zeroSixtyPBDriveId: Int? = {
            guard let carId = car?.id,
                  let time = data?.bestZeroToSixty,
                  let drive = driveManager.drives.first(where: { $0.carId == carId && $0.best060Time == time }) else { return nil }
            return drive.id
        }()

        if !carRecentDrives.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                SectionHeader(title: "Recent Drives")

                ForEach(carRecentDrives) { drive in
                    NavigationLink {
                        DriveDetailView(drive: drive)
                    } label: {
                        GarageDriveRow(drive: drive)
                            .overlay(alignment: .topTrailing) {
                                if drive.id == zeroSixtyPBDriveId {
                                    pbPill(text: "PB 0-60", icon: "trophy.fill", bg: .yellow, fg: .black)
                                } else if drive.id == topSpeedPBDriveId {
                                    pbPill(text: "PB Speed", icon: "flame.fill", bg: .red, fg: .white)
                                }
                            }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func pbPill(text: String, icon: String, bg: Color, fg: Color) -> some View {
        HStack(spacing: 3) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .bold))
            Text(text)
                .font(.caption2.weight(.bold))
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(bg)
        .foregroundColor(fg)
        .clipShape(Capsule())
    }

    // MARK: - Display helpers

    private var topSpeedDisplay: String {
        guard let speed = data?.bestTopSpeed, speed > 0 else { return "—" }
        return String(format: "%.0f", settings.speedValue(speed))
    }

    private var zeroSixtyDisplay: String {
        guard let time = data?.bestZeroToSixty, time > 0 else { return "—" }
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
        guard let urlString = car?.photoUrl, !urlString.isEmpty,
              let url = URL(string: urlString) else { return }
        zoomedPhoto = AvatarZoomTarget(url: url)
    }

    // MARK: - Lifecycle

    private func refresh() {
        data = currentData  // currentData is CarDetailData? — nil when car removed
    }

    /// One-shot confetti: schedule it if the freshly-derived data says
    /// the user just hit a PB in the last week. We always cancel the
    /// in-flight task on disappear so navigating away and back doesn't
    /// stack up multiple timers.
    private func triggerConfettiIfEligible() {
        confettiTask?.cancel()
        guard data?.confettiEligible == true else { return }
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
