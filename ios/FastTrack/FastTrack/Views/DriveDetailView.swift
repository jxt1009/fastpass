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

// MARK: - 0-60 Attempt Display

/// Resolved view-model for a 0-60 attempt. `polylineCoordinates` is the slice
/// of the route that this attempt covers, already clipped to the available
/// route points. `midpointCoordinate` is where the speech-bubble annotation
/// is anchored.
struct ZeroToSixtyAttemptDisplay: Identifiable, Equatable {
    /// Stable identifier derived from the attempt's `endTimestamp` so
    /// SwiftUI diffing on `ForEach` doesn't redraw all attempts when the
    /// view re-runs the parser (e.g. on state changes). Falls back to a
    /// UUID only if no timestamp is available.
    let id: String
    let elapsedSeconds: Double
    let polylineCoordinates: [CLLocationCoordinate2D]
    let midpointCoordinate: CLLocationCoordinate2D
    let isPersonalBest: Bool
    let isLegacy: Bool
}

// MARK: - Drive Detail View

struct DriveDetailView: View {
    let drive: Drive

    @State private var routeCoordinates: [CLLocationCoordinate2D] = []
    @State private var routePoints: [RoutePoint] = []
    @State private var routeEvents: [RouteEvent] = []
    @State private var showingCarPicker = false

    /// 0-60 attempts parsed from `drive.zeroToSixtyAttempts` and, as a
    /// backwards-compat fallback, from any `zero_to_sixty` events embedded in
    /// the route payload. The route-polyline indices are populated from
    /// `routePoints` so the map can draw each attempt on top of the route.
    @State private var zeroToSixtyAttempts: [ZeroToSixtyAttemptDisplay] = []

    // Map expand state
    @State private var isMapExpanded = false

    // Playback state
    @State private var playbackProgress: Double = 0
    @State private var isPlaying = false
    @State private var playbackTimer: Timer?

    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @Environment(\.dismiss) private var dismiss

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

                // 0-60 attempt legend (only when attempts were captured)
                if !zeroToSixtyAttempts.isEmpty {
                    zeroToSixtyLegend
                }

                // Stats Grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
                    DashboardGauge(value: settings.speedDisplay(drive.maxSpeed), label: "Top Speed", color: .ftAmber)
                    DashboardGauge(value: settings.distanceDisplay(drive.distance, decimals: 1), label: "Distance", color: .ftBlue)
                    DashboardGauge(value: drive.durationString, label: "Duration", color: .ftBlue)
                    if let best = drive.best060Time {
                        DashboardGauge(value: String(format: "%.1fs", best), label: "0-60", color: .ftGreen)
                    } else {
                        DashboardGauge(value: settings.speedDisplay(drive.avgSpeed), label: "Avg Speed", color: .secondary)
                    }
                }

                // Extended Stats Grid
                if drive.leftTurns > 0 || drive.rightTurns > 0 || drive.brakeEvents > 0 {
                    InstrumentCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Driving Stats")
                                .font(.headline)

                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                                StatCard(title: "Left Turns",    value: "\(drive.leftTurns)",   icon: "arrow.turn.up.left",   info: StatInfo.leftTurns)
                                StatCard(title: "Right Turns",   value: "\(drive.rightTurns)",  icon: "arrow.turn.up.right",  info: StatInfo.rightTurns)
                                StatCard(title: "Brake Events",  value: "\(drive.brakeEvents)", icon: "hand.raised.fill",     info: StatInfo.brakeEvents)
                                StatCard(title: "Lane Changes",  value: "\(drive.laneChanges)", icon: "arrow.left.arrow.right", info: StatInfo.laneChanges)
                            }

                            if drive.maxAcceleration > 0 {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                                    StatCard(title: "Max Accel", value: String(format: "%.1f m/s²", drive.maxAcceleration), icon: "arrow.up.circle",   info: StatInfo.maxAcceleration)
                                    StatCard(title: "Max Decel", value: String(format: "%.1f m/s²", drive.maxDeceleration), icon: "arrow.down.circle", info: StatInfo.maxDeceleration)
                                }
                            }

                            if drive.peakGForce > 0 {
                                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 15) {
                                    StatCard(title: "Peak G-Force", value: String(format: "%.2f G", drive.peakGForce), icon: "circle.circle", info: StatInfo.peakGForce)
                                    if let best060 = drive.best060Time {
                                        StatCard(title: "0-60 Time", value: String(format: "%.1f sec", best060), icon: "timer", info: StatInfo.zeroToSixty)
                                    }
                                }
                            }
                        }
                    }
                }

                // Trip Details
                InstrumentCard {
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
                                    Image(systemName: "pencil").font(.caption).foregroundColor(.ftBlue)
                                }
                            }
                        }

                        DetailRow(label: "Start Location", value: String(format: "%.4f, %.4f", drive.startLatitude, drive.startLongitude))
                        DetailRow(label: "End Location",   value: String(format: "%.4f, %.4f", drive.endLatitude,   drive.endLongitude))
                        if drive.stoppedTime > 0 {
                            DetailRow(label: "Stopped Time", value: formatDuration(drive.stoppedTime))
                        }
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Drive Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isOwner {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .destructive) {
                        showingDeleteConfirmation = true
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(isDeleting)
                }
            }
        }
        .alert("Delete Drive?", isPresented: $showingDeleteConfirmation) {
            Button("Cancel", role: .cancel) {}
            Button(isDeleting ? "Deleting…" : "Delete", role: .destructive) {
                Task { await performDelete() }
            }
            .disabled(isDeleting)
        } message: {
            Text("This permanently removes the drive from your history. This can't be undone.")
        }
        .alert("Unable to Delete Drive", isPresented: Binding(
            get: { deleteError != nil },
            set: { if !$0 { deleteError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(deleteError ?? "Unknown error")
        }
        .onAppear {
            parseRouteData()
            parseZeroToSixtyAttempts()
        }
        .onDisappear { stopPlayback() }
        .sheet(isPresented: $showingCarPicker) {
            DriveCarSelectorView(drive: drive)
        }
    }

    private var isOwner: Bool {
        drive.userID == AuthManager.shared.getUser()?.id
    }

    // MARK: - Delete

    @MainActor
    private func performDelete() async {
        guard !isDeleting, let id = drive.id else { return }
        isDeleting = true
        defer { isDeleting = false }
        let deletedDrive = drive
        do {
            try await driveManager.deleteDrive(id: id)
            ToastManager.shared.show(ToastMessage(
                text: "Drive deleted",
                actionLabel: "Undo"
            ) {
                Task { await driveManager.restoreDrive(deletedDrive) }
            })
            dismiss()
        } catch {
            deleteError = error.localizedDescription
        }
    }

    // MARK: - Map Section

    @ViewBuilder
    private var mapSection: some View {
        if !routeCoordinates.isEmpty {
            mapContent
                .frame(height: 260)
                .cornerRadius(Radius.lg)
                // Expand button overlay (top-right)
                .overlay(alignment: .topTrailing) {
                    Button {
                        isMapExpanded = true
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right")
                            .font(.footnote.weight(.semibold)).minimumScaleFactor(0.8)
                            .padding(8)
                            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: Radius.sm))
                    }
                    .padding(10)
                }
                .fullScreenCover(isPresented: $isMapExpanded) {
                    NavigationStack {
                        ZStack(alignment: .bottom) {
                            mapContent
                                .ignoresSafeArea()
                            if !routePoints.isEmpty {
                                playbackControls
                                    .padding(.horizontal)
                                    .padding(.bottom, 12)
                                    .background(.ultraThinMaterial)
                            }
                        }
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
            RoundedRectangle(cornerRadius: Radius.lg)
                .fill(Color.ftCardBg)
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
                MapPolyline(coordinates: routeCoordinates).stroke(Color.ftBlue, lineWidth: 3)
            }

            // Start / End markers
            Annotation("Start", coordinate: routeCoordinates.first!) {
                ZStack {
                    Circle().fill(Color.ftGreen).frame(width: 20, height: 20)
                    Image(systemName: "flag.fill").font(.caption).minimumScaleFactor(0.8).foregroundColor(.white)
                }
            }
            Annotation("End", coordinate: routeCoordinates.last!) {
                ZStack {
                    Circle().fill(Color.ftRed).frame(width: 20, height: 20)
                    Image(systemName: "flag.checkered").font(.caption).minimumScaleFactor(0.8).foregroundColor(.white)
                }
            }

            // Event markers
            ForEach(Array(routeEvents.enumerated()), id: \.offset) { _, event in
                Annotation(event.label, coordinate: event.coordinate) {
                    ZStack {
                        Circle().fill(event.color.opacity(0.85)).frame(width: 22, height: 22)
                        Image(systemName: event.icon).font(.caption).minimumScaleFactor(0.8).foregroundColor(.white)
                    }
                }
            }

            // 0-60 attempt polylines + speech-bubble labels (drawn after the
            // route so the orange sits on top).
            ForEach(zeroToSixtyAttempts) { attempt in
                if attempt.polylineCoordinates.count >= 2 {
                    MapPolyline(coordinates: attempt.polylineCoordinates)
                        .stroke(Color.ftAmber, lineWidth: 6)
                }
                Annotation("", coordinate: attempt.midpointCoordinate) {
                    ZeroSixtyAttemptBubble(
                        elapsedSeconds: attempt.elapsedSeconds,
                        isPersonalBest: attempt.isPersonalBest,
                        isLegacy: attempt.isLegacy
                    )
                    .accessibilityLabel(Text("0 to 60 in \(String(format: "%.1f", attempt.elapsedSeconds)) seconds"))
                }
            }

            // Playback position marker
            if let playCoord = playbackCoordinate {
                Annotation("", coordinate: playCoord) {
                    ZStack {
                        Circle().fill(Color.ftBlue).frame(width: 14, height: 14)
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
            .tint(.ftBlue)

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
                        .foregroundColor(.ftBlue)
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
        .background(Color.ftCardBg)
        .cornerRadius(Radius.lg)
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

    /// Linearly interpolates between the two surrounding route points at the
    /// current playback position, giving smooth sub-second movement.
    private var playbackPoint: RoutePoint? {
        guard routePoints.count >= 2 else { return routePoints.first }
        let t = playbackProgress * Double(routePoints.count - 1)
        let lo = max(0, min(routePoints.count - 2, Int(t)))
        let hi = lo + 1
        let frac = t - Double(lo)

        let a = routePoints[lo]
        let b = routePoints[hi]
        return RoutePoint(
            coordinate: CLLocationCoordinate2D(
                latitude:  a.coordinate.latitude  + (b.coordinate.latitude  - a.coordinate.latitude)  * frac,
                longitude: a.coordinate.longitude + (b.coordinate.longitude - a.coordinate.longitude) * frac
            ),
            speed:     a.speed     + (b.speed     - a.speed)     * frac,
            timestamp: a.timestamp + (b.timestamp - a.timestamp) * frac
        )
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

    // MARK: - 0-60 Attempt parsing

    /// Small caption under the map explaining the orange highlight + bubble
    /// markers. Hidden when the drive has no recorded attempts.
    @ViewBuilder
    private var zeroToSixtyLegend: some View {
        HStack(spacing: 8) {
            Capsule()
                .fill(Color.ftAmber)
                .frame(width: 18, height: 4)
            Text("0-60 attempts")
                .font(.caption)
                .foregroundColor(.secondary)
            if zeroToSixtyAttempts.contains(where: { $0.isPersonalBest }) {
                Capsule()
                    .fill(Color.ftGold)
                    .frame(width: 18, height: 4)
                Text("personal best")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Text("\(zeroToSixtyAttempts.count) capture\(zeroToSixtyAttempts.count == 1 ? "" : "s")")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 4)
    }

    /// Resolves every 0-60 attempt into a display model with polyline slice +
    /// midpoint coordinate, and marks the fastest attempt in the drive as the
    /// personal best for this drive.
    private func parseZeroToSixtyAttempts() {
        var collected: [ZeroToSixtyAttempt] = []
        var seenEndTimestamps: Set<Double> = []

        // 1) New typed field — preferred
        for attempt in drive.zeroToSixtyAttempts {
            if seenEndTimestamps.insert(attempt.endTimestamp).inserted {
                collected.append(attempt)
            }
        }

        // 2) Legacy fallback: events embedded in routeData
        guard let routeData = drive.routeData,
              let data = routeData.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let v2 = json as? [String: Any],
              (v2["v"] as? Int) == 2,
              let evts = v2["events"] as? [[String: Any]] else {
            zeroToSixtyAttempts = resolvePolylines(for: collected)
            return
        }

        // Need route point index range — look it up by timestamp if available,
        // otherwise let the polyline-resolver fall back to a 0..routePoints.count-1
        // range (drawn over the whole route — still useful as a legacy marker).
        for evt in evts where (evt["type"] as? String) == "zero_to_sixty" {
            guard let startTs = evt["start_ts"] as? Double,
                  let endTs = evt["end_ts"] as? Double,
                  let elapsed = evt["elapsed_s"] as? Double else { continue }
            guard seenEndTimestamps.insert(endTs).inserted else { continue }
            let startIdx = nearestIndex(of: startTs)
            let endIdx   = max(startIdx, nearestIndex(of: endTs))
            collected.append(ZeroToSixtyAttempt(
                startIndex:     startIdx,
                endIndex:       endIdx,
                startTimestamp: startTs,
                endTimestamp:   endTs,
                elapsedSeconds: elapsed,
                startLatitude:  evt["start_lat"] as? Double ?? 0,
                startLongitude: evt["start_lng"] as? Double ?? 0,
                endLatitude:    evt["end_lat"]   as? Double ?? 0,
                endLongitude:   evt["end_lng"]   as? Double ?? 0,
                legacy:         true
            ))
        }

        zeroToSixtyAttempts = resolvePolylines(for: collected)
    }

    /// Builds the display models for the parsed attempts, including the
    /// polyline slice and a midpoint coordinate for the bubble annotation.
    private func resolvePolylines(for attempts: [ZeroToSixtyAttempt]) -> [ZeroToSixtyAttemptDisplay] {
        guard !attempts.isEmpty else { return [] }

        let fastestTime = attempts.map(\.elapsedSeconds).min() ?? .infinity

        return attempts.map { attempt in
            let coords = polylineCoordinates(for: attempt)
            let mid = midpoint(for: attempt, fallbackTo: coords)
            return ZeroToSixtyAttemptDisplay(
                id:                  String(attempt.endTimestamp),
                elapsedSeconds:      attempt.elapsedSeconds,
                polylineCoordinates: coords,
                midpointCoordinate:  mid,
                isPersonalBest:      attempt.elapsedSeconds == fastestTime,
                isLegacy:            attempt.legacy
            )
        }
    }

    /// Slice of the route polyline that this attempt covers. Uses the
    /// attempt's start/end indices when set (the live recorder stores these
    /// by design); falls back to a timestamp lookup for legacy events.
    private func polylineCoordinates(for attempt: ZeroToSixtyAttempt) -> [CLLocationCoordinate2D] {
        guard !routePoints.isEmpty else { return [] }
        let startIdx: Int
        let endIdx: Int
        if attempt.startIndex == 0 && attempt.endIndex == 0 && attempt.elapsedSeconds == 0 {
            return []
        }
        if attempt.legacy {
            // Legacy events: indices not persisted; resolve from timestamps
            startIdx = nearestIndex(of: attempt.startTimestamp)
            let end   = nearestIndex(of: attempt.endTimestamp)
            endIdx = max(startIdx, end)
        } else {
            startIdx = max(0, min(routePoints.count - 1, attempt.startIndex))
            endIdx   = max(startIdx, min(routePoints.count - 1, attempt.endIndex))
        }
        guard startIdx < endIdx else { return [] }
        return Array(routePoints[startIdx...endIdx].map(\.coordinate))
    }

    private func nearestIndex(of timestamp: TimeInterval) -> Int {
        guard !routePoints.isEmpty else { return 0 }
        var bestIdx = 0
        var bestDelta = TimeInterval.greatestFiniteMagnitude
        for (idx, pt) in routePoints.enumerated() {
            let delta = abs(pt.timestamp - timestamp)
            if delta < bestDelta {
                bestDelta = delta
                bestIdx = idx
            }
        }
        return bestIdx
    }

    private func midpoint(for attempt: ZeroToSixtyAttempt, fallbackTo coords: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D {
        if !coords.isEmpty {
            return coords[coords.count / 2]
        }
        return CLLocationCoordinate2D(
            latitude:  (attempt.startLatitude  + attempt.endLatitude)  / 2,
            longitude: (attempt.startLongitude + attempt.endLongitude) / 2
        )
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
                                                .foregroundColor(.ftBlue)
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

// MARK: - 0-60 Attempt Bubble

/// Speech-bubble annotation shown at the midpoint of a 0-60 attempt. The
/// tail always points down (the bubble is anchored above its annotation point
/// so the tail sits over the route). Background is solid orange to read
/// clearly against any map style.
struct ZeroSixtyAttemptBubble: View {
    let elapsedSeconds: Double
    let isPersonalBest: Bool
    let isLegacy: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                if isPersonalBest {
                    Image(systemName: "trophy.fill")
                        .font(FTFont.pill).minimumScaleFactor(0.7)
                }
                Text(String(format: "%.1fs", elapsedSeconds))
                    .font(.caption.weight(.bold)).minimumScaleFactor(0.8)
                    .monospacedDigit()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                SpeechBubble(cornerRadius: Radius.xs + 2, tailWidth: 8, tailHeight: 5)
                    .fill(isPersonalBest ? Color.ftPB060Tint : Color.ftAmber)
            )
            .overlay(
                SpeechBubble(cornerRadius: Radius.xs + 2, tailWidth: 8, tailHeight: 5)
                    .stroke(Color.white, lineWidth: 1)
            )
            .foregroundColor(isPersonalBest ? .black : .white)
            // The bubble is offset upward so the speech-bubble tail lands on
            // the actual coordinate of the attempt.
            .offset(y: -22)
        }
    }
}

#Preview {
    NavigationStack {
        DriveDetailView(drive: Drive.example)
    }
}
