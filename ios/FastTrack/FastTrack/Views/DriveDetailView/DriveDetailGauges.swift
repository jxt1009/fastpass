import SwiftUI

// MARK: - DriveDetailGauges

struct DriveDetailGauges: View {
    let drive: Drive
    let settings: AppSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            StatsGrid(spacing: 12) {
                FTGauge(style: .compact, label: "Top Speed", value: settings.speedDisplay(drive.maxSpeed), color: .ftAmber)
                FTGauge(style: .compact, label: "Distance", value: settings.distanceDisplay(drive.distance, decimals: 1), color: .ftBlue)
                FTGauge(style: .compact, label: "Duration", value: drive.durationString, color: .ftBlue)
                if let best = drive.best060Time {
                    FTGauge(style: .compact, label: "0-60", value: String(format: "%.1fs", best), color: .ftGreen)
                } else {
                    FTGauge(style: .compact, label: "Avg Speed", value: settings.speedDisplay(drive.avgSpeed), color: .secondary)
                }
            }

            if drive.leftTurns > 0 || drive.rightTurns > 0 || drive.brakeEvents > 0 {
                extendedStats
            }
        }
    }

    private var extendedStats: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Driving Stats")
                    .font(.headline)

                StatsGrid(spacing: 15) {
                    StatCard(title: "Left Turns",    value: "\(drive.leftTurns)",   icon: "arrow.turn.up.left",   info: StatInfo.leftTurns)
                    StatCard(title: "Right Turns",   value: "\(drive.rightTurns)",  icon: "arrow.turn.up.right",  info: StatInfo.rightTurns)
                    StatCard(title: "Brake Events",  value: "\(drive.brakeEvents)", icon: "hand.raised.fill",     info: StatInfo.brakeEvents)
                    StatCard(title: "Lane Changes",  value: "\(drive.laneChanges)", icon: "arrow.left.arrow.right", info: StatInfo.laneChanges)
                }

                if drive.maxAcceleration > 0 {
                    StatsGrid(spacing: 15) {
                        StatCard(title: "Max Accel", value: String(format: "%.1f m/s²", drive.maxAcceleration), icon: "arrow.up.circle",   info: StatInfo.maxAcceleration)
                        StatCard(title: "Max Decel", value: String(format: "%.1f m/s²", drive.maxDeceleration), icon: "arrow.down.circle", info: StatInfo.maxDeceleration)
                    }
                }

                if drive.peakGForce > 0 {
                    StatsGrid(spacing: 15) {
                        StatCard(title: "Peak G-Force", value: String(format: "%.2f G", drive.peakGForce), icon: "circle.circle", info: StatInfo.peakGForce)
                        if let best060 = drive.best060Time {
                            StatCard(title: "0-60 Time", value: String(format: "%.1f sec", best060), icon: "timer", info: StatInfo.zeroToSixty)
                        }
                    }
                }
            }
        }
    }
}
