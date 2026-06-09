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

    // ── Semantic backgrounds (light/dark adaptive) ──────────

    static let ftSurfaceBg = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 7/255, green: 7/255, blue: 11/255, alpha: 1)
            : UIColor.systemGroupedBackground
    })

    static let ftCardBg = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 18/255, green: 18/255, blue: 22/255, alpha: 1)
            : UIColor.secondarySystemGroupedBackground
    })

    static let ftSectionBg = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 28/255, green: 28/255, blue: 30/255, alpha: 1)
            : UIColor.systemBackground
    })

    static let ftGlassSurface = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.06)
            : UIColor(white: 1, alpha: 0.72)
    })

    static let ftGlassStroke = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.14)
            : UIColor(white: 1, alpha: 0.85)
    })

    static let ftHighlight = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.16)
            : UIColor(white: 1, alpha: 0.42)
    })
}

// ─── Spacing ───────────────────────────────────────────────

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

enum Motion {
    static let quick: Animation = .easeOut(duration: 0.14)
    static let standard: Animation = .easeInOut(duration: 0.24)
    static let entrance: Animation = .spring(response: 0.36, dampingFraction: 0.88)
    static let hero: Animation = .spring(response: 0.52, dampingFraction: 0.84)
}

// ─── Speed Color Mapping ───────────────────────────────────

enum SpeedColor {
    /// Returns a color on a green→amber→orange→red gradient based on speed threshold.
    /// - speedInMps: speed in meters per second
    /// - Returns: Color interpolated along the gradient
    static func color(for speedInMps: Double) -> Color {
        let speed = max(0, speedInMps)

        typealias Stop = (threshold: Double, r: Double, g: Double, b: Double)
        let stops: [Stop] = [
            (0,    48/255, 209/255, 88/255),     // green
            (11.2, 48/255, 209/255, 88/255),     // green
            (22.3, 255/255, 107/255, 53/255),    // amber
            (35.8, 255/255, 159/255, 10/255),    // orange
            (60,   255/255, 69/255, 58/255),     // red
        ]

        for i in 0..<stops.count - 1 {
            let (s0, r0, g0, b0) = stops[i]
            let (s1, r1, g1, b1) = stops[i + 1]
            if speed >= s0 && speed <= s1 {
                let t = s1 == s0 ? 0 : (speed - s0) / (s1 - s0)
                return Color(red: r0 + (r1 - r0) * t,
                             green: g0 + (g1 - g0) * t,
                             blue: b0 + (b1 - b0) * t)
            }
        }

        return Color.ftRed
    }
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
    var compact: Bool = false

    var body: some View {
        if compact {
            HStack(spacing: 6) {
                Text(value)
                    .font(.system(.body, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(color)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)

                Text(label.uppercased())
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(.secondary)
                    .tracking(0.5)
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.ftSectionBg, lineWidth: 1)
            )
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.ftCardBg)
            )
        } else {
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

// ─── Instrument Card ────────────────────────────────────

struct InstrumentCard<Content: View>: View {
    let content: Content
    var glass: Bool

    init(glass: Bool = false, @ViewBuilder content: () -> Content) {
        self.glass = glass
        self.content = content()
    }

    var body: some View {
        content
            .padding(Spacing.md)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(glass ? Color.ftGlassSurface : Color.ftCardBg)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(glass ? Color.ftGlassStroke : Color.clear, lineWidth: 1)
            )
    }
}

// ─── Gauge Arc ──────────────────────────────────────────

struct GaugeArc: Shape {
    var startAngle: Angle = .degrees(135)
    var endAngle: Angle = .degrees(45)

    func path(in rect: CGRect) -> Path {
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let radius = min(rect.width, rect.height) / 2

        let start = Angle.degrees(startAngle.degrees - 90)
        let end = Angle.degrees(endAngle.degrees - 90)

        return Path { path in
            path.addArc(center: center,
                       radius: radius,
                       startAngle: start,
                       endAngle: end,
                       clockwise: true)
        }
    }
}
