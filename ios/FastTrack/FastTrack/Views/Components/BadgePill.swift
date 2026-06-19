import SwiftUI

/// Reusable colored capsule badge. Used for "You" markers, "Selected",
/// "Active", PB trophies, car-name chips, and notification counts.
///
/// All styles are Capsule-shaped and follow the same padding baseline
/// (`.horizontal, 6; .vertical, 2`) with a `caption2.semibold` font,
/// except `.count` which uses tighter padding for tiny numerals.
struct BadgePill: View {
    enum Style: Equatable {
        case you
        case selected
        case pb060
        case pbTopSpeed
        case carChip
        case count
    }

    let text: String
    let icon: String?
    let style: Style

    init(_ text: String, icon: String? = nil, style: Style) {
        self.text = text
        self.icon = icon
        self.style = style
    }

    var body: some View {
        HStack(spacing: 3) {
            if let icon {
                Image(systemName: icon)
                    .font(.caption2)
            }
            Text(text)
                .font(.caption2)
                .fontWeight(.semibold)
        }
        .foregroundColor(foreground)
        .padding(.horizontal, paddingH)
        .padding(.vertical, paddingV)
        .background(Capsule().fill(background))
        .overlay(strokeOverlay)
    }

    private var foreground: Color {
        switch style {
        case .you, .selected, .carChip: return .ftBlue
        case .pbTopSpeed, .count: return .white
        case .pb060: return .black
        }
    }

    private var background: Color {
        switch style {
        case .you, .selected: return .ftBlue.opacity(0.15)
        case .pb060: return .ftGold
        case .pbTopSpeed: return .ftRed
        case .carChip: return .ftBlue.opacity(0.15)
        case .count: return .ftRed
        }
    }

    @ViewBuilder
    private var strokeOverlay: some View {
        switch style {
        case .you, .selected, .carChip:
            Capsule().stroke(Color.ftBlue.opacity(0.30), lineWidth: 1)
        default:
            EmptyView()
        }
    }

    private var paddingH: CGFloat {
        switch style {
        case .count: return 4
        default: return 6
        }
    }

    private var paddingV: CGFloat {
        switch style {
        case .count: return 1
        default: return 2
        }
    }
}
