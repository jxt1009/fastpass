import SwiftUI

// ─── Colors ────────────────────────────────────────────────

extension Color {
    static let ftBlue   = Color(red: 10/255, green: 132/255, blue: 255/255)   // #0A84FF
    static let ftAmber  = Color(red: 255/255, green: 107/255, blue: 53/255)   // #FF6B35
    static let ftGreen  = Color(red: 48/255, green: 209/255, blue: 88/255)    // #30D158
    static let ftRed    = Color(red: 255/255, green: 69/255, blue: 58/255)    // #FF453A
    static let ftGold   = Color(red: 255/255, green: 214/255, blue: 10/255)   // #FFD60A
    static let ftBg     = Color(red: 7/255, green: 7/255, blue: 11/255)       // #07070B
    static let ftSurface = Color(red: 18/255, green: 18/255, blue: 22/255)     // #121216
}

// ─── Font Modifier ─────────────────────────────────────────

struct FTMono: ViewModifier {
    func body(content: Content) -> some View {
        content.font(.system(.body, design: .monospaced))
    }
}

extension View {
    func ftMono() -> some View {
        modifier(FTMono())
    }
}

// ─── Dashboard Gauge (web stat-card look) ─────────────────

struct DashboardGauge: View {
    let value: String
    let label: String
    let color: Color

    var body: some View {
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
                .stroke(Color(.systemGray4).opacity(0.3), lineWidth: 1)
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
        )
    }
}

// ─── Color-coded stat value (for inline stat rows) ──────

struct StatValue: View {
    let value: String
    let color: Color

    var body: some View {
        Text(value)
            .font(.system(.title3, design: .monospaced))
            .fontWeight(.bold)
            .foregroundColor(color)
    }
}
