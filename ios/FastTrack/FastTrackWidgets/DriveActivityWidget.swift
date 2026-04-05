import ActivityKit
import WidgetKit
import SwiftUI

// MARK: - Live Activity Widget

struct DriveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: DriveActivityAttributes.self) { context in
            // Standard lock screen / notification banner view
            LockScreenLiveActivityView(context: context)
                .activityBackgroundTint(Color.black.opacity(0.8))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded island (press-and-hold)
                DynamicIslandExpandedRegion(.leading) {
                    Label {
                        Text(String(format: "%.0f", context.state.speedMph))
                            .font(.title2).fontWeight(.bold)
                    } icon: {
                        Image(systemName: "speedometer")
                            .foregroundColor(.yellow)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Label {
                        Text(String(format: "%.2fG", context.state.gForce))
                            .font(.title2).fontWeight(.bold)
                    } icon: {
                        Image(systemName: "circle.circle.fill")
                            .foregroundColor(.orange)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    HStack(spacing: 4) {
                        Image(systemName: "record.circle")
                            .foregroundColor(.red)
                            .symbolEffect(.pulse)
                        Text(timerInterval: context.attributes.startDate...Date.distantFuture,
                             countsDown: false)
                            .font(.headline).fontWeight(.semibold)
                            .monospacedDigit()
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text(String(format: "%.2f mi", context.state.distanceMiles))
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                // Speed in compact leading slot
                HStack(spacing: 2) {
                    Image(systemName: "speedometer")
                        .font(.caption2)
                        .foregroundColor(.yellow)
                    Text(String(format: "%.0f", context.state.speedMph))
                        .font(.caption).fontWeight(.semibold)
                        .monospacedDigit()
                }
            } compactTrailing: {
                // G-force in compact trailing slot
                Text(String(format: "%.1fG", context.state.gForce))
                    .font(.caption).fontWeight(.semibold)
                    .foregroundColor(.orange)
                    .monospacedDigit()
            } minimal: {
                Image(systemName: "record.circle")
                    .foregroundColor(.red)
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
            // CarPlay / Watch compact view
            smallView
        } else {
            // Lock screen / notification view
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
                Text(timerInterval: context.attributes.startDate...Date.distantFuture,
                     countsDown: false)
                    .font(.headline).fontWeight(.semibold)
                    .monospacedDigit()
                Text("elapsed")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    // Full lock screen / notification view
    private var lockScreenView: some View {
        HStack(spacing: 0) {
            // Recording indicator + timer
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .foregroundColor(.red)
                        .symbolEffect(.pulse)
                    Text("Recording")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Text(timerInterval: context.attributes.startDate...Date.distantFuture,
                     countsDown: false)
                    .font(.title2).fontWeight(.bold)
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Speed
            VStack(spacing: 2) {
                Text(String(format: "%.0f", context.state.speedMph))
                    .font(.title).fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(.yellow)
                Text("mph")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            // G-Force
            VStack(spacing: 2) {
                Text(String(format: "%.2f", context.state.gForce))
                    .font(.title).fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(.orange)
                Text("G")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)

            // Distance
            VStack(spacing: 2) {
                Text(String(format: "%.1f", context.state.distanceMiles))
                    .font(.title).fontWeight(.bold)
                    .monospacedDigit()
                    .foregroundColor(.green)
                Text("mi")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
