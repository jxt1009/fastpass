import SwiftUI
import MapKit

struct DriveDetailView: View {
    let drive: Drive
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Map placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color(.systemGray6))
                    .frame(height: 200)
                    .overlay(
                        Text("Map View\n(Coming Soon)")
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.secondary)
                    )
                
                // Stats Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                    StatCard(title: "Distance", value: String(format: "%.2f mi", drive.distance * 0.000621371), icon: "map")
                    StatCard(title: "Duration", value: drive.durationString, icon: "clock")
                    StatCard(title: "Max Speed", value: "\(Int(drive.maxSpeed * 2.23694)) mph", icon: "speedometer")
                    StatCard(title: "Avg Speed", value: "\(Int(drive.avgSpeed * 2.23694)) mph", icon: "gauge")
                }
                
                // Trip Details
                VStack(alignment: .leading, spacing: 10) {
                    Text("Trip Details")
                        .font(.headline)
                    
                    DetailRow(label: "Start Time", value: drive.startTime.formatted(date: .long, time: .shortened))
                    DetailRow(label: "End Time", value: drive.endTime.formatted(date: .long, time: .shortened))
                    DetailRow(label: "Start Location", value: String(format: "%.4f, %.4f", drive.startLatitude, drive.startLongitude))
                    DetailRow(label: "End Location", value: String(format: "%.4f, %.4f", drive.endLatitude, drive.endLongitude))
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Drive Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct StatCard: View {
    let title: String
    let value: String
    let icon: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
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

#Preview {
    NavigationStack {
        DriveDetailView(drive: Drive.example)
    }
}
