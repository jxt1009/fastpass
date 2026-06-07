import SwiftUI

// MARK: - Driving Style Badge
//
// A small pill that surfaces the computed `DrivingStyle` on the
// per-car detail view. The body is a tinted capsule with an icon +
// label; tapping the badge is a no-op for now (a future tooltip
// explaining the heuristic is tracked in the plan's out-of-scope
// list).

struct DrivingStyleBadge: View {
    let style: DrivingStyle

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: style.icon)
                .font(.caption)
                .foregroundColor(style.color)
            Text(style.title)
                .font(.caption)
                .fontWeight(.semibold)
                .foregroundColor(style.color)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule()
                .fill(style.color.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(style.color.opacity(0.35), lineWidth: 0.5)
        )
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Driving style: \(style.title). \(style.explanation).")
    }
}
