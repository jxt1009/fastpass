import SwiftUI

// MARK: - Stat Info Glossary (moved to Models/StatInfo.swift + Resources/stat_info.json)

// MARK: - Trend Direction

enum TrendDirection {
    case up, down, neutral

    var icon: String {
        switch self {
        case .up: return "arrow.up"
        case .down: return "arrow.down"
        case .neutral: return "minus"
        }
    }

    var color: Color {
        switch self {
        case .up: return .green
        case .down: return .red
        case .neutral: return .gray
        }
    }

    var label: String {
        switch self {
        case .up: return "Up"
        case .down: return "Down"
        case .neutral: return "Same"
        }
    }
}

// MARK: - Stat Info Button

struct StatInfoButton: View {
    let entry: StatInfoEntry
    @State private var showing = false

    var body: some View {
        Button {
            showing = true
        } label: {
            Image(systemName: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showing) {
            StatInfoSheet(entry: entry)
        }
    }
}

// MARK: - Stat Info Sheet

private struct StatInfoSheet: View {
    let entry: StatInfoEntry
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let unit = entry.unit {
                        HStack {
                            Label(unit, systemImage: "ruler")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("What it measures")
                            .font(.headline)
                        Text(entry.summary)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("How it's calculated")
                            .font(.headline)
                        Text(entry.howCalculated)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle(entry.title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}


// MARK: - Stat Card

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    let color: Color?
    let info: StatInfoEntry?

    init(title: String, value: String, icon: String, color: Color? = nil, info: StatInfoEntry? = nil) {
        self.title = title
        self.value = value
        self.icon = icon
        self.color = color
        self.info = info
    }

    var body: some View {
        if let color = color {
            // Colored version (used in ContentView)
            VStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.title3)
                    .foregroundColor(color)

                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                    .foregroundColor(color)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .cornerRadius(Radius.md)
        } else {
            // Default version (used in DriveDetailView)
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Label(title, systemImage: icon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let info { StatInfoButton(entry: info) }
                }
                Text(value)
                    .font(.title3)
                    .fontWeight(.semibold)
                    .monospacedDigit()
            }
.frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color.ftGlassCardFill)
            .cornerRadius(Radius.lg)
        }
    }
}

struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.medium)
        }
        .font(.subheadline)
    }
}

enum GradientProgressBarSize {
    case compact, hero
}

struct GradientProgressBar: View {
    let value: Double
    let range: ClosedRange<Double>
    let size: GradientProgressBarSize

    var fraction: Double {
        guard range.upperBound > range.lowerBound else { return 0 }
        return max(0, min(1, (value - range.lowerBound) / (range.upperBound - range.lowerBound)))
    }

    var trackHeight: CGFloat { size == .compact ? 5 : 8 }
    var dotDiameter: CGFloat { size == .compact ? 9 : 14 }

    private let gradient = LinearGradient(
        colors: [.ftGreen, .ftGold, .ftAmber, .ftRed],
        startPoint: .leading,
        endPoint: .trailing
    )

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(gradient)
                    .frame(height: trackHeight)
                Circle()
                    .fill(Color.white)
                    .overlay(Circle().stroke(Color.ftBg, lineWidth: 1.5))
                    .frame(width: dotDiameter, height: dotDiameter)
                    .offset(x: geo.size.width * fraction - dotDiameter / 2)
            }
        }
        .frame(height: dotDiameter)
    }
}

private struct ActiveGlowModifier: ViewModifier {
    let isActive: Bool
    let color: Color

    func body(content: Content) -> some View {
        content
            .shadow(color: isActive ? color.opacity(0.28) : .clear, radius: 10)
            .shadow(color: isActive ? color.opacity(0.18) : .clear, radius: 18)
            .animation(Motion.quick, value: isActive)
    }
}

extension View {
    func activeGlow(_ isActive: Bool, color: Color = .ftBlue) -> some View {
        modifier(ActiveGlowModifier(isActive: isActive, color: color))
    }
}

// MARK: - Shimmer / Skeleton loading

/// A view modifier that overlays a shimmering highlight to indicate loading.
struct ShimmerModifier: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color.ftShimmer, location: 0.4),
                            .init(color: .clear, location: 0.8),
                        ]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 2)
                    .offset(x: phase * geo.size.width * 2)
                }
                .clipped()
            )
            .onAppear {
                if !reduceMotion {
                    withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                        phase = 1
                    }
                }
            }
    }
}

extension View {
    func shimmer() -> some View {
        modifier(ShimmerModifier())
    }
}

/// A rounded rectangle placeholder that pulses while content loads.
struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 16
    var cornerRadius: CGFloat = Radius.xs + 2

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color.white.opacity(0.06))
            .frame(width: width, height: height)
            .shimmer()
    }
}

/// Skeleton row that mimics a leaderboard entry while loading.
struct LeaderboardSkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonBlock(width: 28, height: 20)
            Circle()
                .fill(Color.ftSkeleton)
                .frame(width: 36, height: 36)
                .shimmer()
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(width: 120, height: 14)
                SkeletonBlock(width: 80, height: 12)
            }
            Spacer()
            SkeletonBlock(width: 60, height: 20)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
    }
}

/// Skeleton card that mimics a stat card while loading.
struct StatCardSkeleton: View {
    var body: some View {
        VStack(spacing: 8) {
            SkeletonBlock(width: 24, height: 24, cornerRadius: Radius.xs)
            SkeletonBlock(width: 50, height: 12)
            SkeletonBlock(width: 70, height: 18)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color.ftGlassCardFill)
        .cornerRadius(Radius.lg)
    }
}

// MARK: - Instrument-Cluster Reusables

struct InstrumentStatCell: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let unit: String
    var info: StatInfoEntry? = nil

    var body: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: icon).foregroundColor(iconColor).font(.title3)
                    Spacer()
                    if let info { StatInfoButton(entry: info) }
                }
                Text(label)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(minHeight: 76, alignment: .topLeading)
        }
        .frame(maxWidth: .infinity)
    }
}

struct InstrumentButtonStyle: ButtonStyle {
    let color: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .fontWeight(.semibold)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding()
            .background(color)
            .cornerRadius(Radius.lg)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.easeInOut(duration: 0.15), value: configuration.isPressed)
    }
}

struct SectionHeader: View {
    let title: String
    var info: StatInfoEntry? = nil

    var body: some View {
        HStack {
            Text(title).font(.title3).fontWeight(.bold)
            if let info { StatInfoButton(entry: info) }
        }
        .padding(.top, 8)
    }
}

struct PerformanceBreakdownCard: View {
    let title: String
    let value: String
    let category: String
    let icon: String
    let color: Color
    var info: StatInfoEntry? = nil

    var body: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(color)
                        .font(.title3)
                    Spacer()
                    if let info { StatInfoButton(entry: info) }
                }

                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)

                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(category)
                    .font(.caption2)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(color.opacity(0.2))
                    .foregroundColor(color)
                    .cornerRadius(Radius.xs)
            }
        }
    }
}

// MARK: - Speech Bubble

/// A rounded-rectangle bubble with a small triangular tail at the bottom
/// centre. Used to label 0-60 attempts on the drive map.
struct SpeechBubble: Shape {
    var cornerRadius: CGFloat = Radius.md
    var tailWidth: CGFloat = 14
    var tailHeight: CGFloat = 8

    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = min(cornerRadius, min(rect.width, rect.height) / 2)
        let bodyBottom = rect.maxY - tailHeight
        let tailCenterX = rect.midX

        // Start at top-left, just past the corner.
        p.move(to: CGPoint(x: rect.minX + r, y: rect.minY))
        // Top edge to top-right corner.
        p.addLine(to: CGPoint(x: rect.maxX - r, y: rect.minY))
        // Top-right corner.
        p.addArc(
            center: CGPoint(x: rect.maxX - r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(-90),
            endAngle: .degrees(0),
            clockwise: false
        )
        // Right edge down to the start of the tail.
        p.addLine(to: CGPoint(x: rect.maxX, y: bodyBottom - r))
        // Bottom-right corner.
        p.addArc(
            center: CGPoint(x: rect.maxX - r, y: bodyBottom - r),
            radius: r,
            startAngle: .degrees(0),
            endAngle: .degrees(90),
            clockwise: false
        )
        // Bottom edge to the right side of the tail.
        p.addLine(to: CGPoint(x: tailCenterX + tailWidth / 2, y: bodyBottom))
        // Tail down to its tip.
        p.addLine(to: CGPoint(x: tailCenterX, y: rect.maxY))
        // Tail up to its left side.
        p.addLine(to: CGPoint(x: tailCenterX - tailWidth / 2, y: bodyBottom))
        // Bottom edge from the left side of the tail to the bottom-left corner.
        p.addLine(to: CGPoint(x: rect.minX + r, y: bodyBottom))
        // Bottom-left corner.
        p.addArc(
            center: CGPoint(x: rect.minX + r, y: bodyBottom - r),
            radius: r,
            startAngle: .degrees(90),
            endAngle: .degrees(180),
            clockwise: false
        )
        // Left edge up to the top-left corner.
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY + r))
        // Top-left corner.
        p.addArc(
            center: CGPoint(x: rect.minX + r, y: rect.minY + r),
            radius: r,
            startAngle: .degrees(180),
            endAngle: .degrees(270),
            clockwise: false
        )
        p.closeSubpath()
        return p
    }
}

/// A small filled circle with a label — used to add qualitative context to a metric or state.
struct StatusDot: View {
    let level: StatusLevel
    let label: String
    var font: Font = .caption

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(level.color)
                .frame(width: 6, height: 6)
            Text(label)
                .font(font)
                .fontWeight(.semibold)
                .foregroundStyle(level.color)
        }
    }
}

