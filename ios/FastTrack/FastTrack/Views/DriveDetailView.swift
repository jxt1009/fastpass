import SwiftUI
import MapKit

// MARK: - Route data types

struct RoutePoint {
    let coordinate: CLLocationCoordinate2D
    let speed: Double
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
    let speedBand: Int
}

// MARK: - 0-60 Attempt Display

struct ZeroToSixtyAttemptDisplay: Identifiable, Equatable {
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
    @State private var routePointTimestamps: [TimeInterval] = []
    @State private var showingCarPicker = false
    @State private var zeroToSixtyAttempts: [ZeroToSixtyAttemptDisplay] = []
    @State private var playbackProgress: Double = 0
    @State private var isPlaying = false
    @State private var playbackTimer: Timer?
    @State private var showingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var deleteError: String?
    @Environment(\.dismiss) private var dismiss

    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var driveManager: DriveManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var carStatsManager: CarStatsManager

    private var isOwner: Bool {
        drive.userID == authManager.getUser()?.id
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                DriveDetailMap(
                    drive: drive,
                    routeCoordinates: routeCoordinates,
                    routePoints: routePoints,
                    routeEvents: routeEvents,
                    speedSegments: speedSegments,
                    zeroToSixtyAttempts: zeroToSixtyAttempts,
                    playbackProgress: $playbackProgress,
                    isPlaying: isPlaying,
                    onTogglePlayback: togglePlayback,
                    onStartPlayback: startPlayback,
                    onStopPlayback: stopPlayback,
                    onSeekBack: seekBack,
                    onSeekForward: seekForward
                )

                if !routePoints.isEmpty {
                    DriveDetailAttemptsList(zeroToSixtyAttempts: zeroToSixtyAttempts)
                }

                DriveDetailGauges(drive: drive, settings: settings)

                DriveDetailTripCard(
                    drive: drive,
                    onTapCarPicker: { showingCarPicker = true }
                )
            }
            .padding()
        }
        .navigationTitle("Drive Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                DriveDetailActions(
                    isOwner: isOwner,
                    isDeleting: isDeleting,
                    onDelete: { showingDeleteConfirmation = true }
                )
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
        }
        .onDisappear { stopPlayback() }
        .sheet(isPresented: $showingCarPicker) {
            DriveCarSelectorView(drive: drive)
        }
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

    // MARK: - Speed Segments

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

    // MARK: - Playback control

    private func togglePlayback() {
        if isPlaying { stopPlayback() } else { startPlayback() }
    }

    private func startPlayback() {
        if playbackProgress >= 1 { playbackProgress = 0 }
        isPlaying = true
        let duration = max(drive.duration, 1)
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

    private func seekBack() {
        let step = 10.0 / max(drive.duration, 1)
        playbackProgress = max(0, playbackProgress - step)
    }

    private func seekForward() {
        let step = 10.0 / max(drive.duration, 1)
        playbackProgress = min(1, playbackProgress + step)
    }

    // MARK: - Route parsing

struct RouteParseResult: Sendable {
    let rawCoordinates: [(lat: Double, lng: Double)]
    let rawPoints: [(lat: Double, lng: Double, speed: Double, ts: Double)]
    let rawEvents: [(type: String, lat: Double, lng: Double, ts: Double)]
}

private func parseRouteDataFromString(_ routeData: String) -> RouteParseResult {
    guard let data = routeData.data(using: .utf8),
          let json = try? JSONSerialization.jsonObject(with: data) else {
        return RouteParseResult(rawCoordinates: [], rawPoints: [], rawEvents: [])
    }

    if let v2 = json as? [String: Any], (v2["v"] as? Int) == 2 {
        var rawPoints: [(lat: Double, lng: Double, speed: Double, ts: Double)] = []
        if let pts = v2["points"] as? [[String: Double]] {
            rawPoints = pts.compactMap { d in
                guard let lat = d["lat"], let lng = d["lng"] else { return nil }
                return (lat: lat, lng: lng, speed: d["speed"] ?? 0, ts: d["ts"] ?? 0)
            }
        }
        var rawEvents: [(type: String, lat: Double, lng: Double, ts: Double)] = []
        if let evts = v2["events"] as? [[String: Any]] {
            rawEvents = evts.compactMap { d in
                guard let typeStr = d["type"] as? String,
                      let lat = d["lat"] as? Double,
                      let lng = d["lng"] as? Double else { return nil }
                return (type: typeStr, lat: lat, lng: lng, ts: d["ts"] as? Double ?? 0)
            }
        }
        let rawCoords = rawPoints.map { (lat: $0.lat, lng: $0.lng) }
        return RouteParseResult(rawCoordinates: rawCoords, rawPoints: rawPoints, rawEvents: rawEvents)
    } else if let v1 = json as? [[String: Double]] {
        let rawCoords = v1.compactMap { d -> (lat: Double, lng: Double)? in
            guard let lat = d["lat"], let lng = d["lng"] else { return nil }
            return (lat: lat, lng: lng)
        }
        return RouteParseResult(rawCoordinates: rawCoords, rawPoints: [], rawEvents: [])
    }
    return RouteParseResult(rawCoordinates: [], rawPoints: [], rawEvents: [])
}

    private func parseRouteData() {
        guard let routeData = drive.routeData else { return }
        let routeCoordinatesCopy = routeCoordinates

        Task.detached(priority: .userInitiated) {
            let result = parseRouteDataFromString(routeData)
            await MainActor.run {
                let mappedPoints = result.rawPoints.map {
                    RoutePoint(coordinate: CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng),
                               speed: $0.speed, timestamp: $0.ts)
                }
                self.routeCoordinates = result.rawCoordinates.map {
                    CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
                }
                self.routePoints = mappedPoints
                self.routePointTimestamps = mappedPoints.map(\.timestamp)
                self.routeEvents = result.rawEvents.compactMap { raw -> RouteEvent? in
                    let evtType: RouteEvent.EventType
                    switch raw.type {
                    case "brake":       evtType = .brake
                    case "turn_left":   evtType = .turnLeft
                    case "turn_right":  evtType = .turnRight
                    case "lane_change": evtType = .laneChange
                    default:            return nil
                    }
                    return RouteEvent(type: evtType,
                                      coordinate: CLLocationCoordinate2D(latitude: raw.lat, longitude: raw.lng),
                                      timestamp: raw.ts)
                }
                self.parseZeroToSixtyAttempts()
                _ = routeCoordinatesCopy
            }
        }
    }

    // MARK: - 0-60 Attempt parsing

    private func parseZeroToSixtyAttempts() {
        var collected: [ZeroToSixtyAttempt] = []
        var seenEndTimestamps: Set<Double> = []

        for attempt in drive.zeroToSixtyAttempts {
            if seenEndTimestamps.insert(attempt.endTimestamp).inserted {
                collected.append(attempt)
            }
        }

        guard let routeData = drive.routeData,
              let data = routeData.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let v2 = json as? [String: Any],
              (v2["v"] as? Int) == 2,
              let evts = v2["events"] as? [[String: Any]] else {
            zeroToSixtyAttempts = resolvePolylines(for: collected)
            return
        }

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

    private func polylineCoordinates(for attempt: ZeroToSixtyAttempt) -> [CLLocationCoordinate2D] {
        guard !routePoints.isEmpty else { return [] }
        if attempt.startIndex == 0 && attempt.endIndex == 0 && attempt.elapsedSeconds == 0 {
            return []
        }
        let startIdx: Int
        let endIdx: Int
        if attempt.legacy {
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
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var apiService: APIService
    @EnvironmentObject var carStatsManager: CarStatsManager
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject var driveManager: DriveManager

    var body: some View {
        NavigationStack {
            Group {
                if let profile = profileManager.profile, !profile.garage.isEmpty {
                    List {
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
                let updatedDrive = try await apiService.updateDriveCarAssignment(driveId: driveId, car: car)

                if let index = driveManager.drives.firstIndex(where: { $0.id == drive.id }) {
                    driveManager.drives[index] = updatedDrive
                }
                carStatsManager.rebuildStats(from: driveManager.drives)


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
