import SwiftUI

struct ContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var driveManager: DriveManager
    @State private var showingHistory = false
    
    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Speed Display
                VStack {
                    Text("\(Int(locationManager.currentSpeed * 2.23694))") // Convert m/s to mph
                        .font(.system(size: 80, weight: .bold, design: .rounded))
                    Text("MPH")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .padding()
                
                // Trip Info
                if driveManager.isRecording {
                    VStack(spacing: 10) {
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Duration")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(driveManager.currentDrive?.durationString ?? "0:00")
                                    .font(.title3)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Distance")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text(String(format: "%.2f mi", (driveManager.currentDrive?.distance ?? 0) * 0.000621371))
                                    .font(.title3)
                            }
                        }
                        
                        HStack {
                            VStack(alignment: .leading) {
                                Text("Max Speed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(Int((driveManager.currentDrive?.maxSpeed ?? 0) * 2.23694)) mph")
                                    .font(.title3)
                            }
                            Spacer()
                            VStack(alignment: .trailing) {
                                Text("Avg Speed")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                Text("\(Int((driveManager.currentDrive?.avgSpeed ?? 0) * 2.23694)) mph")
                                    .font(.title3)
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                Spacer()
                
                // Record Button
                Button(action: {
                    if driveManager.isRecording {
                        driveManager.stopRecording()
                    } else {
                        driveManager.startRecording()
                    }
                }) {
                    Text(driveManager.isRecording ? "Stop Recording" : "Start Recording")
                        .font(.title2)
                        .fontWeight(.semibold)
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(driveManager.isRecording ? Color.red : Color.blue)
                        .cornerRadius(12)
                }
                
                // History Button
                Button(action: {
                    showingHistory = true
                }) {
                    Text("View History")
                        .font(.headline)
                        .foregroundColor(.blue)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(.systemGray6))
                        .cornerRadius(12)
                }
            }
            .padding()
            .navigationTitle("FastPass")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingHistory) {
                DriveHistoryView()
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationManager())
        .environmentObject(DriveManager())
}
