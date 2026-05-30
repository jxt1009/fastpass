import SwiftUI
import CoreLocation

#if DEBUG
enum AppStoreScreenshotMode {
    private static let enabledFlag = "-FastTrackAppStoreScreenshots"
    private static let screenFlag = "-FastTrackScreenshotScreen"

    enum Screen: String {
        case track
        case history
        case analytics
        case profile
        case signin
        case leaderboard
        case driveoverview

        static var current: Screen {
            let args = ProcessInfo.processInfo.arguments
            guard let flagIndex = args.firstIndex(of: screenFlag), args.indices.contains(flagIndex + 1) else {
                return .track
            }
            return Screen(rawValue: args[flagIndex + 1].lowercased()) ?? .track
        }
    }

    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains(enabledFlag)
    }
}

struct AppStoreScreenshotRootView: View {
    @StateObject private var locationManager: LocationManager
    @StateObject private var driveManager: DriveManager

    init() {
        let screen = AppStoreScreenshotMode.Screen.current
        let locationManager = LocationManager.screenshotPreview()
        let driveManager = DriveManager.screenshotPreview(for: screen)
        _locationManager = StateObject(wrappedValue: locationManager)
        _driveManager = StateObject(wrappedValue: driveManager)
        seedScreenshotData(using: driveManager)
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            screenshotScreen
        }
            .environmentObject(locationManager)
            .environmentObject(driveManager)
            .environment(\.colorScheme, .dark)
            .preferredColorScheme(.dark)
    }

    @ViewBuilder
    private var screenshotScreen: some View {
        switch AppStoreScreenshotMode.Screen.current {
        case .track:
            ContentView()
        case .history:
            DriveHistoryView()
        case .analytics:
            AnalyticsView()
        case .profile:
            ProfileView()
        case .signin:
            SignInView()
                .environmentObject(AuthManager.shared)
        case .leaderboard:
            AppStoreLeaderboardScreenshotView()
        case .driveoverview:
            NavigationStack {
                DriveDetailView(drive: DriveManager.screenshotDrives[0])
            }
        }
    }

    private func seedScreenshotData(using driveManager: DriveManager) {
        let profile = UserProfile(
            username: "jamestoper",
            country: "United States",
            garage: [
                UserCar(id: "gt3", make: "Porsche", model: "911", year: 2023, trim: "GT3", nickname: "Track Car"),
                UserCar(id: "m3", make: "Tesla", model: "Model 3", year: 2024, trim: "Performance", nickname: "Daily")
            ],
            selectedCarId: "gt3",
            isPublic: true
        )

        ProfileManager.shared.profile = profile
        AchievementManager.shared.resetProgress()
        AchievementManager.shared.updateProgress(with: driveManager.drives)
        CarStatsManager.shared.clearLocalData()
        driveManager.drives.forEach { CarStatsManager.shared.updateStats(for: $0) }
    }

    private struct AppStoreLeaderboardScreenshotView: View {
        @ObservedObject private var settings = AppSettings.shared

        private let entries: [AppStoreLeaderboardEntry] = [
            AppStoreLeaderboardEntry(rank: 1, username: "apexdriver", mphValue: 82.0, trend: "up"),
            AppStoreLeaderboardEntry(rank: 2, username: "jamestoper", mphValue: 76.0, trend: "up"),
            AppStoreLeaderboardEntry(rank: 3, username: "taylorruns", mphValue: 74.0, trend: "same"),
            AppStoreLeaderboardEntry(rank: 4, username: "coastalgti", mphValue: 72.0, trend: "up"),
            AppStoreLeaderboardEntry(rank: 5, username: "nightshift", mphValue: 69.0, trend: "down")
        ]

        var body: some View {
            NavigationStack {
                ScrollView {
                    VStack(spacing: 20) {
                        HStack(spacing: 10) {
                            leaderboardPill(title: "Global", systemImage: "globe", isSelected: true)
                            leaderboardPill(title: "Month", systemImage: "calendar", isSelected: false)
                            leaderboardPill(title: "Top Speed", systemImage: "speedometer", isSelected: false)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)

                        VStack(alignment: .leading, spacing: 14) {
                            Text("Top Drivers")
                                .font(.headline)
                                .foregroundStyle(.white)

                            ForEach(entries) { entry in
                                HStack(spacing: 14) {
                                    ZStack {
                                        Circle()
                                            .fill(rankColor(entry.rank).opacity(0.22))
                                            .frame(width: 40, height: 40)
                                        Text("\(entry.rank)")
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .foregroundStyle(rankColor(entry.rank))
                                    }

                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(entry.username)
                                            .font(.headline)
                                            .foregroundStyle(.white)
                                        Text(entry.rank == 2 ? "You" : "FastTrack driver")
                                            .font(.subheadline)
                                            .foregroundStyle(.secondary)
                                    }

                                    Spacer()

                                    VStack(alignment: .trailing, spacing: 4) {
                                        Text(settings.speedDisplay(entry.mphValue / 2.23694))
                                            .font(.headline)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                        HStack(spacing: 4) {
                                            Image(systemName: trendIcon(entry.trend))
                                                .font(.caption)
                                            Text(trendLabel(entry.trend))
                                                .font(.caption)
                                        }
                                        .foregroundStyle(trendColor(entry.trend))
                                    }
                                }
                                .padding()
                                .background(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .fill(Color.white.opacity(entry.rank == 2 ? 0.12 : 0.07))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                                        .stroke(entry.rank == 2 ? Color.blue.opacity(0.5) : Color.white.opacity(0.06), lineWidth: 1)
                                )
                            }
                        }
                        .padding(20)
                        .background(
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                        )
                    }
                    .padding()
                }
                .background(
                    LinearGradient(
                        colors: [Color.black, Color(red: 0.08, green: 0.11, blue: 0.17)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .navigationTitle("Leaderboard")
                .navigationBarTitleDisplayMode(.large)
            }
        }

        private func leaderboardPill(title: String, systemImage: String, isSelected: Bool) -> some View {
            HStack(spacing: 6) {
                Image(systemName: systemImage)
                Text(title)
            }
            .font(.subheadline)
            .fontWeight(.semibold)
            .foregroundStyle(isSelected ? Color.black : Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(isSelected ? Color.white : Color.white.opacity(0.08))
            .clipShape(Capsule())
        }

        private func rankColor(_ rank: Int) -> Color {
            switch rank {
            case 1: return .yellow
            case 2: return .blue
            case 3: return .orange
            default: return .gray
            }
        }

        private func trendIcon(_ trend: String) -> String {
            switch trend {
            case "up": return "arrow.up.right"
            case "down": return "arrow.down.right"
            default: return "minus"
            }
        }

        private func trendLabel(_ trend: String) -> String {
            switch trend {
            case "up": return "Rising"
            case "down": return "Falling"
            default: return "Steady"
            }
        }

        private func trendColor(_ trend: String) -> Color {
            switch trend {
            case "up": return .green
            case "down": return .red
            default: return .secondary
            }
        }
    }

    private struct AppStoreLeaderboardEntry: Identifiable {
        let rank: Int
        let username: String
        let mphValue: Double
        let trend: String

        var id: Int { rank }
    }
}

private extension LocationManager {
    static func screenshotPreview() -> LocationManager {
        let manager = LocationManager()
        manager.currentSpeed = 17.4
        manager.rawGPSSpeed = 17.4
        manager.currentLocation = CLLocation(latitude: 37.3346, longitude: -122.0090)
        manager.authorizationStatus = .authorizedAlways
        return manager
    }
}

private extension DriveManager {
    static func screenshotPreview(for screen: AppStoreScreenshotMode.Screen) -> DriveManager {
        let manager = DriveManager()
        manager.drives = screenshotDrives
        manager.isLoadingDrives = false

        if screen == .track {
            manager.isRecording = true
            manager.recordingStartTime = Date().addingTimeInterval(-812)
            manager.routeCoordinates = [
                CLLocationCoordinate2D(latitude: 37.3320, longitude: -122.0300),
                CLLocationCoordinate2D(latitude: 37.3332, longitude: -122.0245),
                CLLocationCoordinate2D(latitude: 37.3346, longitude: -122.0185),
                CLLocationCoordinate2D(latitude: 37.3362, longitude: -122.0130),
                CLLocationCoordinate2D(latitude: 37.3384, longitude: -122.0082)
            ]
            manager.currentDrive = Drive(
                id: nil,
                userID: 1,
                startTime: Date().addingTimeInterval(-812),
                endTime: Date(),
                startLatitude: 37.3320,
                startLongitude: -122.0300,
                endLatitude: 37.3384,
                endLongitude: -122.0082,
                distance: 12420,
                duration: 812,
                maxSpeed: 25.5,
                minSpeed: 0.0,
                avgSpeed: 16.1,
                routeData: nil,
                carId: "gt3",
                carMake: "Porsche",
                carModel: "911",
                carYear: 2023,
                carTrim: "GT3",
                carNickname: "Track Car",
                stoppedTime: 38,
                leftTurns: 9,
                rightTurns: 11,
                brakeEvents: 2,
                laneChanges: 4,
                maxAcceleration: 4.2,
                maxDeceleration: 5.1,
                peakGForce: 0.88,
                topCornerSpeed: 29.8,
                best060Time: 4.1
            )
        }

        return manager
    }

    static var screenshotDrives: [Drive] {
        [
            makeDrive(
                id: 101,
                daysAgo: 1,
                distance: 18200,
                duration: 1180,
                maxSpeed: 24.1,
                avgSpeed: 15.7,
                best060: nil,
                carId: "gt3",
                carMake: "Porsche",
                carModel: "911",
                carYear: 2023,
                trim: "GT3",
                nickname: "Track Car"
            ),
            makeDrive(
                id: 102,
                daysAgo: 3,
                distance: 14600,
                duration: 980,
                maxSpeed: 22.8,
                avgSpeed: 14.8,
                best060: nil,
                carId: "gt3",
                carMake: "Porsche",
                carModel: "911",
                carYear: 2023,
                trim: "GT3",
                nickname: "Track Car"
            ),
            makeDrive(
                id: 103,
                daysAgo: 7,
                distance: 21400,
                duration: 1420,
                maxSpeed: 23.6,
                avgSpeed: 14.4,
                best060: nil,
                carId: "m3",
                carMake: "Tesla",
                carModel: "Model 3",
                carYear: 2024,
                trim: "Performance",
                nickname: "Daily"
            ),
            makeDrive(
                id: 104,
                daysAgo: 12,
                distance: 12800,
                duration: 760,
                maxSpeed: 20.6,
                avgSpeed: 13.2,
                best060: nil,
                carId: "m3",
                carMake: "Tesla",
                carModel: "Model 3",
                carYear: 2024,
                trim: "Performance",
                nickname: "Daily"
            )
        ]
    }

    static func makeDrive(
        id: Int,
        daysAgo: Int,
        distance: Double,
        duration: Double,
        maxSpeed: Double,
        avgSpeed: Double,
        best060: Double?,
        carId: String,
        carMake: String,
        carModel: String,
        carYear: Int,
        trim: String,
        nickname: String
    ) -> Drive {
        let start = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        let route = """
        {"v":2,"points":[{"lat":37.3320,"lng":-122.0300,"speed":18.2,"ts":0},{"lat":37.3340,"lng":-122.0240,"speed":31.4,"ts":120},{"lat":37.3384,"lng":-122.0082,"speed":26.8,"ts":240}],"events":[{"type":"hard_brake","lat":37.3346,"lng":-122.0185,"ts":150}]}
        """
        return Drive(
            id: id,
            userID: 1,
            startTime: start,
            endTime: start.addingTimeInterval(duration),
            startLatitude: 37.3320,
            startLongitude: -122.0300,
            endLatitude: 37.3384,
            endLongitude: -122.0082,
            distance: distance,
            duration: duration,
            maxSpeed: maxSpeed,
            minSpeed: 0.0,
            avgSpeed: avgSpeed,
            routeData: route,
            carId: carId,
            carMake: carMake,
            carModel: carModel,
            carYear: carYear,
            carTrim: trim,
            carNickname: nickname,
            stoppedTime: 42,
            leftTurns: 8 + daysAgo,
            rightTurns: 6 + daysAgo,
            brakeEvents: 2 + (daysAgo % 2),
            laneChanges: 3 + (daysAgo % 3),
            maxAcceleration: 3.8,
            maxDeceleration: 4.7,
            peakGForce: 0.81,
            topCornerSpeed: 27.2,
            best060Time: best060
        )
    }
}
#endif
