import SwiftUI

// ─── Colors ────────────────────────────────────────────────

private struct AdaptiveRadialGradient: ShapeStyle {
    let darkColors: [Color]
    let lightColors: [Color]
    let center: UnitPoint
    let startRadius: CGFloat
    let endRadius: CGFloat

    func resolve(in env: EnvironmentValues) -> some ShapeStyle {
        let colors = env.colorScheme == .light ? lightColors : darkColors
        return AnyShapeStyle(
            RadialGradient(
                colors: colors,
                center: center,
                startRadius: startRadius,
                endRadius: endRadius
            )
        )
    }
}

extension Color {
    static let ftBlue   = Color(red: 10/255, green: 132/255, blue: 255/255)   // #0A84FF
    static let ftRed    = Color(red: 255/255, green: 69/255, blue: 58/255)    // #FF453A
    static let ftBg     = Color(red: 7/255, green: 7/255, blue: 11/255)       // #07070B
    static let ftSurface = Color(red: 18/255, green: 18/255, blue: 22/255)     // #121216

    // ── Brand colors (light/dark adaptive) ──────────
    // Light variants darken the palette so text/icons on the near-white
    // `ftGlassCardFill` light-mode surface pass WCAG AA contrast.

    static var ftGold: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.84, blue: 0.04, alpha: 1.0)   // #FFD60A
                : UIColor(red: 0.72, green: 0.52, blue: 0.0, alpha: 1.0)   // #B88500
        })
    }
    static var ftAmber: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 1.0, green: 0.42, blue: 0.21, alpha: 1.0)   // #FF6B35
                : UIColor(red: 0.76, green: 0.25, blue: 0.05, alpha: 1.0)  // #C2410C
        })
    }
    static var ftGreen: Color {
        Color(UIColor { trait in
            trait.userInterfaceStyle == .dark
                ? UIColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1.0)  // #30D158
                : UIColor(red: 0.08, green: 0.51, blue: 0.24, alpha: 1.0)  // #15803D
        })
    }

    // ── Semantic backgrounds (light/dark adaptive) ──────────

    static let ftSurfaceBg = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(red: 7/255, green: 7/255, blue: 11/255, alpha: 1)
            : UIColor.systemGroupedBackground
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

    static let ftShimmer = Color.white.opacity(0.12)
    static let ftScrim = Color.black.opacity(0.45)
    static let ftRankGold = Color.ftGold
    static let ftRankSilver = Color(red: 192/255, green: 192/255, blue: 192/255)
    static let ftRankBronze = Color(red: 205/255, green: 127/255, blue: 50/255)
    static let ftOnDarkDivider = Color.white.opacity(0.14)
    static let ftHairline = Color.white.opacity(0.1)
    static let ftSkeleton = Color(.systemGray5)
    static let ftPB060Tint = Color.ftGold
    static let ftPBTopSpeedTint = Color.ftRed
    static let ftErrorBackground = Color.red.opacity(0.6)

    // ── Background gradients ─────────────────────────────────

    /// Default screen background — deep navy → near-black radial gradient.
    static var ftBgGradient: some ShapeStyle {
        AdaptiveRadialGradient(
            darkColors: [Color(red: 0.10, green: 0.10, blue: 0.23), Color(red: 0.027, green: 0.027, blue: 0.043)],
            lightColors: [Color(red: 0.92, green: 0.94, blue: 0.98), Color(red: 0.78, green: 0.82, blue: 0.90)],
            center: .topLeading,
            startRadius: 0,
            endRadius: 500
        )
    }

    /// Recording-active screen background — warm dark radial gradient.
    static var ftBgGradientWarm: some ShapeStyle {
        AdaptiveRadialGradient(
            darkColors: [Color(red: 0.12, green: 0.04, blue: 0.0), Color(red: 0.027, green: 0.027, blue: 0.043)],
            lightColors: [Color(red: 1.00, green: 0.93, blue: 0.86), Color(red: 0.95, green: 0.88, blue: 0.80)],
            center: .top,
            startRadius: 0,
            endRadius: 500
        )
    }

    // ── Glass card tokens ────────────────────────────────────

    /// Glass card fill — white at ~7% (dark) / ~55% (light) opacity. Use with `ftGlassCardStroke` border.
    static let ftGlassCardFill = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.07)
            : UIColor(white: 1, alpha: 0.55)
    })
    /// Glass card border stroke — white at ~12% (dark) / ~75% (light) opacity.
    static let ftGlassCardStroke = Color(UIColor { trait in
        trait.userInterfaceStyle == .dark
            ? UIColor(white: 1, alpha: 0.12)
            : UIColor(white: 1, alpha: 0.75)
    })
}

// ─── Status Level ───────────────────────────────────────────

enum StatusLevel {
    case best       // ftGold  — PB, #1 rank
    case improving  // ftGreen — improving, above average, GPS excellent
    case nearBest   // ftAmber — near best, active, GPS good
    case typical    // ftBlue  — normal, info, GPS fair
    case inactive   //          — idle, locked, GPS poor

    var color: Color {
        switch self {
        case .best:      return .ftGold
        case .improving: return .ftGreen
        case .nearBest:  return .ftAmber
        case .typical:   return .ftBlue
        case .inactive:  return Color(white: 0.33)
        }
    }
}

// ─── Spacing ───────────────────────────────────────────────

enum Spacing {
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 16
    static let lg: CGFloat = 24
    static let xl: CGFloat = 32
}

// ─── Radius ─────────────────────────────────────────────────

enum Radius {
    static let xxxs: CGFloat = 1.5
    static let xxs: CGFloat = 3
    static let xs: CGFloat = 4
    static let sm: CGFloat = 8
    static let md: CGFloat = 10
    static let lg: CGFloat = 12
    static let xl: CGFloat = 14
    static let xxl: CGFloat = 18
    static let xxxl: CGFloat = 20
    static let giant: CGFloat = 24
}

enum Motion {
    static let quick: Animation = .easeOut(duration: 0.14)
    static let standard: Animation = .easeInOut(duration: 0.24)
    static let entrance: Animation = .spring(response: 0.36, dampingFraction: 0.88)
    static let hero: Animation = .spring(response: 0.52, dampingFraction: 0.84)
}

// ─── Typography ─────────────────────────────────────────────

enum FTFont {
    static let speedHero = Font.system(size: 96, weight: .heavy, design: .monospaced)
    static let gaugeNumber = Font.system(size: 32, weight: .bold, design: .monospaced)
    static let gaugeValue = Font.system(size: 28, weight: .bold, design: .monospaced)
    static let gaugeLabelCompact = Font.system(size: 8, weight: .semibold)
    static let pill = Font.system(size: 9, weight: .bold)
    static let scoreboard = Font.system(size: 36)
    static let trophy = Font.system(size: 40)
    static let wordmark = Font.system(size: 36, weight: .bold, design: .rounded)
    static let appIcon = Font.system(size: 52, weight: .medium)
    static let iconLarge = Font.system(size: 80)
    static let iconXLarge = Font.system(size: 48, weight: .bold, design: .rounded)
    static let subtitleBold = Font.system(size: 18, weight: .bold)
    static let sectionCaption = Font.system(size: 24)
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
    var padding: CGFloat = Spacing.md

    init(padding: CGFloat = Spacing.md, @ViewBuilder content: () -> Content) {
        self.padding = padding
        self.content = content()
    }

    var body: some View {
        content
            .padding(padding)
            .background(Color.ftGlassCardFill)
            .overlay(
                RoundedRectangle(cornerRadius: Radius.xl)
                    .stroke(Color.ftGlassCardStroke, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Radius.xl))
    }
}

// ─── Gauge Arc ──────────────────────────────────────────
//
// `FTGaugeArc` (in `Views/Components/FTGauge.swift`) is the
// consolidated shape used by the per-car PB hero gauge.
// The legacy `GaugeArc` previously defined here was removed in
// the C-4 consolidation.
