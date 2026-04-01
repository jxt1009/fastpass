import SwiftUI

struct DriveHistoryView: View {
    @EnvironmentObject var driveManager: DriveManager
    
    var body: some View {
        NavigationStack {
            List {
                ForEach(driveManager.drives) { drive in
                    NavigationLink(destination: DriveDetailView(drive: drive)) {
                        DriveRowView(drive: drive)
                    }
                }
            }
            .navigationTitle("Drive History")
            .navigationBarTitleDisplayMode(.large)
            .onAppear { driveManager.startPolling() }
            .onDisappear { driveManager.stopPolling() }
        }
    }
}

struct DriveRowView: View {
    let drive: Drive
    
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(drive.startTime, style: .date)
                    .font(.headline)
                Spacer()
                if !drive.carDisplayString.isEmpty && drive.carDisplayString != "Unknown Car" {
                    Text(drive.carDisplayString)
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(4)
                }
            }
            HStack {
                Label("\(Int(drive.maxSpeed * 2.23694)) mph", systemImage: "speedometer")
                Spacer()
                Label(String(format: "%.2f mi", drive.distance * 0.000621371), systemImage: "map")
                Spacer()
                Label(drive.durationString, systemImage: "clock")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    DriveHistoryView()
        .environmentObject(DriveManager.preview())
}
