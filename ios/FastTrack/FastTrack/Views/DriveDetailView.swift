import SwiftUI
import MapKit

struct DriveDetailView: View {
    let drive: Drive
    
    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var showingCarPicker = false
    @ObservedObject private var profileManager = ProfileManager.shared
    @EnvironmentObject var driveManager: DriveManager
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Map with route
                Group {
                    if !routeCoordinates.isEmpty {
                        Map(coordinateRegion: .constant(regionForRoute), interactionModes: .all, showsUserLocation: false, annotationItems: routeAnnotations) { annotation in
                            MapAnnotation(coordinate: annotation.coordinate) {
                                Circle()
                                    .fill(annotation.isStart ? Color.green : Color.red)
                                    .frame(width: 12, height: 12)
                                    .overlay(
                                        Circle()
                                            .stroke(Color.white, lineWidth: 2)
                                    )
                            }
                        }
                        .frame(height: 200)
                        .cornerRadius(12)
                    } else {
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.systemGray6))
                            .frame(height: 200)
                            .overlay(
                                VStack(spacing: 8) {
                                    Image(systemName: "map")
                                        .font(.title2)
                                        .foregroundColor(.secondary)
                                    Text("No route data available")
                                        .font(.subheadline)
                                        .foregroundColor(.secondary)
                                }
                            )
                    }
                }
                
                // Stats Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                    StatCard(title: "Distance", value: String(format: "%.2f mi", drive.distance * 0.000621371), icon: "map")
                    StatCard(title: "Duration", value: drive.durationString, icon: "clock")
                    StatCard(title: "Max Speed", value: "\(Int(drive.maxSpeed * 2.23694)) mph", icon: "speedometer")
                    StatCard(title: "Avg Speed", value: "\(Int(drive.avgSpeed * 2.23694)) mph", icon: "gauge")
                }
                
                // Extended Stats Grid (if available)
                if drive.leftTurns > 0 || drive.rightTurns > 0 || drive.brakeEvents > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Driving Stats")
                            .font(.headline)
                        
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                            StatCard(title: "Left Turns", value: "\(drive.leftTurns)", icon: "arrow.turn.up.left")
                            StatCard(title: "Right Turns", value: "\(drive.rightTurns)", icon: "arrow.turn.up.right")
                            StatCard(title: "Brake Events", value: "\(drive.brakeEvents)", icon: "hand.raised.fill")
                            StatCard(title: "Lane Changes", value: "\(drive.laneChanges)", icon: "arrow.left.arrow.right")
                        }
                        
                        if drive.maxAcceleration > 0 {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                                StatCard(title: "Max Accel", value: String(format: "%.1f m/s²", drive.maxAcceleration), icon: "arrow.up.circle")
                                StatCard(title: "Max Decel", value: String(format: "%.1f m/s²", drive.maxDeceleration), icon: "arrow.down.circle")
                            }
                        }
                        
                        if drive.peakGForce > 0 {
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                                StatCard(title: "Peak G-Force", value: String(format: "%.2f G", drive.peakGForce), icon: "circle.circle")
                                if let best060 = drive.best060Time {
                                    StatCard(title: "0-60 Time", value: String(format: "%.1f sec", best060), icon: "timer")
                                }
                            }
                        }
                    }
                    .padding()
                    .background(Color(.systemGray6))
                    .cornerRadius(12)
                }
                
                // Trip Details
                VStack(alignment: .leading, spacing: 10) {
                    Text("Trip Details")
                        .font(.headline)
                    
                    DetailRow(label: "Start Time", value: drive.startTime.formatted(date: .long, time: .shortened))
                    DetailRow(label: "End Time", value: drive.endTime.formatted(date: .long, time: .shortened))
                    
                    // Editable car row
                    HStack {
                        Text("Car")
                            .fontWeight(.medium)
                        Spacer()
                        Button {
                            showingCarPicker = true
                        } label: {
                            HStack(spacing: 4) {
                                Text(drive.carDisplayString)
                                    .foregroundColor(.primary)
                                Image(systemName: "pencil")
                                    .font(.caption)
                                    .foregroundColor(.blue)
                            }
                        }
                    }
                    
                    DetailRow(label: "Start Location", value: String(format: "%.4f, %.4f", drive.startLatitude, drive.startLongitude))
                    DetailRow(label: "End Location", value: String(format: "%.4f, %.4f", drive.endLatitude, drive.endLongitude))
                    if drive.stoppedTime > 0 {
                        DetailRow(label: "Stopped Time", value: formatDuration(drive.stoppedTime))
                    }
                }
                .padding()
                .background(Color(.systemGray6))
                .cornerRadius(12)
            }
            .padding()
        }
        .navigationTitle("Drive Details")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { parseRouteData() }
        .sheet(isPresented: $showingCarPicker) {
            DriveCarSelectorView(drive: drive)
        }
    }
    
    // MARK: - Map Data
    
    private var regionForRoute: MKCoordinateRegion {
        guard !routeCoordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: drive.startLatitude, longitude: drive.startLongitude),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
        
        let latitudes = routeCoordinates.map(\.latitude)
        let longitudes = routeCoordinates.map(\.longitude)
        
        let minLat = latitudes.min()!
        let maxLat = latitudes.max()!
        let minLng = longitudes.min()!
        let maxLng = longitudes.max()!
        
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )
        
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.001, (maxLat - minLat) * 1.3),
            longitudeDelta: max(0.001, (maxLng - minLng) * 1.3)
        )
        
        return MKCoordinateRegion(center: center, span: span)
    }
    
    private var routeAnnotations: [RouteAnnotation] {
        guard !routeCoordinates.isEmpty else { return [] }
        return [
            RouteAnnotation(coordinate: routeCoordinates.first!, isStart: true),
            RouteAnnotation(coordinate: routeCoordinates.last!, isStart: false)
        ]
    }
    
    private func parseRouteData() {
        guard let routeData = drive.routeData,
              let data = routeData.data(using: .utf8),
              let jsonArray = try? JSONSerialization.jsonObject(with: data) as? [[String: Double]] else {
            routeCoordinates = []
            return
        }
        
        routeCoordinates = jsonArray.compactMap { point in
            guard let lat = point["lat"], let lng = point["lng"] else { return nil }
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
    }
    
    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
}

// MARK: - Drive Car Selector

struct DriveCarSelectorView: View {
    let drive: Drive
    @ObservedObject private var profileManager = ProfileManager.shared
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var driveManager: DriveManager
    
    var body: some View {
        NavigationStack {
            Group {
                if let profile = profileManager.profile, !profile.garage.isEmpty {
                    List {
                        // Current car section
                        Section("Current Car") {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(drive.carDisplayString)
                                        .font(.headline)
                                        .foregroundColor(.primary)
                                }
                                Spacer()
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        // Available cars section
                        Section("Change to") {
                            ForEach(profile.garage) { car in
                                Button {
                                    updateDriveCar(to: car)
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(car.shortDisplay)
                                                .font(.headline)
                                                .foregroundColor(.primary)
                                            Text(car.displayString)
                                                .font(.subheadline)
                                                .foregroundColor(.secondary)
                                        }
                                        Spacer()
                                        if drive.carId == car.id {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundColor(.blue)
                                        }
                                    }
                                }
                                .disabled(drive.carId == car.id)
                            }
                        }
                    }
                } else {
                    ContentUnavailableView(
                        "No Cars Available",
                        systemImage: "car",
                        description: Text("Add cars to your garage to change drive car")
                    )
                }
            }
            .navigationTitle("Change Car")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
    
    private func updateDriveCar(to car: UserCar) {
        guard let driveId = drive.id else { return }
        Task {
            do {
                let updatedDrive = try await APIService.shared.updateDriveCarAssignment(driveId: driveId, car: car)

                if let index = driveManager.drives.firstIndex(where: { $0.id == drive.id }) {
                    driveManager.drives[index] = updatedDrive
                }

                await MainActor.run {
                    dismiss()
                }
            } catch {
                print("Failed to update drive car: \(error)")
                if case APIError.serverError(let code) = error {
                    print("Server returned status code: \(code)")
                }
                await MainActor.run {
                    dismiss()
                }
            }
        }
    }
}

// MARK: - Route Annotation

private struct RouteAnnotation: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
    let isStart: Bool
}

#Preview {
    NavigationStack {
        DriveDetailView(drive: Drive.example)
    }
}
