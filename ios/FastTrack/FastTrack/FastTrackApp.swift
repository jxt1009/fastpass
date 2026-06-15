import SwiftUI
import os
import UIKit

@main
struct FastTrackApp: App {
    @StateObject private var locationManager: LocationManager
    @StateObject private var driveManager: DriveManager
    @StateObject private var authManager: AuthManager
    @StateObject private var settings: AppSettings
    @StateObject private var profileManager: ProfileManager
    @StateObject private var notificationsManager: NotificationsManager
    @StateObject private var carStatsManager: CarStatsManager
    @StateObject private var achievementManager: AchievementManager
    @StateObject private var apiService: APIService
    @StateObject private var screenWake: ScreenWakeControllerObservable

    init() {
        let apiService = APIService()
        let authMgr = AuthManager(apiService: apiService)
        apiService.authManager = authMgr
        let appSettings = AppSettings(apiService: apiService)
        let profMgr = ProfileManager(apiService: apiService)
        let carStatMgr = CarStatsManager(apiService: apiService)
        let achievementMgr = AchievementManager()
        let notifMgr = NotificationsManager(apiService: apiService)
        let locMgr = LocationManager()
        let drvMgr = DriveManager(
            authManager: authMgr,
            profileManager: profMgr,
            settings: appSettings,
            apiService: apiService,
            carStatsManager: carStatMgr,
            achievementManager: achievementMgr
        )
        drvMgr.setLocationManager(locMgr)
        locMgr.driveManager = drvMgr

        authMgr.profileManager = profMgr
        authMgr.carStatsManager = carStatMgr
        authMgr.achievementManager = achievementMgr
        authMgr.appSettings = appSettings
        authMgr.notificationsManager = notifMgr

        _locationManager = StateObject(wrappedValue: locMgr)
        _driveManager = StateObject(wrappedValue: drvMgr)
        _authManager = StateObject(wrappedValue: authMgr)
        _settings = StateObject(wrappedValue: appSettings)
        _profileManager = StateObject(wrappedValue: profMgr)
        _notificationsManager = StateObject(wrappedValue: notifMgr)
        _carStatsManager = StateObject(wrappedValue: carStatMgr)
        _achievementManager = StateObject(wrappedValue: achievementMgr)
        _apiService = StateObject(wrappedValue: apiService)
        _screenWake = StateObject(wrappedValue: ScreenWakeControllerObservable())
    }

    var body: some Scene {
        WindowGroup {
            Group {
#if DEBUG
                if AppStoreScreenshotMode.isEnabled {
                    AppStoreScreenshotRootView()
                } else {
                    RootView()
                        .environmentObject(locationManager)
                        .environmentObject(driveManager)
                        .environmentObject(authManager)
                        .environmentObject(settings)
                        .environmentObject(profileManager)
                        .environmentObject(notificationsManager)
                        .environmentObject(carStatsManager)
                        .environmentObject(achievementManager)
                        .environmentObject(apiService)
                        .environmentObject(screenWake)
                }
#else
                RootView()
                    .environmentObject(locationManager)
                    .environmentObject(driveManager)
                    .environmentObject(authManager)
                    .environmentObject(settings)
                    .environmentObject(profileManager)
                    .environmentObject(notificationsManager)
                    .environmentObject(carStatsManager)
                    .environmentObject(achievementManager)
                    .environmentObject(apiService)
                    .environmentObject(screenWake)
#endif
            }
            .toastOverlay()
        }
    }
}

struct RootView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var driveManager: DriveManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var notificationsManager: NotificationsManager
    @EnvironmentObject var carStatsManager: CarStatsManager
    @EnvironmentObject var achievementManager: AchievementManager
    @EnvironmentObject var apiService: APIService
    @EnvironmentObject var screenWake: ScreenWakeControllerObservable
    @State private var isInitializing = true
    @State private var selectedTab = 0
    @State private var showingProfileSetup = false
    @State private var tabResetIDs = (0..<4).map { _ in UUID() }

    private static let signOutLog = Logger(subsystem: "app.fasttrack", category: "signOut")

    private var scenePhase: ScenePhase {
        switch UIApplication.shared.applicationState {
        case .active: return .active
        case .inactive: return .inactive
        case .background: return .background
        @unknown default: return .active
        }
    }

    var body: some View {
        ZStack {
            if isInitializing {
                SplashView()
                    .transition(.opacity)
            } else {
                mainContent
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: isInitializing)
        .preferredColorScheme(settings.preferredColorScheme.colorScheme)
        .task {
            if authManager.isAuthenticated {
                do {
                    try await authManager.refreshTokenIfNeeded()
                } catch {
                    authManager.signOut()
                }
            }
            if !driveManager.isRecording {
                await driveManager.discardOrphanLiveActivities()
            }
            try? await Task.sleep(nanoseconds: 800_000_000)
            isInitializing = false
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            if !isAuthenticated {
                Task { @MainActor in
                    if driveManager.isRecording {
                        await driveManager.stopRecording()
                    }
                    if let err = driveManager.lastError {
                        Self.signOutLog.error("Drive upload failed during sign-out: \(err.localizedDescription, privacy: .public)")
                    }
                    driveManager.clearLocalData()
                    notificationsManager.stopPolling()
                    selectedTab = 0
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)) { _ in
            print("🔵🌙 willResignActive, isRecording=\(driveManager.isRecording)")
            screenWake.inner.update(
                isRecording: driveManager.isRecording,
                keepScreenOn: settings.keepScreenOn,
                scenePhase: .inactive
            )
            notificationsManager.stopPolling()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            print("🔵🌙 didBecomeActive")
            screenWake.inner.update(
                isRecording: driveManager.isRecording,
                keepScreenOn: settings.keepScreenOn,
                scenePhase: .active
            )
            if authManager.isAuthenticated {
                notificationsManager.startPolling()
            }
        }
        .onChange(of: driveManager.isRecording) { _, recording in
            print("🔵🎬 isRecording onChange: \(recording), appState=\(UIApplication.shared.applicationState.rawValue)")
            screenWake.inner.update(
                isRecording: recording,
                keepScreenOn: settings.keepScreenOn,
                scenePhase: scenePhase
            )
        }
        .onChange(of: settings.keepScreenOn) { _, keep in
            print("🔵💡 keepScreenOn onChange: \(keep)")
            screenWake.inner.update(
                isRecording: driveManager.isRecording,
                keepScreenOn: keep,
                scenePhase: scenePhase
            )
        }
        .onAppear {
            screenWake.inner.update(
                isRecording: driveManager.isRecording,
                keepScreenOn: settings.keepScreenOn,
                scenePhase: scenePhase
            )
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if authManager.isAuthenticated {
            TabView(selection: $selectedTab) {
                ContentView()
                    .tabItem { Label("Track", systemImage: "location.fill") }.tag(0)
                GarageView()
                    .id(tabResetIDs[1])
                    .tabItem { Label("Garage", systemImage: "car.2.fill") }.tag(1)
                SocialView()
                    .tabItem { Label("Social", systemImage: "person.2.fill") }.tag(2)
                ProfileView(onSwitchToGarage: { selectedTab = 1 })
                    .id(tabResetIDs[3])
                    .tabItem { Label("Profile", systemImage: "person.fill") }.tag(3)
            }
            .sheet(isPresented: $showingProfileSetup) {
                ProfileSetupView()
                    .interactiveDismissDisabled(!profileManager.isProfileComplete)
            }
            .onChange(of: authManager.isAuthenticated) { _, isAuth in
                if isAuth {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        if !profileManager.isProfileComplete {
                            showingProfileSetup = true
                        }
                    }
                    notificationsManager.startPolling()
                }
            }
            .onChange(of: selectedTab) { oldTab, _ in
                if oldTab != 0 && oldTab != 2 {
                    tabResetIDs[oldTab] = UUID()
                }
            }
            .onOpenURL { url in
                if url.scheme == "fasttrack", url.host == "stop-recording" {
                    Task { await driveManager.stopRecording() }
                    selectedTab = 0
                }
            }
            .onAppear {
                locationManager.requestPermission()
                driveManager.startPolling()
                notificationsManager.startPolling()
            }
        } else {
            SignInView()
                .environmentObject(authManager)
        }
    }
}

// MARK: - Splash Screen

struct SplashView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var iconScale: CGFloat = 0.7
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var dotOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.ftSectionBg.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 110, height: 110)
                    Image(systemName: "speedometer")
                        .font(FTFont.appIcon).minimumScaleFactor(0.6)
                        .foregroundStyle(.primary)
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)

                VStack(spacing: 6) {
                    Text("FastTrack")
                        .font(FTFont.wordmark).minimumScaleFactor(0.6)
                        .foregroundStyle(.primary)
                    Text("Every drive. Every detail.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(textOpacity)

                Spacer()

                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color(.systemGray3))
                            .frame(width: 7, height: 7)
                            .scaleEffect(dotOffset == CGFloat(i) ? 1.4 : 1.0)
                            .animation(
                                reduceMotion ? nil : .easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15),
                                value: dotOffset
                            )
                    }
                }
                .padding(.bottom, 52)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                iconScale = 1.0
                iconOpacity = 1.0
            }
            withAnimation(.easeIn(duration: 0.5).delay(0.25)) {
                textOpacity = 1.0
            }
            dotOffset = 2
        }
    }
}
