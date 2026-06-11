import SwiftUI
import MapKit
import Combine

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
    private let idleAccent = Color.ftBlue

    var body: some View {
        NavigationStack {
            ZStack {
                // Always-visible map backdrop
                LiveMapView(
                    userLocation: locationManager.currentLocation?.coordinate
                        ?? CLLocationCoordinate2D(latitude: 37.7749, longitude: -122.4194),
                    routeCoordinates: driveManager.routeCoordinates,
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
                    tint: driveManager.isRecording ? recordingAccent : idleAccent,
                    isRecording: driveManager.isRecording
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
                                .fill(Color.ftCardBg.opacity(0.92))
                        )
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(gpsStatusColor)
                    .frame(width: 7, height: 7)
                    .accessibilityLabel("GPS: \(gpsStatusText)")
                Text(driveManager.isRecording ? "Recording" : "Idle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(driveManager.isRecording ? recordingAccent : .secondary)
                Text("•")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text(gpsStatusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.ftCardBg.opacity(0.9))
            )
        }
    }

    // MARK: - Gauge Strip

    private func gaugeStrip(drive: Drive) -> some View {
        HStack(spacing: Spacing.sm) {
            TrackMetricCard(
                title: "MAX",
                value: String(format: "%.0f", settings.speedValue(drive.maxSpeed)),
                unit: settings.speedUnit,
                color: recordingAccent,
                progress: normalizedSpeedProgress(drive.maxSpeed)
            )

            TrackMetricCard(
                title: "AVG",
                value: String(format: "%.0f", settings.speedValue(drive.avgSpeed)),
                unit: settings.speedUnit,
                color: .ftBlue,
                progress: normalizedSpeedProgress(drive.avgSpeed)
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
                .background(Color.ftCardBg)
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
                        print("🛑 Stop recording button pressed")
                        Task { await driveManager.stopRecording() }
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
                    RoundedRectangle(cornerRadius: Radius.lg)
                        .stroke(Color.ftErrorBackground, lineWidth: 2)
                        .scaleEffect(driveManager.isRecording ? 1.05 : 1)
                        .opacity(driveManager.isRecording ? 0.6 : 0)
                        .animation(
                            driveManager.isRecording && !reduceMotion && scenePhase == .active
                                ? .easeInOut(duration: 0.8).repeatForever(autoreverses: true)
                                : .default,
                            value: driveManager.isRecording
                        )
                        .id("pulse-\(scenePhase)")
                )
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
    let progress: Double
    let tint: Color
    let isRecording: Bool

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.ftHairline, lineWidth: 16)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(
                    LinearGradient(
                        colors: [tint.opacity(0.35), tint],
                        startPoint: .leading,
                        endPoint: .trailing
                    ),
                    style: StrokeStyle(lineWidth: 16, lineCap: .round)
                )
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.2), value: progress)

            Circle()
                .fill(Color.ftCardBg.opacity(isRecording ? 0.5 : 0.7))
                .padding(24)
        }
    }
}

private struct TrackMetricCard: View {
    let title: String
    let value: String
    let unit: String
    let color: Color
    let progress: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .lastTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(.headline, design: .monospaced))
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                if !unit.isEmpty {
                    Text(unit.uppercased())
                        .font(FTFont.gaugeLabelCompact).minimumScaleFactor(0.7)
                        .foregroundColor(.secondary)
                }
            }

            Text(title)
                .font(FTFont.pill).minimumScaleFactor(0.7)
                .foregroundColor(.secondary)

            GeometryReader { proxy in
                RoundedRectangle(cornerRadius: Radius.xxs, style: .continuous)
                    .fill(color.opacity(0.22))
                    .overlay(alignment: .leading) {
                        RoundedRectangle(cornerRadius: Radius.xxs, style: .continuous)
                            .fill(color)
                            .frame(width: proxy.size.width * min(1, max(0, progress)))
                            .animation(.easeInOut(duration: 0.2), value: progress)
                    }
            }
            .frame(height: 4)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 9)
        .padding(.horizontal, 8)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Radius.md, style: .continuous)
                .stroke(Color.ftOnDarkDivider, lineWidth: 1)
        )
    }
}


struct LiveMapView: View {
    let userLocation: CLLocationCoordinate2D
    let routeCoordinates: [CLLocationCoordinate2D]
    let useFlatElevation: Bool

    @State private var cameraPosition: MapCameraPosition
    @State private var cachedDecimated: [CLLocationCoordinate2D] = []
    @State private var cachedInputCount: Int = 0

    init(
        userLocation: CLLocationCoordinate2D,
        routeCoordinates: [CLLocationCoordinate2D],
        useFlatElevation: Bool = false
    ) {
        self.userLocation = userLocation
        self.routeCoordinates = routeCoordinates
        self.useFlatElevation = useFlatElevation
        _cameraPosition = State(initialValue: .region(MKCoordinateRegion(
            center: userLocation,
            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
        )))
        let initial = routeCoordinates.count <= 500
            ? routeCoordinates
            : RouteDecimator.decimate(routeCoordinates, toleranceMeters: 5, maxOutput: 500)
        _cachedDecimated = State(initialValue: initial)
        _cachedInputCount = State(initialValue: routeCoordinates.count)
    }

    /// Recompute the decimated polyline only when the input has
    /// changed by a meaningful amount (≥10 new points). During
    /// recording, `routeCoordinates` updates ~1 Hz, so this drops
    /// the per-tick RDP pass from O(n log n) to O(1) in steady state.
    private func recomputeDecimationIfNeeded() {
        let count = routeCoordinates.count
        if count == cachedInputCount { return }
        if count > cachedInputCount && count - cachedInputCount < 10 { return }
        cachedDecimated = count <= 500
            ? routeCoordinates
            : RouteDecimator.decimate(routeCoordinates, toleranceMeters: 5, maxOutput: 500)
        cachedInputCount = count
    }

    var body: some View {
        recomputeDecimationIfNeeded()
        return Map(position: $cameraPosition) {
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

            let coords = cachedDecimated
            if coords.count > 1 {
                MapPolyline(coordinates: coords)
                    .stroke(Color.ftAmber, lineWidth: 4)
            }

            if let first = routeCoordinates.first {
                Annotation("Route start", coordinate: first) {
                    Image(systemName: "flag.checkered")
                        .foregroundColor(.ftGreen)
                        .font(FTFont.subtitleBold).minimumScaleFactor(0.6)
                        .accessibilityLabel("Route start")
                }
            }
        }
        .mapStyle(.standard(elevation: useFlatElevation ? .flat : .realistic))
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
        .environmentObject(AppSettings.shared)
        .environmentObject(ProfileManager.shared)
}
