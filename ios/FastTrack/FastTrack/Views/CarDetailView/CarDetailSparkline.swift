import SwiftUI
import Charts

// MARK: - CarDetailSparkline

struct CarDetailSparkline: View {
    let data: CarDetailData?
    let settings: AppSettings

    @State private var selectedIndex: Int?

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
            if let idx = selectedIndex, let speed = data?.sparklinePoints[idx] {
                Text(String(format: "%.0f %@", settings.speedValue(speed), settings.speedUnit))
                    .font(.caption.monospacedDigit())
                    .fontWeight(.semibold)
                    .foregroundColor(.ftBlue)
            } else if (data?.sparklinePoints.count ?? 0) > 1 {
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
            let points = data?.sparklinePoints ?? []
            Chart {
                ForEach(Array(points.enumerated()), id: \.offset) { item in
                    lineMark(index: item.offset, speed: item.element)
                }
                if let pbIndex = data?.pbSparklineIndex {
                    pbPointMark(index: pbIndex)
                }
                if let idx = selectedIndex, idx < points.count {
                    RuleMark(x: .value("Selection", idx))
                        .foregroundStyle(Color.ftBlue.opacity(0.3))
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [4, 4]))
                    PointMark(
                        x: .value("Drive", idx),
                        y: .value("Max Speed", settings.speedValue(points[idx]))
                    )
                    .foregroundStyle(Color.ftBlue)
                    .symbolSize(80)
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
            .chartOverlay { proxy in
                GeometryReader { geometry in
                    Rectangle().fill(.clear).contentShape(Rectangle())
                        .gesture(
                            DragGesture(minimumDistance: 0)
                                .onChanged { value in
                                    let frame = geometry[proxy.plotAreaFrame]
                                    guard frame.width > 0, !points.isEmpty else { return }
                                    let ratio = (value.location.x - frame.minX) / frame.width
                                    let idx = max(0, min(points.count - 1, Int((ratio * Double(points.count - 1)).rounded())))
                                    if selectedIndex != idx {
                                        selectedIndex = idx
                                    }
                                }
                                .onEnded { _ in
                                    selectedIndex = nil
                                }
                        )
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
