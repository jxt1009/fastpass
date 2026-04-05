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
        summary: "A 0–100 score measuring how steady and consistent your acceleration inputs are.",
        howCalculated: "Calculated as 100 minus ten times the statistical variance of acceleration samples throughout the drive. High variance (lots of hard throttle/brake inputs) lowers the score. Scores above 80 indicate smooth, controlled driving.",
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
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .background(color.opacity(0.1))
            .cornerRadius(10)
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
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
            .background(Color(.systemGray6))
            .cornerRadius(12)
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
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius)
            .fill(Color(.systemGray5))
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
            SkeletonBlock(width: 24, height: 24, cornerRadius: 4)
            SkeletonBlock(width: 50, height: 12)
            SkeletonBlock(width: 70, height: 18)
        }
        .frame(maxWidth: .infinity)
        .padding()
        .background(Color(.secondarySystemBackground))
        .cornerRadius(12)
    }
}
