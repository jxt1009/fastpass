import SwiftUI
import MapKit

// MARK: - DriveDetailMap

struct DriveDetailMap: View {
    let drive: Drive
    let routeCoordinates: [CLLocationCoordinate2D]
    let routePoints: [RoutePoint]
    let routeEvents: [RouteEvent]
    @EnvironmentObject var settings: AppSettings
    let speedSegments: [SpeedSegment]
    let topSpeedSegments: [TopSpeedSegment]
    let zeroToSixtyAttempts: [ZeroToSixtyAttemptDisplay]
    @Binding var playbackProgress: Double
    let isPlaying: Bool
    let onTogglePlayback: () -> Void
    let onStartPlayback: () -> Void
    let onStopPlayback: () -> Void
    let onSeekBack: () -> Void
    let onSeekForward: () -> Void

    @State private var isMapExpanded = false

    var body: some View {
        if !routeCoordinates.isEmpty {
            mapContent
                .frame(height: 260)
                .cornerRadius(Radius.lg)
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
                                bottomPanel
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
                .fill(Color.ftGlassCardFill)
                .frame(height: 260)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "map").font(.title2).foregroundColor(.secondary)
                        Text("No route data available").font(.subheadline).foregroundColor(.secondary)
                    }
                )
        }
    }

    @ViewBuilder
    private var mapContent: some View {
        Map(initialPosition: .region(regionForRoute)) {
            if !speedSegments.isEmpty {
                ForEach(Array(speedSegments.enumerated()), id: \.offset) { _, seg in
                    MapPolyline(coordinates: seg.coordinates)
                        .stroke(speedBandColor(seg.speedBand), lineWidth: 4)
                }
            } else {
                MapPolyline(coordinates: routeCoordinates).stroke(Color.ftBlue, lineWidth: 3)
            }

            ForEach(Array(topSpeedSegments.prefix(3).enumerated()), id: \.offset) { idx, seg in
                MapPolyline(coordinates: seg.coordinates)
                    .stroke(Color.ftGold, lineWidth: 6)
                if idx < 2 {
                Annotation("", coordinate: seg.midpointCoordinate) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.fill")
                            .font(.caption2)
                        Text(settings.speedDisplay(seg.peakSpeed))
                            .font(.caption.weight(.semibold))
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        SpeechBubble(cornerRadius: 10, tailWidth: 8, tailHeight: 5)
                            .fill(Color.ftGold)
                    )
                    .overlay(
                        SpeechBubble(cornerRadius: 10, tailWidth: 8, tailHeight: 5)
                            .stroke(Color.white, lineWidth: 1)
                    )
                    .foregroundColor(.black)
                    .offset(y: -24)
                }
                }
            }

            if let first = routeCoordinates.first {
                Annotation("Start", coordinate: first) {
                    ZStack {
                        Circle().fill(Color.ftGreen).frame(width: 20, height: 20)
                        Image(systemName: "flag.fill").font(.caption).minimumScaleFactor(0.8).foregroundColor(.white)
                    }
                }
            }
            if let last = routeCoordinates.last {
                Annotation("End", coordinate: last) {
                    ZStack {
                        Circle().fill(Color.ftRed).frame(width: 20, height: 20)
                        Image(systemName: "flag.checkered").font(.caption).minimumScaleFactor(0.8).foregroundColor(.white)
                    }
                }
            }

            ForEach(Array(routeEvents.enumerated()), id: \.offset) { _, event in
                Annotation(event.label, coordinate: event.coordinate) {
                    ZStack {
                        Circle().fill(event.color.opacity(0.85)).frame(width: 22, height: 22)
                        Image(systemName: event.icon).font(.caption).minimumScaleFactor(0.8).foregroundColor(.white)
                    }
                }
            }

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

            if let pt = playbackPoint, let playCoord = playbackCoordinate {
                Annotation("", coordinate: playCoord) {
                    VStack(spacing: 2) {
                        Text(settings.speedDisplay(pt.speed))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(
                                SpeechBubble(cornerRadius: 10, tailWidth: 8, tailHeight: 5)
                                    .fill(Color.ftBlue)
                            )
                            .overlay(
                                SpeechBubble(cornerRadius: 10, tailWidth: 8, tailHeight: 5)
                                    .stroke(Color.white, lineWidth: 1)
                            )
                            .foregroundColor(.white)
                        Circle().fill(Color.ftBlue).frame(width: 10, height: 10)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                    .offset(y: -26)
                }
            }
        }
    }

    // MARK: - Playback Controls

    private var bottomPanel: some View {
        VStack(spacing: 10) {
            gaugeStripRow
                .padding(.horizontal, 4)
            playbackControlsCompact
        }
        .padding()
        .background(Color.ftGlassCardFill)
    }

    private var gaugeStripRow: some View {
        HStack(spacing: 8) {
            VStack(spacing: 2) {
                Text(settings.speedDisplay(drive.maxSpeed))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                Text("MAX").font(.system(size: 9, weight: .semibold)).foregroundColor(.ftAmber)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 2) {
                Text(settings.speedDisplay(drive.avgSpeed))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                Text("AVG").font(.system(size: 9, weight: .semibold)).foregroundColor(.ftBlue)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 2) {
                Text(playbackTimeLabel.isEmpty ? drive.durationString : playbackTimeLabel)
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                Text("TIME").font(.system(size: 9, weight: .semibold)).foregroundColor(.ftGreen)
            }
            .frame(maxWidth: .infinity)
            VStack(spacing: 2) {
                Text(settings.distanceDisplay(drive.distance, decimals: 1))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                    .foregroundColor(.primary)
                Text("DIST").font(.system(size: 9, weight: .semibold)).foregroundColor(.ftAmber)
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var playbackControlsCompact: some View {
        VStack(spacing: 8) {
            Slider(value: $playbackProgress, in: 0...1, onEditingChanged: { editing in
                if editing && isPlaying { onStopPlayback() }
            })
            .tint(.ftBlue)

            HStack {
                Button { onSeekBack() } label: {
                    Image(systemName: "gobackward.10")
                        .foregroundColor(.primary)
                }
                Spacer()
                Button { onTogglePlayback() } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.title)
                        .foregroundColor(.ftBlue)
                }
                Spacer()
                Button { onSeekForward() } label: {
                    Image(systemName: "goforward.10")
                        .foregroundColor(.primary)
                }
            }
        }
    }

    // MARK: - Helpers

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
            span: MKCoordinateSpan(latitudeDelta: max(0.001, (lats.max()! - lats.min()!) * 1.3),
                                   longitudeDelta: max(0.001, (lngs.max()! - lngs.max()!) * 1.3))
        )
    }

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
                latitude: a.coordinate.latitude + (b.coordinate.latitude - a.coordinate.latitude) * frac,
                longitude: a.coordinate.longitude + (b.coordinate.longitude - a.coordinate.longitude) * frac
            ),
            speed: a.speed + (b.speed - a.speed) * frac,
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

    private func speedBandColor(_ band: Int) -> Color {
        switch band {
        case 0: return .green
        case 1: return .yellow
        case 2: return .orange
        default: return .red
        }
    }
}

// MARK: - 0-60 Attempt Bubble

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
            .offset(y: -22)
        }
    }
}
