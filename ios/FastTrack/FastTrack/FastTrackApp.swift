//
//  FastTrackApp.swift
//  FastTrack
//
//  Created by Jameson Toper on 3/31/26.
//

import SwiftUI

@main
struct FastTrackApp: App {
    @StateObject private var locationManager = LocationManager()
    @StateObject private var driveManager: DriveManager
    
    init() {
        let locMgr = LocationManager()
        let drvMgr = DriveManager()
        drvMgr.setLocationManager(locMgr)
        
        _locationManager = StateObject(wrappedValue: locMgr)
        _driveManager = StateObject(wrappedValue: drvMgr)
    }
    
    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(locationManager)
                .environmentObject(driveManager)
        }
    }
}

struct RootView: View {
    @EnvironmentObject var locationManager: LocationManager
    @ObservedObject private var authManager = AuthManager.shared
    @ObservedObject private var settings = AppSettings.shared
    @State private var isInitializing = true
    @State private var selectedTab = 0
    /// Per-tab UUIDs. Changing a UUID causes that tab's content to be recreated (nav reset).
    /// Index 0 (Track) is intentionally never reset so active recordings survive tab switches.
    @State private var tabResetIDs = (0..<6).map { _ in UUID() }

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
                    try await AuthManager.shared.refreshTokenIfNeeded()
                } catch {
                    AuthManager.shared.clearTokens()
                }
            }
            // Small minimum display time so the splash doesn't flash on fast devices
            try? await Task.sleep(nanoseconds: 800_000_000)
            isInitializing = false
        }
    }

    @ViewBuilder
    private var mainContent: some View {
        if authManager.isAuthenticated {
            TabView(selection: $selectedTab) {
                ContentView()
                    // Tab 0 (Track) is NOT reset — preserves active recordings across tab switches
                    .tabItem { Label("Track", systemImage: "location.fill") }.tag(0)
                DriveHistoryView()
                    .id(tabResetIDs[1])
                    .tabItem { Label("History", systemImage: "clock.fill") }.tag(1)
                AnalyticsView()
                    .id(tabResetIDs[2])
                    .tabItem { Label("Analytics", systemImage: "chart.line.uptrend.xyaxis") }.tag(2)
                SocialView()
                    .id(tabResetIDs[3])
                    .tabItem { Label("Social", systemImage: "person.2.fill") }.tag(3)
                AchievementsView()
                    .id(tabResetIDs[4])
                    .tabItem { Label("Achievements", systemImage: "trophy.fill") }.tag(4)
                ProfileView()
                    .id(tabResetIDs[5])
                    .tabItem { Label("Profile", systemImage: "person.fill") }.tag(5)
            }
            .onChange(of: selectedTab) { oldTab, _ in
                // Reset the tab being left (but never the Track tab)
                if oldTab > 0 {
                    tabResetIDs[oldTab] = UUID()
                }
            }
            .onAppear { locationManager.requestPermission() }
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
            Color.black.ignoresSafeArea()

            VStack(spacing: 24) {
                Spacer()

                // Icon
                ZStack {
                    Circle()
                        .fill(Color(white: 0.12))
                        .frame(width: 110, height: 110)
                    Image(systemName: "speedometer")
                        .font(.system(size: 52, weight: .medium))
                        .foregroundStyle(.white)
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)

                // Wordmark
                VStack(spacing: 6) {
                    Text("FastTrack")
                        .font(.system(size: 36, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                    Text("Every drive. Every detail.")
                        .font(.subheadline)
                        .foregroundStyle(Color(white: 0.5))
                }
                .opacity(textOpacity)

                Spacer()

                // Loading indicator
                HStack(spacing: 6) {
                    ForEach(0..<3) { i in
                        Circle()
                            .fill(Color(white: 0.4))
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
