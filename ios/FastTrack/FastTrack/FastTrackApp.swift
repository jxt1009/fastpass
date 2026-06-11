//
//  FastTrackApp.swift
//  FastTrack
//
//  Created by Jameson Toper on 3/31/26.
//

import SwiftUI
import os

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
                    // If the user was recording when they signed out, stop
                    // the drive first so its route data is flushed to disk
                    // and the upload is attempted. The upload may still fail
                    // (no network, etc.); see the lastError log below.
                    if driveManager.isRecording {
                        await driveManager.stopRecording()
                    }
                    if let err = driveManager.lastError {
                        // The in-flight drive didn't make it to the server
                        // before sign-out. Don't block sign-out on it; the
                        // route data is on disk and will be retried on the
                        // next sign-in.
                        Self.signOutLog.error("Drive upload failed during sign-out: \(err.localizedDescription, privacy: .public)")
                    }
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
                GarageView()
                    .id(tabResetIDs[1])
                    .tabItem { Label("Garage", systemImage: "car.2.fill") }.tag(1)
                SocialView()
                    // NOT reset on tab switch — leaderboard data is expensive to reload and
                    // the view manages its own nav stack; internal filter changes re-fetch via .task(id:)
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
                // Reset the tab being left (but never Track (0) or Social (2))
                if oldTab != 0 && oldTab != 2 {
                    tabResetIDs[oldTab] = UUID()
                }
            }
            .onOpenURL { url in
                // Handle deep links from Live Activity controls
                if url.scheme == "fasttrack", url.host == "stop-recording" {
                    Task { await driveManager.stopRecording() }
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
                        .font(FTFont.appIcon).minimumScaleFactor(0.6)
                        .foregroundStyle(.primary)
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)

                // Wordmark
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
