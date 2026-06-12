import SwiftUI
import Charts

// MARK: - CarDetailStatsGrid

struct CarDetailStatsGrid: View {
    let data: CarDetailData?
    let settings: AppSettings
    let car: UserCar?
    let drives: [Drive]

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

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            performanceBreakdown
            periodComparison
            trendSparklines
        }
    }

    // MARK: - Performance

    private var performanceBreakdown: some View {
        VStack(alignment: .leading, spacing: 15) {
            Text("Performance")
                .font(.headline)

            StatsGrid(spacing: 10) {
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
            }
        }
    }

    // MARK: - Period Comparison

    private var periodComparison: some View {
        let currentAvg: Double? = {
            guard let carId = car?.id else { return nil }
            let now = Date()
            let lastMonthStart = Calendar.current.date(byAdding: .month, value: -1, to: now) ?? now
            let periodDrives = drives.filter { $0.carId == carId && $0.startTime >= lastMonthStart }
            guard !periodDrives.isEmpty else { return nil }
            return periodDrives.reduce(0.0) { $0 + $1.maxSpeed } / Double(periodDrives.count)
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

    // MARK: - Trends

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
}
