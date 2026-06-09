import SwiftUI

// MARK: - Drive Performance Detail View

struct DrivePerformanceDetailView: View {
    let drive: Drive
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Performance Summary
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Performance Summary")
                            .font(.headline)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                            PerformanceStatCard(title: "Max Speed", value: AppSettings.shared.speedDisplay(drive.maxSpeed), icon: "speedometer")
                            PerformanceStatCard(title: "Avg Speed", value: AppSettings.shared.speedDisplay(drive.avgSpeed), icon: "gauge.medium")
                            PerformanceStatCard(title: "Distance", value: AppSettings.shared.distanceDisplay(drive.distance), icon: "map")
                            PerformanceStatCard(title: "Duration", value: formatDuration(drive.duration), icon: "clock")
                        }
                    }
                    
                    // Detailed Analysis
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Detailed Analysis")
                            .font(.headline)

                        if drive.maxAcceleration > 0 || drive.maxDeceleration > 0 || drive.peakGForce > 0 {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                if drive.maxAcceleration > 0 {
                                    PerformanceStatCard(
                                        title: "Max Accel",
                                        value: String(format: "%.2f G", drive.maxAcceleration / 9.81),
                                        icon: "arrow.up.right.circle"
                                    )
                                }
                                if drive.maxDeceleration > 0 {
                                    PerformanceStatCard(
                                        title: "Max Brake",
                                        value: String(format: "%.2f G", drive.maxDeceleration / 9.81),
                                        icon: "arrow.down.right.circle"
                                    )
                                }
                                if drive.peakGForce > 0 {
                                    PerformanceStatCard(
                                        title: "Peak G-Force",
                                        value: String(format: "%.2f G", drive.peakGForce),
                                        icon: "circle.circle"
                                    )
                                }
                                if let best060 = drive.best060Time {
                                    PerformanceStatCard(
                                        title: "0–60 mph",
                                        value: String(format: "%.2f sec", best060),
                                        icon: "timer"
                                    )
                                }
                            }
                        }

                        if drive.brakeEvents > 0 || drive.leftTurns > 0 || drive.rightTurns > 0 || drive.laneChanges > 0 {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                                if drive.brakeEvents > 0 {
                                    PerformanceStatCard(title: "Brakes", value: "\(drive.brakeEvents)", icon: "hand.raised.fill")
                                }
                                if drive.leftTurns > 0 {
                                    PerformanceStatCard(title: "Left Turns", value: "\(drive.leftTurns)", icon: "arrow.turn.up.left")
                                }
                                if drive.rightTurns > 0 {
                                    PerformanceStatCard(title: "Right Turns", value: "\(drive.rightTurns)", icon: "arrow.turn.up.right")
                                }
                                if drive.laneChanges > 0 {
                                    PerformanceStatCard(title: "Lane Changes", value: "\(drive.laneChanges)", icon: "arrow.left.arrow.right")
                                }
                            }
                        }

                        // Smoothness score
                        let smoothness = smoothnessScore(for: drive)
                        if smoothness > 0 {
                            InstrumentCard {
                                HStack {
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text("Driving Style Score")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                        Text(String(format: "%.0f / 100", smoothness))
                                            .font(.title3)
                                            .fontWeight(.bold)
                                    }
                                    Spacer()
                                    ProgressView(value: smoothness / 100)
                                        .progressViewStyle(.linear)
                                        .tint(smoothness > 75 ? .green : smoothness > 50 ? .orange : .red)
                                        .frame(width: 100)
                                }
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Performance Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

struct PerformanceStatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Image(systemName: icon)
                        .foregroundColor(.blue)
                    Spacer()
                }
                
                Text(value)
                    .font(.headline)
                    .fontWeight(.bold)
                
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
    }
}
