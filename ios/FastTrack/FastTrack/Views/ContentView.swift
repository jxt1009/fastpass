import SwiftUI
import MapKit
import Combine

struct ContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var driveManager: DriveManager
    @State private var elapsedTime: TimeInterval = 0
    @State private var showingCarPicker = false
    @ObservedObject private var profileManager = ProfileManager.shared

    // 1-second ticker for live timer
    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Map
                if driveManager.isRecording {
                    LiveMapView(
                        userLocation: locationManager.currentLocation?.coordinate
                            ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                        routeCoordinates: driveManager.routeCoordinates
                    )
                    .frame(height: 300)
                    .ignoresSafeArea(edges: .top)
                } else {
                    ZStack {
                        Color.gray.opacity(0.2)
                        VStack(spacing: 12) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 50))
                                .foregroundColor(.gray)
                            Text("Start a drive to see map")
                                .foregroundColor(.gray)
                                .font(.headline)
                        }
                    }
                    .frame(height: 200)
                }

                ScrollView {
                    VStack(spacing: 20) {
                        // Speed
                        VStack {
                            Text("\(Int(locationManager.currentSpeed * 2.23694))")
                                .font(.system(size: 80, weight: .bold, design: .rounded))
                                .foregroundColor(speedColor(for: locationManager.currentSpeed))
                                .contentTransition(.numericText())
                                .animation(.easeInOut(duration: 0.2), value: Int(locationManager.currentSpeed * 2.23694))
                            Text("MPH")
                                .font(.title2)
                                .foregroundStyle(.secondary)
                            
                            // GPS status indicator during recording
                            if driveManager.isRecording {
                                HStack(spacing: 4) {
                                    Circle()
                                        .fill(gpsStatusColor)
                                        .frame(width: 8, height: 8)
                                    Text(gpsStatusText)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                .padding(.top, 4)
                            }
                        }
                        .padding()

                        // Live stats during recording
                        if driveManager.isRecording, let drive = driveManager.currentDrive {
                            VStack(spacing: 16) {
                                Text("CURRENT DRIVE")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fontWeight(.semibold)

                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                                    StatCard(
                                        title: "Time",
                                        value: formatElapsed(elapsedTime),
                                        icon: "clock.fill",
                                        color: .blue
                                    )
                                    StatCard(
                                        title: "Distance",
                                        value: String(format: "%.2f mi", drive.distance * 0.000621371),
                                        icon: "road.lanes",
                                        color: .green
                                    )
                                    StatCard(
                                        title: "Max",
                                        value: String(format: "%.0f mph", drive.maxSpeed * 2.23694),
                                        icon: "speedometer",
                                        color: .red
                                    )
                                    StatCard(
                                        title: "Min",
                                        value: String(format: "%.0f mph", drive.minSpeed * 2.23694),
                                        icon: "gauge.with.dots.needle.bottom.50percent",
                                        color: .orange
                                    )
                                    StatCard(
                                        title: "Avg",
                                        value: String(format: "%.0f mph", drive.avgSpeed * 2.23694),
                                        icon: "chart.line.uptrend.xyaxis",
                                        color: .purple
                                    )
                                    StatCard(
                                        title: "Points",
                                        value: "\(driveManager.routeCoordinates.count)",
                                        icon: "point.3.filled.connected.trianglepath.dotted",
                                        color: .cyan
                                    )
                                }
                            }
                            .padding()
                            .background(Color(.systemGray6))
                            .cornerRadius(12)
                        }

                        Spacer()

                        // Car selector
                        if let profile = profileManager.profile, !profile.garage.isEmpty {
                            VStack(spacing: 12) {
                                Text("DRIVING")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .fontWeight(.semibold)
                                
                                Button { showingCarPicker = true } label: {
                                    HStack {
                                        Image(systemName: "car.fill")
                                        Text(profile.selectedCar?.shortDisplay ?? "Select Car")
                                            .fontWeight(.medium)
                                        Spacer()
                                        Image(systemName: "chevron.right")
                                    }
                                    .font(.headline)
                                    .foregroundColor(.primary)
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(Color(.systemGray6))
                                    .cornerRadius(12)
                                }
                                .disabled(driveManager.isRecording)
                            }
                        }

                        // Record button
                        Button {
                            if driveManager.isRecording {
                                print("🛑 Stop recording button pressed")
                                driveManager.stopRecording()
                                elapsedTime = 0
                            } else {
                                print("▶️ Start recording button pressed")
                                driveManager.startRecording()
                                elapsedTime = 0
                            }
                        } label: {
                            HStack {
                                Image(systemName: driveManager.isRecording ? "stop.fill" : "play.fill")
                                Text(driveManager.isRecording ? "Stop Drive" : "Start Drive")
                                    .fontWeight(.semibold)
                            }
                            .font(.title2)
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(driveManager.isRecording ? Color.red : Color.blue)
                            .cornerRadius(12)
                        }
                    }
                    .padding()
                }
            }
            .navigationTitle("FastTrack")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingCarPicker) {
                CarSelectorView()
            }
            // Tick the live timer every second
            .onReceive(timer) { _ in
                guard driveManager.isRecording, let start = driveManager.recordingStartTime else { 
                    return 
                }
                let newElapsed = Date().timeIntervalSince(start)
                elapsedTime = newElapsed
            }
            // Snap elapsed immediately on recording state change (avoids first-tick delay)
            .onChange(of: driveManager.isRecording) { _, isRecording in
                if isRecording, let start = driveManager.recordingStartTime {
                    elapsedTime = Date().timeIntervalSince(start)
                } else {
                    elapsedTime = 0
                }
            }
        }
    }

    private func formatElapsed(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private func speedColor(for speed: Double) -> Color {
        let mph = speed * 2.23694
        if mph < 25 { return .green }
        if mph < 65 { return .orange }
        return .red
    }
    
    private var gpsStatusColor: Color {
        guard let location = locationManager.currentLocation else { return .red }
        let accuracy = location.horizontalAccuracy
        
        if accuracy < 0 { return .red }     // Invalid
        if accuracy < 5 { return .green }   // Excellent
        if accuracy < 10 { return .orange } // Good
        return .red                         // Poor
    }
    
    private var gpsStatusText: String {
        guard let location = locationManager.currentLocation else { return "Acquiring GPS..." }
        let accuracy = location.horizontalAccuracy
        
        if accuracy < 0 { return "GPS Error" }
        if accuracy < 5 { return "GPS Excellent" }
        if accuracy < 10 { return "GPS Good" }
        return "GPS Poor"
    }
}


struct LiveMapView: View {
    let userLocation: CLLocationCoordinate2D
    let routeCoordinates: [CLLocationCoordinate2D]
    
    @State private var cameraPosition: MapCameraPosition
    
    init(userLocation: CLLocationCoordinate2D, routeCoordinates: [CLLocationCoordinate2D]) {
        self.userLocation = userLocation
        self.routeCoordinates = routeCoordinates
        
        // Initialize camera to follow user
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: userLocation,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
    }
    
    var body: some View {
        Map(position: $cameraPosition) {
            // User location marker
            Annotation("", coordinate: userLocation) {
                ZStack {
                    Circle()
                        .fill(Color.blue.opacity(0.3))
                        .frame(width: 32, height: 32)
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 16, height: 16)
                }
            }
            
            // Route polyline
            if routeCoordinates.count > 1 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(Color.blue, lineWidth: 4)
            }
            
            // Start marker
            if let first = routeCoordinates.first {
                Annotation("", coordinate: first) {
                    ZStack {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 20, height: 20)
                        Image(systemName: "flag.fill")
                            .foregroundColor(.white)
                            .font(.system(size: 10))
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onChange(of: userLocation) { oldValue, newValue in
            // Update camera to follow user
            withAnimation(.easeInOut(duration: 0.5)) {
                cameraPosition = .region(MKCoordinateRegion(
                    center: newValue,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(LocationManager.preview())
        .environmentObject(DriveManager.preview())
}
