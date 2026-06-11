import SwiftUI

// MARK: - FTGauge
//
// One parameterized gauge family replacing the four legacy variants
// (DashboardGauge, MetricGauge, CarDetailGauge, PublicCarDetailGauge).
//
// Styles:
//
//   .hero      — radial-arc donut with optional progress; "Set on" date
//                caption. Used for the per-car PB hero on the own-profile
//                car detail view.
//   .compact   — monospaced 28pt value + 3pt gradient underline +
//                uppercase label. Used on the per-drive detail view.
//   .statCell  — value + label (and optional unit) in a single row.
//                Used as the small cell inside stats grids and on the
//                public car detail view.
//
// All variants share corner radius 12. Color is a parameter; the
// background tints with 8% opacity and strokes with 25%.

struct FTGauge: View {
    enum Style: Equatable {
        case hero(progress: Double?, setOn: Date?)
        case compact
        case statCell(unit: String?)
    }

    let style: Style
    let label: String
    let value: String
    let color: Color

    @State private var displayedProgress: Double = 0

    var body: some View {
        switch style {
        case .hero(let progress, let setOn):
            heroBody(progress: progress, setOn: setOn)
        case .compact:
            compactBody
        case .statCell(let unit):
            statCellBody(unit: unit)
        }
    }

    // MARK: Hero

    @ViewBuilder
    private func heroBody(progress: Double?, setOn: Date?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon(for: label))
                    .font(.caption)
                    .foregroundColor(color)
                Text(label.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .tracking(0.5)
                    .foregroundColor(.secondary)
            }

            arc(progress: progress)
                .frame(height: 100)
                .padding(.top, 2)

            Text(value)
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            if let setOn {
                Text("Set on \(setOn.formatted(.dateTime.month(.abbreviated).day().year()))")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("No record yet")
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
        .onAppear {
            let target = progress ?? 0
            if displayedProgress == 0 && target > 0 {
                withAnimation(.easeInOut(duration: 0.6)) {
                    displayedProgress = target
                }
            } else {
                displayedProgress = target
            }
        }
        .onChange(of: progress) { _, newValue in
            withAnimation(.easeInOut(duration: 0.35)) {
                displayedProgress = newValue ?? 0
            }
        }
    }

    @ViewBuilder
    private func arc(progress: Double?) -> some View {
        if progress != nil {
            ZStack(alignment: .leading) {
                FTGaugeArc()
                    .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                FTGaugeArc()
                    .trim(from: 0, to: max(0.001, displayedProgress))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .animation(.easeInOut(duration: 0.6), value: displayedProgress)
            }
        } else {
            ZStack(alignment: .leading) {
                FTGaugeArc()
                    .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                FTGaugeArc()
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .opacity(0.85)
            }
        }
    }

    // MARK: Compact

    private var compactBody: some View {
        VStack(spacing: 8) {
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .monospaced))
                .foregroundColor(color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            Rectangle()
                .fill(LinearGradient(
                    colors: [.ftBlue, .ftAmber],
                    startPoint: .leading,
                    endPoint: .trailing
                ))
                .frame(width: 32, height: 3)
                .cornerRadius(1.5)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(.secondary)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 16)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.ftSectionBg, lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.ftCardBg)
        )
    }

    // MARK: StatCell

    @ViewBuilder
    private func statCellBody(unit: String?) -> some View {
        let isEmpty = value.isEmpty || value == "—"
        VStack(spacing: 4) {
            Text(isEmpty ? "—" : value)
                .font(.system(.title, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(isEmpty ? .secondary : color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            HStack(spacing: 2) {
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                if let unit, !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 9))
                        .foregroundColor(.secondary.opacity(0.6))
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .padding(.horizontal, 6)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(color.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label) \(isEmpty ? "no data" : value)\(unit.map { " \($0)" } ?? "")")
    }

    private func icon(for label: String) -> String {
        let t = label.lowercased()
        if t.contains("0-60") || t.contains("60") { return "timer" }
        if t.contains("speed") { return "speedometer" }
        return "gauge.with.needle"
    }
}

// MARK: - Arc shape

struct FTGaugeArc: Shape {
    var startAngle: Angle = .degrees(180)
    var endAngle: Angle = .degrees(360)

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2
        let start = Angle.degrees(startAngle.degrees - 90)
        let end = Angle.degrees(endAngle.degrees - 90)
        return Path { path in
            path.addArc(center: center, radius: radius,
                        startAngle: start, endAngle: end, clockwise: true)
        }
    }
}
