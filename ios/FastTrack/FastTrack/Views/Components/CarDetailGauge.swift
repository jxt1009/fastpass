import SwiftUI

// MARK: - Car Detail Gauge
//
// A larger, radial-arc-styled gauge for the centerpiece PBs on the
// per-car detail view. Distinct from `MetricGauge` in
// `SharedComponents.swift` (which is a small horizontal stat cell used
// on the live recording screen). This one:
//
// - Renders the numeric value in a monospaced large font
// - Draws a colored half-donut arc opening upward; when `progress`
//   is provided, the foreground arc is trimmed to that fraction
//   and animates via `.easeInOut(duration: 0.6)` on first appear
// - Surfaces an optional "Set on MMM d, yyyy" caption underneath
//
// When `progress` is `nil` the arc is purely decorative — two stacked
// `GaugeArc()` strokes with no `trim`. When `progress` is non-nil, a
// faded full track is drawn first and a colored arc is trimmed to
// `displayedProgress` (driven from 0 on appear via `withAnimation`).
// The value-driven animation re-triggers on every change to
// `progress` (e.g. a fresh PB).

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
    /// Optional `[0, 1]` progress fraction. When `nil`, the arc is
    /// decorative (current behavior). When non-nil, a colored arc is
    /// drawn trimmed to `progress` over a faded full track, animating
    /// with `.easeInOut(duration: 0.6)` on first appear. Derive the
    /// value via `CarDetailGaugeProgress` so the math stays testable.
    var progress: Double? = nil

    @State private var displayedProgress: Double = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
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

            arc
                .frame(height: 100)
                .padding(.top, 2)

            HStack(alignment: .firstTextBaseline, spacing: 4) {
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
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .fill(color.opacity(0.08))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.xl, style: .continuous)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
        .onAppear {
            // Drive the trim from 0 to the final value with a 0.6s
            // ease-in-out. The implicit .animation on `progress`
            // only fires when the value changes after the view is
            // on screen; this is the entry-point animation.
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
            // Subsequent PB updates (e.g. user records a faster
            // time and comes back to the page) animate to the new
            // value via the existing 0.35s ease-in-out on the trim.
            withAnimation(.easeInOut(duration: 0.35)) {
                displayedProgress = newValue ?? 0
            }
        }
    }

    @ViewBuilder
    private var arc: some View {
        if let _ = progress {
            ZStack(alignment: .leading) {
                GaugeArc()
                    .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                GaugeArc()
                    .trim(from: 0, to: max(0.001, displayedProgress))
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .animation(.easeInOut(duration: 0.6), value: displayedProgress)
            }
        } else {
            ZStack(alignment: .leading) {
                GaugeArc()
                    .stroke(color.opacity(0.18), style: StrokeStyle(lineWidth: 6, lineCap: .round))
                GaugeArc()
                    .stroke(color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .opacity(0.85)
            }
        }
    }

    private func icon(for title: String) -> String {
        let t = title.lowercased()
        if t.contains("0-60") || t.contains("60") { return "timer" }
        if t.contains("speed") { return "speedometer" }
        return "gauge.with.needle"
    }
}
