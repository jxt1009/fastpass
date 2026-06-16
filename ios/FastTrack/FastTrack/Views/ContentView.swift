import SwiftUI
import MapKit
import Combine
import Charts

struct ContentView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var driveManager: DriveManager
    @EnvironmentObject var settings: AppSettings
    @State private var showingCarPicker = false
    @State private var showingSafetyDisclaimer = false
    @State private var showingAddCar = false
    @EnvironmentObject var profileManager: ProfileManager

    private let hasAcceptedSafetyKey = "hasAcceptedSafetyDisclaimer"
    private let recordingAccent = Color.ftAmber

    var body: some View {
        NavigationStack {
            ZStack {
                // Gradient background (behind map)
                Rectangle()
                    .fill(driveManager.isRecording ? AnyShapeStyle(Color.ftBgGradientWarm) : AnyShapeStyle(Color.ftBgGradient))
                    .ignoresSafeArea()

                // Always-visible map backdrop
                LiveMapView(
                    userLocation: locationManager.currentLocation?.coordinate
                        ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                    lastRouteCoordinate: driveManager.routeCoordinates.last,
                    useFlatElevation: driveManager.isRecording
                )
                .opacity(driveManager.isRecording ? 0.7 : 0.34)
                .ignoresSafeArea(edges: .horizontal)

                // Dim overlay on top of map
                Color.ftSurfaceBg
                    .opacity(driveManager.isRecording ? 0.18 : 0.5)

                // Instrument cluster overlay
                VStack(spacing: 0) {
                    Spacer(minLength: 60)

                    speedSection
                        .padding(.top, Spacing.xl)
                        .frame(maxWidth: .infinity)

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
            .sheet(isPresented: $showingAddCar) {
                AddCarView()
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
        VStack(spacing: 10) {
            ZStack {
                SpeedHeroRing(
                    progress: speedRingProgress,
                    diameter: 256
                )
                .frame(width: 256, height: 256)
                .accessibilityLabel("Current speed \(Int(settings.calibratedSpeedValue(locationManager.currentSpeed))) \(settings.speedUnit)")

                VStack(spacing: 4) {
                    Text("\(Int(settings.calibratedSpeedValue(locationManager.currentSpeed)))")
                        .font(FTFont.speedHero).minimumScaleFactor(0.5)
                        .foregroundColor(driveManager.isRecording ? .primary : .secondary)
                        .contentTransition(.numericText())
                        .animation(.easeInOut(duration: 0.18),
                                   value: Int(settings.calibratedSpeedValue(locationManager.currentSpeed)))

                    Text(settings.speedUnit.uppercased())
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 3)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.ftGlassCardFill)
                        )
                }
            }

            HStack(spacing: 8) {
                StatusDot(
                    level: driveManager.isRecording ? .nearBest : .typical,
                    label: driveManager.isRecording ? "Recording" : "Idle"
                )
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                StatusDot(level: gpsStatusLevel, label: gpsStatusText)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.ftGlassCardFill)
            )
        }
    }

    // MARK: - Gauge Strip

    private func gaugeStrip(drive: Drive) -> some View {
        let recentDrives = Array(driveManager.drives.prefix(10))
        return HStack(spacing: Spacing.sm) {
            TrackMetricCard(
                title: "MAX",
                value: String(format: "%.0f", settings.speedValue(drive.maxSpeed)),
                unit: settings.speedUnit,
                color: recordingAccent,
                progress: normalizedSpeedProgress(drive.maxSpeed),
                sparklineData: recentDrives.compactMap { $0.maxSpeed > 0 ? settings.speedValue($0.maxSpeed) : nil }
            )

            TrackMetricCard(
                title: "AVG",
                value: String(format: "%.0f", settings.speedValue(drive.avgSpeed)),
                unit: settings.speedUnit,
                color: .ftBlue,
                progress: normalizedSpeedProgress(drive.avgSpeed),
                sparklineData: recentDrives.compactMap { $0.avgSpeed > 0 ? settings.speedValue($0.avgSpeed) : nil }
            )

            TimelineView(.periodic(from: driveManager.recordingStartTime ?? .now, by: 1)) { ctx in
                let elapsed: TimeInterval = driveManager.recordingStartTime.map {
                    ctx.date.timeIntervalSince($0)
                } ?? 0
                TrackMetricCard(
                    title: "TIME",
                    value: formatElapsed(max(0, elapsed)),
                    unit: "",
                    color: .ftGreen,
                    progress: min(1, max(0, elapsed / 3600))
                )
            }

            TrackMetricCard(
                title: "DIST",
                value: String(format: "%.1f", settings.distanceValue(drive.distance)),
                unit: settings.distanceUnit,
                color: .ftAmber,
                progress: min(1, max(0, drive.distance / 20_000))
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
                .background(Color.ftGlassCardFill)
                .cornerRadius(Radius.lg)
            }

            if profileManager.profile?.garage.isEmpty ?? true {
                Button {
                    showingAddCar = true
                } label: {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("Add a Car to Start Driving")
                    }
                    .font(.title2)
                }
                .buttonStyle(InstrumentButtonStyle(color: .ftBlue))
            } else {
                Button {
                    if driveManager.isRecording {
                        #if DEBUG
                        print("🛑 Stop recording button pressed")
                        #endif
                        Task { await driveManager.stopRecording() }
                    } else {
                        #if DEBUG
                        print("▶️ Start recording button pressed")
                        #endif
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
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .stroke(Color.ftErrorBackground, lineWidth: 2)
                        .scaleEffect(driveManager.isRecording ? 1.05 : 1)
                        .opacity(driveManager.isRecording ? 0.6 : 0)
                        .animation(
                            driveManager.isRecording && !reduceMotion
                                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                : .default,
                            value: driveManager.isRecording
                        )
                        // Restart pulse animation when app returns to foreground.
                        .id("pulse-\(scenePhase)")
                )
                .sensoryFeedback(.impact(weight: .medium), trigger: driveManager.isRecording) { oldValue, newValue in
                    newValue
                }
            }
        }
    }

    // MARK: - Helpers

    private func formatElapsed(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        let s = Int(t) % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private var gpsStatusLevel: StatusLevel {
        guard let location = locationManager.currentLocation else { return .inactive }
        let accuracy = location.horizontalAccuracy
        if accuracy < 0 { return .inactive }
        if accuracy < 5 { return .improving }
        if accuracy < 10 { return .nearBest }
        if accuracy < 20 { return .typical }
        return .inactive
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
        guard let location = locationManager.currentLocation else {
            return driveManager.isRecording ? "Acquiring GPS..." : "GPS standby"
        }
        let accuracy = location.horizontalAccuracy

        if accuracy < 0 { return "GPS Error" }
        if accuracy < 5 { return "GPS Excellent" }
        if accuracy < 10 { return "GPS Good" }
        if accuracy < 20 { return "GPS Fair" }
        return "GPS Poor"
    }

    private var speedRingProgress: Double {
        normalizedSpeedProgress(locationManager.currentSpeed)
    }

    private func normalizedSpeedProgress(_ speed: Double) -> Double {
        min(1, max(0, speed / 55))
    }
}

private struct SpeedHeroRing: View {
    let progress: Double   // 0–1 normalized speed fraction
    let diameter: CGFloat

    private let trackGradient = AngularGradient(
        stops: [
            .init(color: .ftGreen, location: 0.0),
            .init(color: .ftGold,  location: 0.33),
            .init(color: .ftAmber, location: 0.67),
            .init(color: .ftRed,   location: 1.0)
        ],
        center: .center,
        startAngle: .degrees(0),
        endAngle: .degrees(240)
    )

    var body: some View {
        ZStack {
            // Track — 240° open arc, gap at bottom
            Circle()
                .trim(from: 0, to: 240.0/360.0)
                .stroke(Color.white.opacity(0.06), style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(150))
                .frame(width: diameter, height: diameter)

            // Value arc
            Circle()
                .trim(from: 0, to: (240.0/360.0) * progress)
                .stroke(trackGradient, style: StrokeStyle(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(150))
                .frame(width: diameter, height: diameter)
                .animation(.linear(duration: 0.1), value: progress)

            // 5 tick marks evenly spaced along the 240° arc
            ForEach(0..<5) { i in
                let angle = 150.0 + (240.0 / 4.0) * Double(i)
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1.5, height: 6)
                    .offset(y: -(diameter / 2) + 5)
                    .rotationEffect(.degrees(angle))
            }
        }
        .frame(width: diameter, height: diameter)
    }
}

private struct TrackMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    let progress: Double
    var sparklineData: [Double] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.headline, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    Text(unit.uppercased())
                        .font(FTFont.gaugeLabelCompact).minimumScaleFactor(0.7)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }

            Text(title)
                .font(FTFont.pill).minimumScaleFactor(0.7)
                .foregroundColor(.secondary)
                .lineLimit(1)

            ZStack(alignment: .leading) {
                if sparklineData.count >= 3 {
                    Chart {
                        ForEach(Array(sparklineData.enumerated()), id: \.offset) { i, v in
                            LineMark(x: .value("i", i), y: .value("v", v))
                        }
                    }
                    .chartXAxis(.hidden)
                    .chartYAxis(.hidden)
                    .foregroundStyle(color.opacity(0.70))
                }
            }
            .frame(height: 14)

            GradientProgressBar(value: progress, range: 0...max(1, 0.001), size: .compact)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
        .background(Color.ftGlassCardFill, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.ftGlassCardStroke, lineWidth: 1)
        )
    }
}


struct LiveMapView: View {
    let userLocation: CLLocationCoordinate2D
    let lastRouteCoordinate: CLLocationCoordinate2D?
    let useFlatElevation: Bool

    @State private var cameraPosition: MapCameraPosition
    @State private var regionUpdateTask: Task<Void, Never>?

    init(
        userLocation: CLLocationCoordinate2D,
        lastRouteCoordinate: CLLocationCoordinate2D?,
        useFlatElevation: Bool = false
    ) {
        self.userLocation = userLocation
        self.lastRouteCoordinate = lastRouteCoordinate
        self.useFlatElevation = useFlatElevation
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: userLocation,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
    }

    var body: some View {
        Map(position: $cameraPosition) {
            Annotation("Current location", coordinate: userLocation) {
                ZStack {
                    Circle()
                        .stroke(.white, lineWidth: 3)
                        .frame(width: 22, height: 22)
                    Circle()
                        .fill(Color.ftBlue)
                        .frame(width: 16, height: 16)
                }
            }
        }
        .mapStyle(.standard(elevation: useFlatElevation ? .flat : .realistic))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .onChange(of: userLocation) { oldValue, newValue in
            regionUpdateTask?.cancel()
            regionUpdateTask = Task {
                try? await Task.sleep(nanoseconds: 500_000_000)
                guard !Task.isCancelled else { return }
                withAnimation(.easeInOut(duration: 0.5)) {
                    cameraPosition = .region(MKCoordinateRegion(
                        center: newValue,
                        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                    ))
                }
            }
        }
    }
}

#Preview {
    let apiService = APIService()
    let authManager = AuthManager(apiService: apiService)
    apiService.authManager = authManager
    return ContentView()
        .environmentObject(LocationManager.preview())
        .environmentObject(DriveManager.preview())
        .environmentObject(AppSettings(apiService: apiService))
        .environmentObject(ProfileManager(apiService: apiService))
        .environmentObject(authManager)
}
