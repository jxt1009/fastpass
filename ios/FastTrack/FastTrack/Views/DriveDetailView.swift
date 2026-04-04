import SwiftUI
import MapKit

// MARK: - Route data types

struct RoutePoint {
    let coordinate: CLLocationCoordinate2D
    let speed: Double    // m/s
    let timestamp: Double
}

struct RouteEvent {
    enum EventType { case brake, turnLeft, turnRight, laneChange }
    let type: EventType
    let coordinate: CLLocationCoordinate2D
    let timestamp: Double

    var icon: String {
        switch type {
        case .brake:      return "hand.raised.fill"
        case .turnLeft:   return "arrow.turn.up.left"
        case .turnRight:  return "arrow.turn.up.right"
        case .laneChange: return "arrow.left.arrow.right"
        }
    }

    var color: Color {
        switch type {
        case .brake:      return .red
        case .turnLeft, .turnRight: return .orange
        case .laneChange: return .yellow
        }
    }

    var label: String {
        switch type {
        case .brake:      return "Brake"
        case .turnLeft:   return "Left Turn"
        case .turnRight:  return "Right Turn"
        case .laneChange: return "Lane Change"
        }
    }
}

struct SpeedSegment {
    let coordinates: [CLLocationCoordinate2D]
    let speedBand: Int   // 0=slow(green) 1=medium(yellow) 2=fast(orange) 3=very fast(red)
}

// MARK: - Drive Detail View

struct DriveDetailView: View {
    let drive: Drive

    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var routePoints: [RoutePoint] = []
    @State private var routeEvents: [RouteEvent] = []
    @State private var showingCarPicker = false

    // Map expand state
    @State private var isMapExpanded = false

    // Playback state
    @State private var playbackProgress: Double = 0
    @State private var isPlaying = false
    @State private var playbackTimer: Timer?

    @ObservedObject private var settings = AppSettings.shared
    @EnvironmentObject var driveManager: DriveManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Map with route
                mapSection

                // Playback controls (only when rich route data is available)
                if !routePoints.isEmpty {
                    playbackControls
                }

                // Stats Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                    StatCard(title: "Distance", value: settings.distanceDisplay(drive.distance, decimals: 2), icon: "map")
                    StatCard(title: "Duration", value: drive.durationString, icon: "clock")
                    StatCard(title: "Max Speed", value: settings.speedDisplay(drive.maxSpeed), icon: "speedometer")
                    StatCard(title: "Avg Speed", value: settings.speedDisplay(drive.avgSpeed), icon: "gauge")
                }

                // Extended Stats Grid
                if drive.leftTurns > 0 || drive.rightTurns > 0 || drive.brakeEvents > 0 {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Driving Stats")
                            .font(.headline)

                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                            StatCard(title: "Left Turns",    value: "\(drive.leftTurns)",   icon: "arrow.turn.up.left")
                            StatCard(title: "Right Turns",   value: "\(drive.rightTurns)",  icon: "arrow.turn.up.right")
                            StatCard(title: "Brake Events",  value: "\(drive.brakeEvents)", icon: "hand.raised.fill")
                            StatCard(title: "Lane Changes",  value: "\(drive.laneChanges)", icon: "arrow.left.arrow.right")
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
                    DetailRow(label: "End Time",   value: drive.endTime.formatted(date: .long, time: .shortened))

                    // Editable car row
                    HStack {
                        Text("Car").fontWeight(.medium)
                        Spacer()
                        Button { showingCarPicker = true } label: {
                            HStack(spacing: 4) {
                                Text(drive.carDisplayString).foregroundColor(.primary)
                                Image(systemName: "pencil").font(.caption).foregroundColor(.blue)
                            }
                        }
                    }

                    DetailRow(label: "Start Location", value: String(format: "%.4f, %.4f", drive.startLatitude, drive.startLongitude))
                    DetailRow(label: "End Location",   value: String(format: "%.4f, %.4f", drive.endLatitude,   drive.endLongitude))
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
        .onDisappear { stopPlayback() }
        .sheet(isPresented: $showingCarPicker) {
            DriveCarSelectorView(drive: drive)
        }
    }

    // MARK: - Map Section

    @ViewBuilder
    private var mapSection: some View {
        if !routeCoordinates.isEmpty {
            mapContent
                .frame(height: 260)
                .cornerRadius(12)
                // Expand button overlay (top-right)
                .overlay(alignment: .topTrailing) {
                    Button {
                        isMapExpanded = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.system(size: 13, weight: .semibold))
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    }
                    .padding(10)
                }
                .fullScreenCover(isPresented: $isMapExpanded) {
                    NavigationStack {
                        mapContent
                            .ignoresSafeArea()
                            .navigationTitle("Route")
                            .navigationBarTitleDisplayMode(.inline)
                            .toolbar {
                                ToolbarItem(placement: .confirmationAction) {
                                    Button("Done") { isMapExpanded = false }
                                }
                            }
                    }
                }
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(.systemGray6))
                .frame(height: 260)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "map").font(.title2).foregroundColor(.secondary)
                        Text("No route data available").font(.subheadline).foregroundColor(.secondary)
                    }
                )
        }
    }

    /// The Map view used in both compact and full-screen contexts.
    @ViewBuilder
    private var mapContent: some View {
        Map(initialPosition: .region(regionForRoute)) {
            // Speed-colored segments when rich data is available; fall back to blue
            if !speedSegments.isEmpty {
                ForEach(Array(speedSegments.enumerated()), id: \.offset) { _, seg in
                    MapPolyline(coordinates: seg.coordinates)
                        .stroke(speedBandColor(seg.speedBand), lineWidth: 4)
                }
            } else {
                MapPolyline(coordinates: routeCoordinates).stroke(.blue, lineWidth: 3)
            }

            // Start / End markers
            Annotation("Start", coordinate: routeCoordinates.first!) {
                ZStack {
                    Circle().fill(Color.green).frame(width: 20, height: 20)
                    Image(systemName: "flag.fill").font(.system(size: 10)).foregroundColor(.white)
                }
            }
            Annotation("End", coordinate: routeCoordinates.last!) {
                ZStack {
                    Circle().fill(Color.red).frame(width: 20, height: 20)
                    Image(systemName: "flag.checkered").font(.system(size: 10)).foregroundColor(.white)
                }
            }

            // Event markers
            ForEach(Array(routeEvents.enumerated()), id: \.offset) { _, event in
                Annotation(event.label, coordinate: event.coordinate) {
                    ZStack {
                        Circle().fill(event.color.opacity(0.85)).frame(width: 22, height: 22)
                        Image(systemName: event.icon).font(.system(size: 10)).foregroundColor(.white)
                    }
                }
            }

            // Playback position marker
            if let playCoord = playbackCoordinate {
                Annotation("", coordinate: playCoord) {
                    ZStack {
                        Circle().fill(Color.blue).frame(width: 14, height: 14)
                        Circle().stroke(Color.white, lineWidth: 2).frame(width: 14, height: 14)
                    }
                }
            }
        }
    }

    // MARK: - Playback Controls

    private var playbackControls: some View {
        VStack(spacing: 10) {
            // Current stats at playback position
            HStack {
                if let pt = playbackPoint {
                    Label(settings.speedDisplay(pt.speed), systemImage: "speedometer")
                        .font(.subheadline).fontWeight(.semibold)
                    Spacer()
                    Text(playbackTimeLabel)
                        .font(.caption).foregroundColor(.secondary)
                }
            }

            // Scrubber — onEditingChanged fires only on user interaction,
            // not when the playback timer updates the value programmatically.
            Slider(value: $playbackProgress, in: 0...1, onEditingChanged: { editing in
                if editing && isPlaying { stopPlayback() }
            })
            .tint(.blue)

            // Transport controls
            HStack {
                // Seek back 10 seconds
                Button {
                    let step = 10.0 / max(drive.duration, 1)
                    playbackProgress = max(0, playbackProgress - step)
                } label: {
                    Image(systemName: "gobackward.10")
                        .foregroundColor(.primary)
                }
                Spacer()
                Button { togglePlayback() } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundColor(.blue)
                }
                Spacer()
                // Seek forward 10 seconds
                Button {
                    let step = 10.0 / max(drive.duration, 1)
                    playbackProgress = min(1, playbackProgress + step)
                } label: {
                    Image(systemName: "goforward.10")
                        .foregroundColor(.primary)
                }
            }
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(12)
    }

    // MARK: - Computed helpers

    private var speedSegments: [SpeedSegment] {
        guard !routePoints.isEmpty else { return [] }
        let maxSpeed = routePoints.map(\.speed).max() ?? 1
        guard maxSpeed > 0 else { return [] }

        var segments: [SpeedSegment] = []
        var currentCoords: [CLLocationCoordinate2D] = []
        var currentBand: Int = -1

        for point in routePoints {
            let fraction = point.speed / maxSpeed
            let band: Int
            switch fraction {
            case ..<0.25: band = 0
            case 0.25..<0.5: band = 1
            case 0.5..<0.75: band = 2
            default: band = 3
            }

            if band != currentBand {
                if currentCoords.count >= 2 {
                    segments.append(SpeedSegment(coordinates: currentCoords, speedBand: currentBand))
                }
                currentCoords = currentCoords.last.map { [$0] } ?? []
                currentBand = band
            }
            currentCoords.append(point.coordinate)
        }
        if currentCoords.count >= 2 {
            segments.append(SpeedSegment(coordinates: currentCoords, speedBand: currentBand))
        }
        return segments
    }

    private func speedBandColor(_ band: Int) -> Color {
        switch band {
        case 0: return .green
        case 1: return .yellow
        case 2: return .orange
        default: return .red
        }
    }

    private var playbackPoint: RoutePoint? {
        guard !routePoints.isEmpty else { return nil }
        let idx = Int(playbackProgress * Double(routePoints.count - 1))
        return routePoints[min(idx, routePoints.count - 1)]
    }

    private var playbackCoordinate: CLLocationCoordinate2D? {
        guard playbackProgress > 0 else { return nil }
        return playbackPoint?.coordinate
    }

    private var playbackTimeLabel: String {
        guard !routePoints.isEmpty, drive.duration > 0 else { return "" }
        let elapsed = playbackProgress * drive.duration
        let m = Int(elapsed) / 60
        let s = Int(elapsed) % 60
        return String(format: "%d:%02d", m, s)
    }

    // MARK: - Playback control

    private func togglePlayback() {
        if isPlaying { stopPlayback() } else { startPlayback() }
    }

    private func startPlayback() {
        if playbackProgress >= 1 { playbackProgress = 0 }
        isPlaying = true
        let duration = max(drive.duration, 1)
        // Playback at 4× real-time. Each tick (0.05s wall time) advances
        // 0.2s of drive time, so progress step = 0.2 / duration.
        let playbackSpeed = 4.0
        let tickInterval: TimeInterval = 0.05
        let stepSize = (tickInterval * playbackSpeed) / duration
        playbackTimer = Timer.scheduledTimer(withTimeInterval: tickInterval, repeats: true) { _ in
            DispatchQueue.main.async {
                if self.playbackProgress >= 1 {
                    self.stopPlayback()
                } else {
                    self.playbackProgress = min(1, self.playbackProgress + stepSize)
                }
            }
        }
    }

    private func stopPlayback() {
        isPlaying = false
        playbackTimer?.invalidate()
        playbackTimer = nil
    }

    // MARK: - Region

    private var regionForRoute: MKCoordinateRegion {
        guard !routeCoordinates.isEmpty else {
            return MKCoordinateRegion(
                center: CLLocationCoordinate2D(latitude: drive.startLatitude, longitude: drive.startLongitude),
                span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
            )
        }
        let lats = routeCoordinates.map(\.latitude)
        let lngs = routeCoordinates.map(\.longitude)
        let center = CLLocationCoordinate2D(latitude: (lats.min()! + lats.max()!) / 2,
                                            longitude: (lngs.min()! + lngs.max()!) / 2)
        return MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta:  max(0.001, (lats.max()! - lats.min()!) * 1.3),
                                   longitudeDelta: max(0.001, (lngs.max()! - lngs.min()!) * 1.3))
        )
    }

    // MARK: - Route parsing

    private func parseRouteData() {
        guard let routeData = drive.routeData,
              let data = routeData.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) else {
            routeCoordinates = []
            return
        }

        // v2 format: {"v":2,"points":[{lat,lng,speed,ts}],"events":[{type,lat,lng,ts}]}
        if let v2 = json as? [String: Any], (v2["v"] as? Int) == 2 {
            if let pts = v2["points"] as? [[String: Double]] {
                routePoints = pts.compactMap { d in
                    guard let lat = d["lat"], let lng = d["lng"] else { return nil }
                    return RoutePoint(coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                                      speed: d["speed"] ?? 0, timestamp: d["ts"] ?? 0)
                }
                routeCoordinates = routePoints.map(\.coordinate)
            }
            if let evts = v2["events"] as? [[String: Any]] {
                routeEvents = evts.compactMap { d in
                    guard let typeStr = d["type"] as? String,
                          let lat = d["lat"] as? Double,
                          let lng = d["lng"] as? Double else { return nil }
                    let evtType: RouteEvent.EventType
                    switch typeStr {
                    case "brake":       evtType = .brake
                    case "turn_left":   evtType = .turnLeft
                    case "turn_right":  evtType = .turnRight
                    case "lane_change": evtType = .laneChange
                    default:            return nil
                    }
                    return RouteEvent(type: evtType,
                                      coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                                      timestamp: d["ts"] as? Double ?? 0)
                }
            }
        } else if let v1 = json as? [[String: Double]] {
            // v1 format: [{lat,lng}]
            routeCoordinates = v1.compactMap { d in
                guard let lat = d["lat"], let lng = d["lng"] else { return nil }
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
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
                // Rebuild per-car stats so profile reflects the reassignment
                CarStatsManager.shared.rebuildStats(from: driveManager.drives)

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

// (Removed — using new Map API with MapPolyline and Annotation directly)

#Preview {
    NavigationStack {
        DriveDetailView(drive: Drive.example)
    }
}
