//
//  FastTrackApp.swift
//  FastTrack
//
//  Created by Jameson Toper on 3/31/26.
//

import SwiftUI

@main
struct FastTrackApp: App {
    @StateObject private var locationManager: LocationManager
    @StateObject private var driveManager: DriveManager
    @StateObject private var authManager: AuthManager
    @StateObject private var settings: AppSettings
    @StateObject private var profileManager: ProfileManager
    @StateObject private var notificationsManager: NotificationsManager

    init() {
        let locMgr = LocationManager()
        let drvMgr = DriveManager()
        drvMgr.setLocationManager(locMgr)
        let authMgr = AuthManager.shared
        let appSettings = AppSettings.shared
        let profMgr = ProfileManager.shared
        let notifMgr = NotificationsManager.shared

        _locationManager = StateObject(wrappedValue: locMgr)
        _driveManager = StateObject(wrappedValue: drvMgr)
        _authManager = StateObject(wrappedValue: authMgr)
        _settings = StateObject(wrappedValue: appSettings)
        _profileManager = StateObject(wrappedValue: profMgr)
        _notificationsManager = StateObject(wrappedValue: notifMgr)
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
                }
#else
                RootView()
                    .environmentObject(locationManager)
                    .environmentObject(driveManager)
                    .environmentObject(authManager)
                    .environmentObject(settings)
                    .environmentObject(profileManager)
                    .environmentObject(notificationsManager)
#endif
            }
        }
    }
}

private let socialTabTag = 1

struct RootView: View {
    @EnvironmentObject var locationManager: LocationManager
    @EnvironmentObject var driveManager: DriveManager
    @EnvironmentObject var authManager: AuthManager
    @EnvironmentObject var settings: AppSettings
    @EnvironmentObject var profileManager: ProfileManager
    @EnvironmentObject var notificationsManager: NotificationsManager
    @Environment(\.scenePhase) private var scenePhase
    @State private var isInitializing = true
    @State private var selectedTab = 0
    @State private var showingProfileSetup = false
    /// Per-tab UUIDs. Changing a UUID causes that tab's content to be recreated (nav reset).
    /// Index 0 (Track) is intentionally never reset so active recordings survive tab switches.
    @State private var tabResetIDs = (0..<5).map { _ in UUID() }

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
            // Small minimum display time so the splash doesn't flash on fast devices
            try? await Task.sleep(nanoseconds: 800_000_000)
            isInitializing = false
        }
        .onChange(of: authManager.isAuthenticated) { _, isAuthenticated in
            if !isAuthenticated {
                Task { @MainActor in
                    driveManager.clearLocalData()
                    notificationsManager.stopPolling()
                    selectedTab = 0
                }
            }
        }
        .onChange(of: scenePhase) { _, newPhase in
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
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if authManager.isAuthenticated {
            TabView(selection: $selectedTab) {
                ContentView()
                    // Tab 0 (Track) is NOT reset — preserves active recordings across tab switches
                    .tabItem { Label("Track", systemImage: "location.fill") }.tag(0)
                SocialView()
                    // NOT reset on tab switch — leaderboard data is expensive to reload and
                    // the view manages its own nav stack; internal filter changes re-fetch via .task(id:)
                    .tabItem { Label("Social", systemImage: "person.2.fill") }.tag(socialTabTag)
                DriveHistoryView()
                    .id(tabResetIDs[2])
                    .tabItem { Label("History", systemImage: "clock.fill") }.tag(2)
                AnalyticsView()
                    .id(tabResetIDs[3])
                    .tabItem { Label("Analytics", systemImage: "chart.line.uptrend.xyaxis") }.tag(3)
                ProfileView()
                    .id(tabResetIDs[4])
                    .tabItem { Label("Profile", systemImage: "person.fill") }.tag(4)
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
                // Reset the tab being left (but never Track or Social)
                if oldTab > 0 && oldTab != socialTabTag {
                    tabResetIDs[oldTab] = UUID()
                }
            }
            .onOpenURL { url in
                // Handle deep links from Live Activity controls
                if url.scheme == "fasttrack", url.host == "stop-recording" {
                    driveManager.stopRecording()
                    selectedTab = 0  // Switch to Track tab
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
    @State private var iconScale: CGFloat = 0.7
    @State private var iconOpacity: Double = 0
    @State private var textOpacity: Double = 0
    @State private var dotOffset: CGFloat = 0

    var body: some View {
        ZStack {
            Color.ftSectionBg.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color(.systemGray5))
                        .frame(width: 110, height: 110)
                    Image(systemName: "speedometer")
                        .font(.system(size: 52, weight: .medium))
                        .foregroundStyle(.primary)
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)

                // Wordmark
                VStack(spacing: 6) {
                    Text("FastTrack")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("Every drive. Every detail.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .opacity(textOpacity)

                Spacer()

                // Loading indicator
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color(.systemGray3))
                            .frame(width: 7, height: 7)
                            .scaleEffect(dotOffset == CGFloat(i) ? 1.4 : 1.0)
                            .animation(
                                .easeInOut(duration: 0.4).repeatForever().delay(Double(i) * 0.15),
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
