import SwiftUI
import MapKit
import Combine

struct ContentView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var driveManager: DriveManager
    @ObservedObject private var settings = AppSettings.shared
    @State private var showingCarPicker = false
    @State private var showingSafetyDisclaimer = false
    @ObservedObject private var profileManager = ProfileManager.shared

    private let hasAcceptedSafetyKey = "hasAcceptedSafetyDisclaimer"

    var body: some View {
        NavigationStack {
            ZStack {
                // Always-visible map backdrop
                LiveMapView(
                    userLocation: locationManager.currentLocation?.coordinate
                        ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                    routeCoordinates: driveManager.routeCoordinates
                )
                .opacity(driveManager.isRecording ? 0.65 : 0.3)
                .ignoresSafeArea(edges: .horizontal)

                // Dim overlay on top of map
                Color.ftSurfaceBg
                    .opacity(driveManager.isRecording ? 0.15 : 0.55)

                // Instrument cluster overlay
                VStack(spacing: 0) {
                    Spacer(minLength: 60)

                    speedSection
                        .padding(.top, Spacing.xl)

                    Spacer()

                    if driveManager.isRecording, let drive = driveManager.currentDrive {
                        gaugeStrip(drive: drive)
                            .padding(.bottom, Spacing.sm)
                    }

                    controlsSection
                        .padding(.horizontal, Spacing.md)
                        .padding(.bottom, Spacing.lg)
                }
            }
            .navigationTitle("FastTrack")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(isPresented: $showingCarPicker) {
                CarSelectorView()
            }
            .alert("Safety First", isPresented: $showingSafetyDisclaimer) {
                Button("I Understand — Start Drive") {
                    UserDefaults.standard.set(true, forKey: hasAcceptedSafetyKey)
                    driveManager.startRecording()
                }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("FastTrack is designed to be used on closed courses, private roads, or as a passenger only.\n\nNever operate this app while driving on public roads. Always obey traffic laws. You are solely responsible for your safety and the safety of others.")
            }
        }
    }

    // MARK: - Speed Section

    private var speedSection: some View {
        VStack(spacing: Spacing.sm) {
            ZStack {
                GaugeArc()
                    .stroke(SpeedColor.color(for: locationManager.currentSpeed),
                            style: StrokeStyle(lineWidth: 10, lineCap: .round))
                    .frame(width: 260, height: 260)

                VStack(spacing: 2) {
                    Text("\(Int(settings.calibratedSpeedValue(locationManager.currentSpeed)))")
                        .font(.system(size: 100, weight: .bold, design: .monospaced))
                        .foregroundColor(SpeedColor.color(for: locationManager.currentSpeed))
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.2),
                                   value: Int(settings.calibratedSpeedValue(locationManager.currentSpeed)))

                    Text(settings.speedUnit.uppercased())
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Spacing.lg)
                .padding(.vertical, Spacing.sm)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Color.ftCardBg.opacity(0.9))
                )
            }

            if driveManager.isRecording {
                HStack(spacing: 4) {
                    Circle()
                        .fill(gpsStatusColor)
                        .frame(width: 8, height: 8)
                    Text(gpsStatusText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 2)
            } else {
                Text("Start a drive to see map")
                    .foregroundColor(.gray)
                    .font(.headline)
                    .padding(.top, Spacing.sm)
            }
        }
    }

    // MARK: - Gauge Strip

    private func gaugeStrip(drive: Drive) -> some View {
        HStack(spacing: Spacing.sm) {
            MetricGauge(
                title: "MAX",
                value: String(format: "%.0f", settings.speedValue(drive.maxSpeed)),
                unit: settings.speedUnit,
                color: SpeedColor.color(for: drive.maxSpeed)
            )

            MetricGauge(
                title: "AVG",
                value: String(format: "%.0f", settings.speedValue(drive.avgSpeed)),
                unit: settings.speedUnit,
                color: SpeedColor.color(for: drive.avgSpeed)
            )

            TimelineView(.periodic(from: driveManager.recordingStartTime ?? .now, by: 1)) { ctx in
                let elapsed: TimeInterval = driveManager.recordingStartTime.map {
                    ctx.date.timeIntervalSince($0)
                } ?? 0
                MetricGauge(
                    title: "TIME",
                    value: formatElapsed(max(0, elapsed)),
                    unit: "",
                    color: .ftBlue
                )
            }

            MetricGauge(
                title: "DIST",
                value: String(format: "%.1f", settings.distanceValue(drive.distance)),
                unit: settings.distanceUnit,
                color: .ftGreen
            )
        }
        .padding(.horizontal, Spacing.md)
    }

    // MARK: - Controls Section

    private var controlsSection: some View {
        VStack(spacing: Spacing.sm) {
            if let profile = profileManager.profile, !profile.garage.isEmpty {
                Button { showingCarPicker = true } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "car.fill")
                            .foregroundColor(.ftBlue)
                        Text(profile.selectedCar?.shortDisplay ?? "Select Car")
                            .fontWeight(.medium)
                        Spacer()
                    }
                    .font(.headline)
                    .foregroundColor(.primary)
                    .padding()
                }
                .disabled(driveManager.isRecording)
                .opacity(driveManager.isRecording ? 0.5 : 1)
                .frame(maxWidth: .infinity)
                .background(Color.ftCardBg)
                .cornerRadius(12)
            }

            Button {
                if driveManager.isRecording {
                    print("🛑 Stop recording button pressed")
                    driveManager.stopRecording()
                } else {
                    print("▶️ Start recording button pressed")
                    let hasAccepted = UserDefaults.standard.bool(forKey: hasAcceptedSafetyKey)
                    if hasAccepted {
                        driveManager.startRecording()
                    } else {
                        showingSafetyDisclaimer = true
                    }
                }
            } label: {
                HStack {
                    Image(systemName: driveManager.isRecording ? "stop.fill" : "play.fill")
                    Text(driveManager.isRecording ? "Stop Drive" : "Start Drive")
                }
                .font(.title2)
            }
            .buttonStyle(InstrumentButtonStyle(color: driveManager.isRecording ? .ftRed : .ftBlue))
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.red.opacity(0.6), lineWidth: 2)
                    .scaleEffect(driveManager.isRecording ? 1.05 : 1)
                    .opacity(driveManager.isRecording ? 0.6 : 0)
                    .animation(
                        driveManager.isRecording
                            ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                            : .default,
                        value: driveManager.isRecording
                    )
            )
        }
    }

    // MARK: - Helpers

    private func formatElapsed(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private var gpsStatusColor: Color {
        guard let location = locationManager.currentLocation else { return .red }
        let accuracy = location.horizontalAccuracy

        if accuracy < 0 { return .red }
        if accuracy < 5 { return .green }
        if accuracy < 10 { return .orange }
        return .red
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

        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: userLocation,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
    }

    var body: some View {
        Map(position: $cameraPosition) {
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

            if routeCoordinates.count > 1 {
                MapPolyline(coordinates: routeCoordinates)
                    .stroke(Color.blue, lineWidth: 4)
            }

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
