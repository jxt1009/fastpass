import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity Widget

struct DriveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveActivityAttributes.self) { context in
            // Standard lock screen / notification banner view
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.85))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded island (press-and-hold)
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label("Speed", systemImage: "speedometer")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                        Text(String(format: "%.0f mph", context.state.speedMph))
                            .font(.title2).fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(.yellow)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Label("G-Force", systemImage: "circle.circle.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .labelStyle(.titleAndIcon)
                        Text(String(format: "%.2fG", context.state.gForce))
                            .font(.title2).fontWeight(.bold)
                            .monospacedDigit()
                            .foregroundColor(.orange)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: context.state.phase == .ended ? "checkmark.circle.fill" : "record.circle")
                                .foregroundColor(context.state.phase == .ended ? .green : .red)
                                .symbolEffect(.pulse)
                            Text(context.state.phase == .ended ? "Drive complete" : "FastTrack")
                                .font(.caption).fontWeight(.semibold)
                                .foregroundStyle(.secondary)
                        }
                        if context.state.phase == .ended {
                            Text(formatElapsed(context.state.elapsedSeconds))
                                .font(.headline).fontWeight(.semibold)
                                .monospacedDigit()
                        } else {
                            Text(timerInterval: context.attributes.startDate...Date.distantFuture,
                                 countsDown: false)
                                .font(.headline).fontWeight(.semibold)
                                .monospacedDigit()
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 20) {
                        // Distance
                        VStack(spacing: 1) {
                            Text(String(format: "%.2f mi", context.state.distanceMiles))
                                .font(.subheadline).fontWeight(.semibold)
                                .monospacedDigit()
                            Text("distance")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        // Max speed
                        VStack(spacing: 1) {
                            Text(String(format: "%.0f mph", context.state.maxSpeedMph))
                                .font(.subheadline).fontWeight(.semibold)
                                .monospacedDigit()
                                .foregroundColor(.yellow.opacity(0.8))
                            Text("top speed")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        // Stop button — deep-links into the app to stop recording.
                        // Hidden in the ended phase — drive is already over.
                        if context.state.phase == .recording {
                            Link(destination: URL(string: "fasttrack://stop-recording")!) {
                                Label("Stop", systemImage: "stop.circle.fill")
                                    .font(.caption).fontWeight(.semibold)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 5)
                                    .background(Color.red.opacity(0.8), in: Capsule())
                            }
                        }
                    }
                    .padding(.top, 4)
                }
            } compactLeading: {
                HStack(spacing: 2) {
                    Image(systemName: context.state.phase == .ended ? "checkmark.circle.fill" : "speedometer")
                        .font(.caption2)
                        .foregroundColor(context.state.phase == .ended ? .green : .yellow)
                    Text(String(format: "%.0f", context.state.speedMph))
                        .font(.caption).fontWeight(.semibold)
                        .monospacedDigit()
                }
            } compactTrailing: {
                Text(String(format: "%.1fG", context.state.gForce))
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.orange)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: context.state.phase == .ended ? "checkmark.circle.fill" : "record.circle")
                    .foregroundColor(context.state.phase == .ended ? .green : .red)
                    .symbolEffect(.pulse)
            }
        }
    }
}

// MARK: - Lock Screen / Notification View

private struct LockScreenLiveActivityView: View {
    let context: ActivityViewContext<DriveActivityAttributes>
    @Environment(\.activityFamily) var activityFamily

    var body: some View {
        if activityFamily == .small {
            smallView
        } else {
            lockScreenView
        }
    }

    // Compact view for CarPlay Dashboard and watchOS Smart Stack
    private var smallView: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(String(format: "%.0f", context.state.speedMph))
                    .font(.title).fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(.yellow)
                Text("mph")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Divider()
                .frame(height: 30)
                .overlay(.white.opacity(0.3))
            VStack(alignment: .leading, spacing: 2) {
                if context.state.phase == .ended {
                    Text(formatElapsed(context.state.elapsedSeconds))
                        .font(.headline).fontWeight(.semibold)
                        .monospacedDigit()
                    Text("elapsed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } else {
                    Text(timerInterval: context.attributes.startDate...Date.distantFuture,
                         countsDown: false)
                        .font(.headline).fontWeight(.semibold)
                        .monospacedDigit()
                    Text("elapsed")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // Full lock screen / notification view
    private var lockScreenView: some View {
        VStack(spacing: 10) {
            HStack {
                HStack(spacing: 5) {
                    Image(systemName: context.state.phase == .ended ? "checkmark.circle.fill" : "record.circle")
                        .foregroundColor(context.state.phase == .ended ? .green : .red)
                        .symbolEffect(.pulse)
                    Text(context.state.phase == .ended ? "Drive complete" : "FastTrack")
                        .font(.caption).fontWeight(.semibold)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if context.state.phase == .ended {
                    Text(formatElapsed(context.state.elapsedSeconds))
                        .font(.headline).fontWeight(.bold)
                        .monospacedDigit()
                } else {
                    Text(timerInterval: context.attributes.startDate...Date.distantFuture,
                         countsDown: false)
                        .font(.headline).fontWeight(.bold)
                        .monospacedDigit()
                }
                Spacer()
                // Deep-link stop button — hidden once the drive has ended.
                if context.state.phase == .recording {
                    Link(destination: URL(string: "fasttrack://stop-recording")!) {
                        Label("Stop", systemImage: "stop.circle.fill")
                            .font(.caption).fontWeight(.semibold)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color.red.opacity(0.75), in: Capsule())
                    }
                } else {
                    Color.clear.frame(width: 1, height: 1)
                }
            }

            // Stats row
            HStack(spacing: 0) {
                statCell(value: String(format: "%.0f", context.state.speedMph),
                         unit: "mph", color: .yellow)
                statCell(value: String(format: "%.0f", context.state.maxSpeedMph),
                         unit: "top mph", color: .yellow.opacity(0.7))
                statCell(value: String(format: "%.2f", context.state.gForce),
                         unit: "G", color: .orange)
                statCell(value: String(format: "%.1f", context.state.distanceMiles),
                         unit: "mi", color: .green)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func statCell(value: String, unit: String, color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title2).fontWeight(.bold)
                .monospacedDigit()
                .foregroundColor(color)
            Text(unit)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Helpers

private func formatElapsed(_ t: TimeInterval) -> String {
    let h = Int(t) / 3600
    let m = (Int(t) % 3600) / 60
    let s = Int(t) % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
}
