import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject var driveManager: DriveManager
    @EnvironmentObject var settings: AppSettings
    @StateObject private var profileManager = ProfileManager.shared
    @State private var selectedTimeFrame: TimeFrame = .month
    @State private var selectedMetric: AnalyticsMetric = .speed
    @State private var showingDetailSheet = false
    @State private var selectedDrive: Drive?
    @State private var selectedCarId: String? = nil

    private var garage: [UserCar] { profileManager.profile?.garage ?? [] }

    private var filteredDrives: [Drive] {
        let cutoffDate = Calendar.current.date(byAdding: selectedTimeFrame.dateComponent, value: -selectedTimeFrame.value, to: Date()) ?? Date()
        let byTime = driveManager.drives.filter { $0.startTime >= cutoffDate }
        guard let carId = selectedCarId else { return byTime }
        return byTime.filter { $0.carId == carId }
    }

    /// Drives from the prior equivalent period, used for the period-comparison card.
    private var prevPeriodDrives: [Drive] {
        let now = Date()
        let periodEnd = Calendar.current.date(byAdding: selectedTimeFrame.dateComponent, value: -selectedTimeFrame.value, to: now) ?? now
        let periodStart = Calendar.current.date(byAdding: selectedTimeFrame.dateComponent, value: -selectedTimeFrame.value, to: periodEnd) ?? periodEnd
        let byTime = driveManager.drives.filter { $0.startTime >= periodStart && $0.startTime < periodEnd }
        guard let carId = selectedCarId else { return byTime }
        return byTime.filter { $0.carId == carId }
    }

    private var analyticsData: AnalyticsData {
        AnalyticsData(drives: filteredDrives)
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                if driveManager.isLoadingDrives {
                    analyticsSkeleton
                } else {
                    VStack(spacing: 20) {
                        // Time Frame Selector
                        timeFramePicker

                        // Car Filter (only when 2+ cars in garage)
                        if garage.count >= 2 {
                            carFilterRow
                        }

                        // Performance Overview Cards
                        performanceOverview

                        // Main Chart
                        chartSection

                        // Performance Breakdown
                        performanceBreakdown

                        // Recent Best Performances
                        recentBests
                    }
                    .padding()
                    .transition(.opacity.animation(.easeInOut(duration: 0.3)))
                }
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.large)
        }
        // Ensure a fetch is in-flight whenever this tab is visible. SwiftUI may not
        // propagate @EnvironmentObject changes to non-active tabs, so we kick off our
        // own fetch when the view first appears rather than relying solely on the
        // TabView-level startPolling() call.
        .onAppear { driveManager.fetchDrives() }
        .sheet(item: $selectedDrive) { drive in
            DrivePerformanceDetailView(drive: drive)
        }
    }

    // MARK: - Loading skeleton

    private var analyticsSkeleton: some View {
        VStack(spacing: 20) {
            // Time frame picker placeholder
            SkeletonBlock(height: 36, cornerRadius: 10)

            // Overview cards row
            HStack(spacing: 12) {
                ForEach(0..<3, id: \.self) { _ in StatCardSkeleton() }
            }

            // Chart placeholder
            VStack(alignment: .leading, spacing: 12) {
                SkeletonBlock(width: 140, height: 16)
                SkeletonBlock(height: 180, cornerRadius: 12)
            }

            // Breakdown rows
            VStack(alignment: .leading, spacing: 12) {
                SkeletonBlock(width: 180, height: 16)
                ForEach(0..<4, id: \.self) { _ in
                    HStack {
                        SkeletonBlock(width: 100, height: 14)
                        Spacer()
                        SkeletonBlock(width: 60, height: 18)
                    }
                }
            }
        }
        .padding()
    }
    
    // MARK: - Time Frame Picker
    
    private var timeFramePicker: some View {
        Picker("Time Frame", selection: $selectedTimeFrame) {
            ForEach(TimeFrame.allCases, id: \.self) { frame in
                Text(frame.displayName).tag(frame)
            }
        }
        .pickerStyle(SegmentedPickerStyle())
    }
    
    // MARK: - Car Filter

    private var carFilterRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                AnalyticsCarChip(
                    title: "All Cars",
                    isSelected: selectedCarId == nil,
                    color: .blue
                ) {
                    selectedCarId = nil
                }
                ForEach(garage) { car in
                    AnalyticsCarChip(
                        title: car.shortDisplay,
                        isSelected: selectedCarId == car.id,
                        color: .blue
                    ) {
                        selectedCarId = selectedCarId == car.id ? nil : car.id
                    }
                }
            }
            .padding(.horizontal, 4)
        }
    }

    // MARK: - Performance Overview
    
    private var performanceOverview: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
            periodComparisonCard

            AnalyticsCard(
                title: "Total Drives",
                value: "\(filteredDrives.count)",
                icon: "car.fill",
                iconColor: .blue,
                trend: nil
            )
            
            AnalyticsCard(
                title: "Total Distance",
                value: settings.distanceDisplay(analyticsData.totalDistance, decimals: 0),
                icon: "map.fill",
                iconColor: .green,
                trend: nil
            )
            
            AnalyticsCard(
                title: "Avg Max Speed",
                value: settings.speedDisplay(analyticsData.avgMaxSpeed),
                icon: "speedometer",
                iconColor: .orange,
                trend: analyticsData.speedTrend
            )
            
            AnalyticsCard(
                title: "Driving Score",
                value: String(format: "%.0f", analyticsData.overallDrivingScore),
                icon: "star.fill",
                iconColor: .yellow,
                trend: analyticsData.scoreTrend,
                info: StatInfo.drivingScore
            )
        }
    }

    private var periodComparisonCard: some View {
        let currentAvg = AnalyticsData.avgMaxSpeed(for: filteredDrives)
        let prevAvg = AnalyticsData.avgMaxSpeed(for: prevPeriodDrives)

        let (valueText, trend): (String, TrendDirection?) = {
            guard let cur = currentAvg, let prev = prevAvg, prev > 0 else {
                return ("—", nil)
            }
            let delta = (cur - prev) * settings.speedFactor
            let sign = delta >= 0 ? "+" : ""
            let trend: TrendDirection = delta > 0.5 ? .up : (delta < -0.5 ? .down : .neutral)
            return (String(format: "%@%.1f %@", sign, delta, settings.speedUnit), trend)
        }()

        return AnalyticsCard(
            title: "vs Previous Period",
            value: valueText,
            icon: "arrow.up.arrow.down",
            iconColor: .purple,
            trend: trend
        )
    }
    
    // MARK: - Chart Section
    
    private var chartSection: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("Performance Trends")
                        .font(.headline)
                    Spacer()
                    
                    Picker("Metric", selection: $selectedMetric) {
                        ForEach(AnalyticsMetric.allCases, id: \.self) { metric in
                            Text(metric.displayName).tag(metric)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                }
                
                if #available(iOS 16.0, *), !filteredDrives.isEmpty {
                    Chart(filteredDrives) { drive in
                        LineMark(
                            x: .value("Date", drive.startTime),
                            y: .value(selectedMetric.displayName, selectedMetric.getValue(from: drive))
                        )
                        .foregroundStyle(selectedMetric.color)
                        .interpolationMethod(.catmullRom)
                    }
                    .frame(height: 200)
                    .chartYAxisLabel(selectedMetric.unit)
                    .chartXAxisLabel("Date")
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.ftCardBg)
                        .frame(height: 200)
                        .overlay(
                            VStack(spacing: 8) {
                                Image(systemName: "chart.line.uptrend.xyaxis")
                                    .font(.title2)
                                    .foregroundColor(.secondary)
                                Text("No data available")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                        )
                }
            }
        }
    }
    
    // MARK: - Performance Breakdown
    
    private var performanceBreakdown: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Performance Breakdown")
                .font(.headline)
            
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                PerformanceBreakdownCard(
                    title: "Best 0-60",
                    value: analyticsData.bestZeroToSixty.map { String(format: "%.1fs", $0) } ?? "N/A",
                    category: analyticsData.zeroToSixtyCategory,
                    icon: "bolt.fill",
                    color: .red
                )
                
                PerformanceBreakdownCard(
                    title: "Cornering",
                    value: String(format: "%.2fG", analyticsData.maxLateralG),
                    category: analyticsData.corneringGrade,
                    icon: "arrow.triangle.turn.up.right.circle.fill",
                    color: .purple
                )
                
                PerformanceBreakdownCard(
                    title: "Driving Style",
                    value: String(format: "%.0f%%", analyticsData.avgSmoothness),
                    category: analyticsData.drivingStyle,
                    icon: "waveform.path",
                    color: .cyan
                )
                
                PerformanceBreakdownCard(
                    title: "Consistency",
                    value: String(format: "%.0f%%", analyticsData.consistency),
                    category: analyticsData.consistencyGrade,
                    icon: "target",
                    color: .mint
                )
            }
        }
    }
    
    // MARK: - Recent Bests
    
    private var recentBests: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Top Performances")
                .font(.headline)
            
            if analyticsData.topSpeedDrives.isEmpty {
                ContentUnavailableView(
                    "No Performance Data",
                    systemImage: "trophy",
                    description: Text("Complete more drives to see your best performances")
                )
                .frame(height: 120)
            } else {
                ForEach(analyticsData.topSpeedDrives.prefix(3), id: \.id) { drive in
                    Button {
                        selectedDrive = drive
                    } label: {
                        RecentBestCard(drive: drive)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
    }
}

// MARK: - Supporting Views

struct AnalyticsCard: View {
    let title: String
    let value: String
    let icon: String
    let iconColor: Color
    let trend: TrendDirection?
    var info: StatInfoEntry? = nil

    var body: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(iconColor)
                        .font(.title3)
                    Spacer()
                    if let trend = trend {
                        TrendIndicator(trend: trend)
                    }
                    if let info { StatInfoButton(entry: info) }
                }

                Text(value)
                    .font(.title2)
                    .fontWeight(.bold)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}

struct TrendIndicator: View {
    let trend: TrendDirection
    
    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: trend.icon)
                .font(.caption)
            Text(trend.label)
                .font(.caption2)
        }
        .foregroundColor(trend.color)
    }
}

struct PerformanceBreakdownCard: View {
    let title: String
    let value: String
    let category: String
    let icon: String
    let color: Color
    
    var body: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.title3)
                    Spacer()
                }
                
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                Text(category)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.2))
                    .foregroundColor(color)
                    .cornerRadius(4)
            }
        }
    }
}

struct RecentBestCard: View {
    let drive: Drive
    
    var body: some View {
        InstrumentCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "trophy.fill")
                            .foregroundColor(.yellow)
                        Text("Top Speed")
                            .font(.subheadline)
                            .fontWeight(.medium)
                        Spacer()
                        Text(AppSettings.shared.speedDisplay(drive.maxSpeed))
                            .font(.headline)
                            .fontWeight(.bold)
                    }
                    
                    Text(drive.startTime.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if !drive.carDisplayString.isEmpty {
                        Text(drive.carDisplayString)
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
                Spacer()
                
                Image(systemName: "chevron.right")
                    .foregroundColor(.secondary)
                    .font(.caption)
            }
        }
    }
}

private struct AnalyticsCarChip: View {
    let title: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .white : color)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(isSelected ? color : Color(.systemGray6))
                .cornerRadius(20)
        }
    }
}
