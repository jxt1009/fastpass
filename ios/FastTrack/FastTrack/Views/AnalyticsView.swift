import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject var driveManager: DriveManager
    @EnvironmentObject var settings: AppSettings
    @State private var selectedTimeFrame: TimeFrame = .month
    @State private var selectedMetric: AnalyticsMetric = .speed
    @State private var showingDetailSheet = false
    @State private var selectedDrive: Drive?
    
    private var filteredDrives: [Drive] {
        let cutoffDate = Calendar.current.date(byAdding: selectedTimeFrame.dateComponent, value: -selectedTimeFrame.value, to: Date()) ?? Date()
        return driveManager.drives.filter { $0.startTime >= cutoffDate }
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
    
    // MARK: - Performance Overview
    
    private var performanceOverview: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
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
                trend: analyticsData.speedTrend,
                info: StatInfo.avgMaxSpeed
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
                    color: .red,
                    info: StatInfo.zeroToSixty
                )

                PerformanceBreakdownCard(
                    title: "Cornering",
                    value: String(format: "%.2fG", analyticsData.maxLateralG),
                    category: analyticsData.corneringGrade,
                    icon: "arrow.triangle.turn.up.right.circle.fill",
                    color: .purple,
                    info: StatInfo.cornering
                )

                PerformanceBreakdownCard(
                    title: "Driving Style",
                    value: String(format: "%.0f%%", analyticsData.avgSmoothness),
                    category: analyticsData.drivingStyle,
                    icon: "waveform.path",
                    color: .cyan,
                    info: StatInfo.smoothness
                )

                PerformanceBreakdownCard(
                    title: "Consistency",
                    value: String(format: "%.0f%%", analyticsData.consistency),
                    category: analyticsData.consistencyGrade,
                    icon: "target",
                    color: .mint,
                    info: StatInfo.consistency
                )
            }
        }
    }
    
    // MARK: - Recent Bests
    
    private var recentBests: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Recent Best Performances")
                .font(.headline)
            
            if analyticsData.recentBestDrives.isEmpty {
                ContentUnavailableView(
                    "No Performance Data",
                    systemImage: "trophy",
                    description: Text("Complete more drives to see your best performances")
                )
                .frame(height: 120)
            } else {
                ForEach(analyticsData.recentBestDrives.prefix(3), id: \.id) { drive in
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

struct RecentBestCard: View {
    let drive: Drive
    
    var body: some View {
        InstrumentCard {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Image(systemName: "trophy.fill")
                            .foregroundColor(.yellow)
                        Text("Best Max Speed")
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
