import SwiftUI

struct DriveHistoryView: View {
    @EnvironmentObject var driveManager: DriveManager
    @Environment(\.dismiss) var dismiss
    
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
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .onAppear {
                driveManager.fetchDrives()
            }
        }
    }
}

struct DriveRowView: View {
    let drive: Drive
    
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(drive.startTime, style: .date)
                .font(.headline)
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
        .environmentObject(DriveManager())
}
