//
//  FastPassApp.swift
//  FastPass
//
//  Created by Jameson Toper on 3/31/26.
//

import SwiftUI

@main
struct FastPassApp: App {
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

    var body: some View {
        Group {
            if authManager.isAuthenticated {
                ContentView()
                    .onAppear { locationManager.requestPermission() }
            } else {
                SignInView()
                    .environmentObject(authManager)
            }
        }
        .task {
            guard authManager.isAuthenticated else { return }
            do {
                try await AuthManager.shared.refreshTokenIfNeeded()
            } catch {
                AuthManager.shared.clearTokens()
            }
        }
    }
}
