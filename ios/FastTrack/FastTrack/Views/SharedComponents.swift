import SwiftUI

// MARK: - Stat Info Glossary

struct StatInfoEntry {
    let title: String
    let summary: String         // plain English: what does it measure?
    let howCalculated: String   // the algorithm / threshold detail
    let unit: String?

    init(_ title: String, summary: String, howCalculated: String, unit: String? = nil) {
        self.title = title
        self.summary = summary
        self.howCalculated = howCalculated
        self.unit = unit
    }
}

enum StatInfo {
    static let brakeEvents = StatInfoEntry(
        "Brake Events",
        summary: "Counts instances of hard braking during a drive.",
        howCalculated: "Triggered when GPS-derived deceleration exceeds 2.5 m/s² (~0.25g). A 4-second cooldown prevents the same stop from being counted multiple times.",
        unit: "count"
    )
    static let laneChanges = StatInfoEntry(
        "Lane Changes",
        summary: "Estimates lateral lane-change maneuvers.",
        howCalculated: "Detected when heading changes 10–35° over a 2-second GPS window while travelling above 15 mph. Sustained curves (ramps, cloverleafs) are excluded by checking that heading hasn't been rotating consistently in one direction for more than 5 seconds totalling >40° — so a 270° California cloverleaf onramp is correctly classified as a curve, not multiple lane changes. A 3-second cooldown prevents double-counting.",
        unit: "count"
    )
    static let leftTurns = StatInfoEntry(
        "Left Turns",
        summary: "Counts significant left-hand turns.",
        howCalculated: "Detected when heading decreases by more than 35° over a 2-second GPS window. A 4-second cooldown separates distinct turns.",
        unit: "count"
    )
    static let rightTurns = StatInfoEntry(
        "Right Turns",
        summary: "Counts significant right-hand turns.",
        howCalculated: "Detected when heading increases by more than 35° over a 2-second GPS window. A 4-second cooldown separates distinct turns.",
        unit: "count"
    )
    static let peakGForce = StatInfoEntry(
        "Peak G-Force",
        summary: "The highest combined lateral and longitudinal force experienced during the drive.",
        howCalculated: "Calculated as √(longitudinal_G² + lateral_G²) using GPS-derived acceleration. 1 G = 9.81 m/s². Values above ~0.4g feel noticeable; above ~1g is hard cornering.",
        unit: "G"
    )
    static let maxAcceleration = StatInfoEntry(
        "Max Acceleration",
        summary: "The fastest rate of forward acceleration recorded in a single GPS interval.",
        howCalculated: "Difference in GPS speed between consecutive readings divided by elapsed time, capped at physically plausible values. Measured in metres per second squared (m/s²).",
        unit: "m/s²"
    )
    static let maxDeceleration = StatInfoEntry(
        "Max Deceleration",
        summary: "The sharpest braking force recorded in a single GPS interval.",
        howCalculated: "Same method as Max Acceleration but for negative acceleration (slowing down). Higher numbers mean harder braking. 9.8 m/s² = 1G.",
        unit: "m/s²"
    )
    static let cornerSpeed = StatInfoEntry(
        "Top Corner Speed",
        summary: "The fastest speed recorded while cornering.",
        howCalculated: "The highest GPS speed at any moment where lateral G-force exceeds 0.15g, indicating the car is turning rather than going straight.",
        unit: "speed"
    )
    static let zeroToSixty = StatInfoEntry(
        "0–60 Time",
        summary: "Time to accelerate from a standstill to 60 mph.",
        howCalculated: "Timing starts when GPS speed drops below 5 mph and stops when speed reaches 60 mph. Only recorded once per run; if speed drops below 5 mph again, the timer resets. Not recorded if you never reach 60 mph.",
        unit: "seconds"
    )
    static let smoothness = StatInfoEntry(
        "Driving Smoothness",
        summary: "A 0–100 score measuring how steady and progressive your throttle, braking, and cornering inputs are.",
        howCalculated: "Starts from a speed-efficiency base (avg speed ÷ max speed × 100), then subtracts penalties: up to 15 points for hard acceleration (> 1g), up to 15 for hard braking (> 1g), up to 20 for high peak G-force (> 2g), and up to 20 for brake events (2 points each, capped at 10 events). The per-car score is the average across all drives for that car.",
        unit: "0–100"
    )
    static let performanceCategory = StatInfoEntry(
        "Performance Category",
        summary: "A label describing the performance tier of your car based on recorded top speed.",
        howCalculated: "Based on the highest GPS speed ever recorded with that car: City Car (<60 mph), Economy (60–90), Performance (90–120), Sports Car (120–150), Supercar (150+).",
        unit: nil
    )
    static let avgSpeed = StatInfoEntry(
        "Avg Speed",
        summary: "Your average speed across the entire drive including stops.",
        howCalculated: "Total distance divided by total elapsed drive time (from start to end). Note: this includes stopped time, so extended stops lower the average.",
        unit: "speed"
    )
    static let stoppedTime = StatInfoEntry(
        "Stopped Time",
        summary: "Total time the vehicle was stationary during the drive.",
        howCalculated: "Accumulated whenever GPS speed drops below 1 mph. Useful for understanding how much of your drive time was spent at lights or in traffic.",
        unit: "time"
    )
    static let drivingScore = StatInfoEntry(
        "Driving Score",
        summary: "A 0–100 composite score reflecting the quality of your driving across all recorded drives.",
        howCalculated: "Weighted average of three components: Smoothness (40%) — consistency of throttle and braking inputs; Consistency (30%) — how repeatable your smoothness is drive-to-drive; Performance (30%) — average top speed relative to the Sports Car threshold (100 mph). Higher scores reward smooth, consistent driving with decent speed.",
        unit: "0–100"
    )
static let cornering = StatInfoEntry(
        "Cornering",
        summary: "The highest lateral G-force recorded during your drives.",
        howCalculated: "Peak lateral G-force is derived from GPS heading changes. The value shown is the maximum across all filtered drives. Values above 0.6g indicate spirited cornering; above 0.8g is race-driver territory.",
        unit: "G"
    )
    static let consistency = StatInfoEntry(
        "Consistency",
        summary: "How repeatable your performance is drive-to-drive.",
        howCalculated: "Coefficient of variation of top speeds across drives. The standard deviation of max speeds is divided by the mean, then inverted to a 0–100 score. Higher means your top speeds are more predictable from drive to drive.",
        unit: "0–100"
    )
    static let periodComparison = StatInfoEntry(
        "Period Comparison",
        summary: "How your average max speed this period compares to the previous equivalent period.",
        howCalculated: "The average max speed across all drives in the current time window minus the same metric from the prior window. A delta above +0.5 speed-units shows as 'Up'; below −0.5 as 'Down'; within ±0.5 as 'Same'.",
        unit: nil
    )
    static let avgMaxSpeed = StatInfoEntry(
        "Avg Max Speed",
        summary: "The average of your highest speeds across all filtered drives.",
        howCalculated: "Sum of each drive's max speed divided by the number of drives. Not the average speed of a single drive — this measures the typical ceiling of your driving sessions.",
        unit: "speed"
    )
    // Section-level info
    static let maneuversSection = StatInfoEntry(
        "Maneuvers",
        summary: "Counts significant directional events detected from GPS heading changes.",
        howCalculated: "All maneuver detection uses GPS course data sampled roughly once per second. Accuracy depends on GPS quality and may miss very brief maneuvers at low speed. False positives can occur on winding roads.",
        unit: nil
    )
    static let performanceSection = StatInfoEntry(
        "Performance",
        summary: "Acceleration and G-force metrics derived from GPS speed changes.",
        howCalculated: "Calculated by comparing consecutive GPS speed readings. GPS speed accuracy varies by device and environment — values recorded at poor GPS accuracy are excluded. All metrics represent the peak value recorded during the drive.",
        unit: nil
    )
}

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
            .background(Color.ftCardBg)
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

struct GaugeProgressBar: View {
    let progress: Double
    var color: Color = .ftBlue
    var height: CGFloat = 6

    private var clampedProgress: Double {
        min(max(progress, 0), 1)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = max(proxy.size.width * clampedProgress, height)

            Capsule()
                .fill(Color.ftSectionBg)
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(color)
                        .frame(width: clampedProgress == 0 ? 0 : width)
                        .animation(Motion.standard, value: clampedProgress)
                }
        }
        .frame(height: height)
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
    @State private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        gradient: Gradient(stops: [
                            .init(color: .clear, location: 0),
                            .init(color: Color.white.opacity(0.35), location: 0.4),
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
                withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) {
                    phase = 1
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
            .fill(Color.ftSectionBg.opacity(0.5))
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
                .fill(Color(.systemGray5))
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
        .background(Color.ftCardBg)
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
                Text(label).font(.caption).foregroundColor(.secondary)
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value).font(.title2).fontWeight(.bold).foregroundColor(.primary)
                    if !unit.isEmpty {
                        Text(unit).font(.caption).foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct MetricGauge: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .monospaced)).fontWeight(.bold)
                .foregroundColor(color)
            HStack(spacing: 2) {
                Text(title).font(.caption2.weight(.semibold)).minimumScaleFactor(0.75).foregroundColor(.secondary)
                Text(unit).font(.caption2).minimumScaleFactor(0.7).foregroundColor(.secondary.opacity(0.6))
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(Color.ftCardBg)
        .cornerRadius(Radius.sm)
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

