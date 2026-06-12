import SwiftUI

// MARK: - DriveDetailTripCard

struct DriveDetailTripCard: View {
    let drive: Drive
    let onTapCarPicker: () -> Void

    var body: some View {
        InstrumentCard {
            VStack(alignment: .leading, spacing: 10) {
                Text("Trip Details")
                    .font(.headline)

                DetailRow(label: "Start Time", value: drive.startTime.formatted(date: .long, time: .shortened))
                DetailRow(label: "End Time",   value: drive.endTime.formatted(date: .long, time: .shortened))

                HStack {
                    Text("Car").fontWeight(.medium)
                    Spacer()
                    Button { onTapCarPicker() } label: {
                        HStack(spacing: 4) {
                            Text(drive.carDisplayString).foregroundColor(.primary)
                            Image(systemName: "pencil").font(.caption).foregroundColor(.ftBlue)
                        }
                    }
                }

                DetailRow(label: "Start Location", value: String(format: "%.4f, %.4f", drive.startLatitude, drive.startLongitude))
                DetailRow(label: "End Location",   value: String(format: "%.4f, %.4f", drive.endLatitude,   drive.endLongitude))
                if drive.stoppedTime > 0 {
                    DetailRow(label: "Stopped Time", value: formatDuration(drive.stoppedTime))
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
