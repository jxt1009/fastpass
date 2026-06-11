import SwiftUI

// MARK: - Public Car Detail Gauge
//
// Read-only variant of the per-car PB hero gauge used on the
// public-profile car detail view. Lighter than the own-profile variant
// (`DriveDetailView`'s gauges, or whatever Track E introduces):
//   - No "Set on <date>" subtitle — the public blob doesn't expose
//     when the PB was recorded.
//   - No driving-style / category annotation — that data is per-user-
//     per-drive and we don't have drives on the public side.
//   - No info button — the help text is for the user about their own
//     metric; a public visitor doesn't need it.
//
// The hero number and unit are the same as the own-profile gauge; the
// view sizes itself to the cell so the two gauges sit side-by-side
// under the hero photo.

struct PublicCarDetailGauge: View {
    let title: String
    let value: String?
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value ?? "—")
                .font(.system(.title, design: .monospaced))
                .fontWeight(.bold)
                .foregroundColor(value == nil ? .secondary : color)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
            HStack(spacing: 2) {
                Text(title)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.secondary)
                if !unit.isEmpty {
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
            RoundedRectangle(cornerRadius: Radius.md)
                .stroke(color.opacity(0.35), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: Radius.md)
                .fill(color.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title) \(value ?? "no data")\(unit.isEmpty ? "" : " \(unit)")")
    }
}
