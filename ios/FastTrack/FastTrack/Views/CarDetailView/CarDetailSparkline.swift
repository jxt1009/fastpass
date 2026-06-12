import SwiftUI
import Charts

// MARK: - CarDetailSparkline

struct CarDetailSparkline: View {
    let data: CarDetailData?
    let settings: AppSettings

    var body: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 8) {
                header
                chart
            }
        }
    }

    private var header: some View {
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
    private var chart: some View {
        if (data?.sparklinePoints.count ?? 0) > 1 {
            if #available(iOS 16.0, *) {
                chartBody
            } else {
                emptyState
            }
        } else {
            emptyState
        }
    }

    @ViewBuilder
    private var chartBody: some View {
        if #available(iOS 16.0, *) {
            Chart {
                ForEach(Array((data?.sparklinePoints ?? []).enumerated()), id: \.offset) { item in
                    lineMark(index: item.offset, speed: item.element)
                }
                if let pbIndex = data?.pbSparklineIndex {
                    pbPointMark(index: pbIndex)
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
    private func lineMark(index: Int, speed: Double) -> some ChartContent {
        LineMark(
            x: .value("Drive", index),
            y: .value("Max Speed", settings.speedValue(speed)),
            series: .value("Series", "speed")
        )
        .foregroundStyle(Color.ftBlue)
        .interpolationMethod(.monotone)
    }

    @available(iOS 16.0, *)
    private func pbPointMark(index: Int) -> some ChartContent {
        let speed = data?.sparklinePoints[index] ?? 0
        return PointMark(
            x: .value("Drive", index),
            y: .value("Max Speed", settings.speedValue(speed))
        )
        .foregroundStyle(Color.ftRed)
        .symbolSize(120)
        .annotation(position: .top) {
            Text("PB")
                .font(.caption2)
                .fontWeight(.bold)
                .foregroundColor(.red)
        }
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No trend data",
            systemImage: "chart.line.uptrend.xyaxis",
            description: Text("Record more drives to see the trend")
        )
        .frame(height: 120)
    }
}
