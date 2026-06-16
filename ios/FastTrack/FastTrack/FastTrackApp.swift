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
    @Environment(\.scenePhase) private var scenePhase
    @State private var isInitializing = true
    @State private var selectedTab: AppTab = .track
    @State private var showingProfileSetup = false
    @State private var tabResetIDs = (0..<4).map { _ in UUID() }

    private static let signOutLog = Logger(subsystem: "app.fasttrack", category: "signOut")

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
            // Crash breadcrumb: if the app was killed during a background
            // transition, the marker will still be set on next launch.
            if let state = UserDefaults.standard.string(forKey: "crash_bg_state") {
                print("🔴 CRASH DIAG: last bg handler reached: '\(state)'")
                UserDefaults.standard.removeObject(forKey: "crash_bg_state")
            }
            UserDefaults.standard.removeObject(forKey: "crash_bg_state")
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
                    selectedTab = .track
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
            UserDefaults.standard.set("enter_\(newPhase)", forKey: "crash_bg_state")
            UserDefaults.standard.synchronize()
            screenWake.inner.update(
                isRecording: driveManager.isRecording,
                keepScreenOn: settings.keepScreenOn,
                scenePhase: newPhase
            )
            UserDefaults.standard.set("screenWake_\(newPhase)", forKey: "crash_bg_state")
            UserDefaults.standard.synchronize()
            switch newPhase {
            case .active:
                if authManager.isAuthenticated {
                    notificationsManager.startPolling()
                }
            case .background:
                notificationsManager.stopPolling()
            default:
                break
            }
            UserDefaults.standard.set("done_\(newPhase)", forKey: "crash_bg_state")
            UserDefaults.standard.synchronize()
        }
        .onChange(of: driveManager.isRecording) { _, recording in
            screenWake.inner.update(
                isRecording: recording,
                keepScreenOn: settings.keepScreenOn,
                scenePhase: scenePhase
            )
        }
        .onChange(of: settings.keepScreenOn) { _, keep in
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
                    .tabItem { Label("Track", systemImage: "location.fill") }.tag(AppTab.track)
                GarageView()
                    .id(tabResetIDs[1])
                    .tabItem { Label("Garage", systemImage: "car.2.fill") }.tag(AppTab.garage)
                SocialView()
                    .tabItem { Label("Social", systemImage: "person.2.fill") }.tag(AppTab.social)
                ProfileView(onSwitchToGarage: { selectedTab = .garage })
                    .id(tabResetIDs[3])
                    .tabItem { Label("Profile", systemImage: "person.fill") }.tag(AppTab.profile)
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
                if oldTab == .garage || oldTab == .profile {
                    tabResetIDs[oldTab.rawValue] = UUID()
                }
            }
            .onOpenURL { url in
                if url.scheme == "fasttrack", url.host == "stop-recording" {
                    Task { await driveManager.stopRecording() }
                    selectedTab = .track
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

// MARK: - App Tab

enum AppTab: Int, CaseIterable {
    case track, garage, social, profile
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
            Rectangle()
                .fill(Color.ftBgGradient)
                .ignoresSafeArea()

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
