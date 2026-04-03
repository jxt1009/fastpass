import SwiftUI
import Charts

struct AnalyticsView: View {
    @EnvironmentObject var driveManager: DriveManager
    @ObservedObject private var settings = AppSettings.shared
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
        NavigationView {
            ScrollView {
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
            }
            .navigationTitle("Analytics")
            .navigationBarTitleDisplayMode(.large)
        }
        .sheet(item: $selectedDrive) { drive in
            DrivePerformanceDetailView(drive: drive)
        }
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
                trend: analyticsData.speedTrend
            )
            
            AnalyticsCard(
                title: "Driving Score",
                value: String(format: "%.0f", analyticsData.overallDrivingScore),
                icon: "star.fill",
                iconColor: .yellow,
                trend: analyticsData.scoreTrend
            )
        }
    }
    
    // MARK: - Chart Section
    
    private var chartSection: some View {
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
                    .fill(Color(.systemGray6))
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
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
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
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.title3)
                Spacer()
                if let trend = trend {
                    TrendIndicator(trend: trend)
                }
            }
            
            Text(value)
                .font(.title2)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
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
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}

struct RecentBestCard: View {
    let drive: Drive
    
    var body: some View {
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
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }
}

// MARK: - Supporting Types

enum TimeFrame: CaseIterable {
    case week, month, quarter, year
    
    var displayName: String {
        switch self {
        case .week: return "Week"
        case .month: return "Month"
        case .quarter: return "3 Months"
        case .year: return "Year"
        }
    }
    
    var dateComponent: Calendar.Component {
        switch self {
        case .week: return .day
        case .month: return .month
        case .quarter: return .month
        case .year: return .year
        }
    }
    
    var value: Int {
        switch self {
        case .week: return 7
        case .month: return 1
        case .quarter: return 3
        case .year: return 1
        }
    }
}

enum AnalyticsMetric: CaseIterable {
    case speed, distance, smoothness, acceleration
    
    var displayName: String {
        switch self {
        case .speed: return "Max Speed"
        case .distance: return "Distance"
        case .smoothness: return "Smoothness"
        case .acceleration: return "Max Acceleration"
        }
    }
    
    var unit: String {
        let s = AppSettings.shared
        switch self {
        case .speed: return s.speedUnit
        case .distance: return s.distanceUnit
        case .smoothness: return "score"
        case .acceleration: return "G"
        }
    }
    
    var color: Color {
        switch self {
        case .speed: return .red
        case .distance: return .blue
        case .smoothness: return .green
        case .acceleration: return .orange
        }
    }
    
    func getValue(from drive: Drive) -> Double {
        let s = AppSettings.shared
        switch self {
        case .speed: return drive.maxSpeed * s.speedFactor
        case .distance: return drive.distance * s.distanceFactor
        case .smoothness: return 75
        case .acceleration: return 0.5
        }
    }
}

enum TrendDirection {
    case up, down, neutral
    
    var icon: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .neutral: return "minus"
        }
    }
    
    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .neutral: return .gray
        }
    }
    
    var label: String {
        switch self {
        case .up: return "Up"
        case .down: return "Down"
        case .neutral: return "Same"
        }
    }
}

// MARK: - Analytics Data Model

struct AnalyticsData {
    let drives: [Drive]
    
    var totalDistance: Double {
        drives.reduce(0) { $0 + $1.distance }
    }
    
    var avgMaxSpeed: Double {
        guard !drives.isEmpty else { return 0 }
        return drives.reduce(0) { $0 + $1.maxSpeed } / Double(drives.count)
    }
    
    var overallDrivingScore: Double {
        // Placeholder calculation - would use performance metrics
        return 78.5
    }
    
    var speedTrend: TrendDirection {
        guard drives.count >= 2 else { return .neutral }
        let recent = drives.prefix(drives.count / 2).map(\.maxSpeed)
        let older = drives.suffix(drives.count / 2).map(\.maxSpeed)
        
        let recentAvg = recent.reduce(0, +) / Double(recent.count)
        let olderAvg = older.reduce(0, +) / Double(older.count)
        
        if recentAvg > olderAvg * 1.05 { return .up }
        if recentAvg < olderAvg * 0.95 { return .down }
        return .neutral
    }
    
    var scoreTrend: TrendDirection {
        return .up // Placeholder
    }
    
    var bestZeroToSixty: Double? {
        // Would calculate from performance metrics
        return 5.8
    }
    
    var zeroToSixtyCategory: String {
        guard let time = bestZeroToSixty else { return "Unknown" }
        switch time {
        case 0..<3.0: return "Hypercar"
        case 3.0..<4.0: return "Supercar"
        case 4.0..<6.0: return "Sports Car"
        default: return "Quick"
        }
    }
    
    var maxLateralG: Double {
        return 0.65 // Placeholder
    }
    
    var corneringGrade: String {
        switch maxLateralG {
        case 0.8...: return "Race Driver"
        case 0.6..<0.8: return "Enthusiast"
        default: return "Spirited"
        }
    }
    
    var avgSmoothness: Double {
        return 82.3 // Placeholder
    }
    
    var drivingStyle: String {
        switch avgSmoothness {
        case 90...: return "Silk Smooth"
        case 80..<90: return "Very Smooth"
        case 70..<80: return "Smooth"
        default: return "Moderate"
        }
    }
    
    var consistency: Double {
        return 74.2 // Placeholder
    }
    
    var consistencyGrade: String {
        switch consistency {
        case 90...: return "Exceptional"
        case 80..<90: return "Excellent"
        case 70..<80: return "Good"
        default: return "Average"
        }
    }
    
    var recentBestDrives: [Drive] {
        drives.sorted { $0.maxSpeed > $1.maxSpeed }
    }
}

// MARK: - Drive Performance Detail View

struct DrivePerformanceDetailView: View {
    let drive: Drive
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Performance Summary
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Performance Summary")
                            .font(.headline)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            PerformanceStatCard(title: "Max Speed", value: AppSettings.shared.speedDisplay(drive.maxSpeed), icon: "speedometer")
                            PerformanceStatCard(title: "Avg Speed", value: AppSettings.shared.speedDisplay(drive.avgSpeed), icon: "gauge.medium")
                            PerformanceStatCard(title: "Distance", value: AppSettings.shared.distanceDisplay(drive.distance), icon: "map")
                            PerformanceStatCard(title: "Duration", value: formatDuration(drive.duration), icon: "clock")
                        }
                    }
                    
                    // Detailed Analysis
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Detailed Analysis")
                            .font(.headline)
                        
                        Text("Performance metrics will be calculated from GPS data...")
                            .foregroundColor(.secondary)
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(8)
                    }
                }
                .padding()
            }
            .navigationTitle("Performance Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

struct PerformanceStatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: icon)
                    .foregroundColor(.blue)
                Spacer()
            }
            
            Text(value)
                .font(.headline)
                .fontWeight(.bold)
            
            Text(title)
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding()
        .background(Color(.systemBackground))
        .cornerRadius(12)
    }
}