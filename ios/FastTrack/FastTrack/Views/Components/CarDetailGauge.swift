import SwiftUI

// MARK: - Car Detail Gauge
//
// A larger, radial-arc-styled gauge for the centerpiece PBs on the
// per-car detail view. Distinct from `MetricGauge` in
// `SharedComponents.swift` (which is a small horizontal stat cell used
// on the live recording screen). This one:
//
// - Renders the numeric value in a monospaced large font
// - Draws a thin colored arc as a decorative background
// - Surfaces an optional "Set on MMM d, yyyy" caption underneath
//
// The arc is a *decorative* element — we don't try to compute a
// progress fraction from the value. The visual goal is "showy", not
// "accurate". For accuracy, the underlying numeric value is always
// the source of truth.

struct CarDetailGauge: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    /// Optional "Set on …" caption shown under the numeric value.
    var setOn: Date? = nil
    /// Optional formatter for the date. Defaults to a tasteful
    /// "MMM d, yyyy" via `Date.FormatStyle`.
    var dateFormat: Date.FormatStyle = .dateTime.month(.abbreviated).day().year()

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon(for: title))
                    .font(.caption)
                    .foregroundColor(color)
                Text(title.uppercased())
                    .font(.caption2)
                    .fontWeight(.semibold)
                    .tracking(0.5)
                    .foregroundColor(.secondary)
            }

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 32, weight: .bold, design: .monospaced))
                    .foregroundColor(color)
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.subheadline)
                        .fontWeight(.semibold)
                        .foregroundColor(color.opacity(0.75))
                }
            }

            ZStack(alignment: .leading) {
                GaugeArc()
                    .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                GaugeArc()
                    .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .opacity(0.85)
            }
            .frame(height: 16)
            .padding(.top, 2)

            if let setOn {
                Text("Set on \(setOn.formatted(dateFormat))")
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
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
    }

    private func icon(for title: String) -> String {
        let t = title.lowercased()
        if t.contains("0-60") || t.contains("60") { return "timer" }
        if t.contains("speed") { return "speedometer" }
        return "gauge.with.needle"
    }
}
