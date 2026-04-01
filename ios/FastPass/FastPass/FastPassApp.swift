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
    @State private var isAuthenticated = false
    
    var body: some View {
        Group {
            if isAuthenticated {
                ContentView()
                    .onAppear {
                        locationManager.requestPermission()
                    }
            } else {
                SignInView()
            }
        }
        .task {
            // Check if user is already authenticated
            isAuthenticated = AuthManager.shared.isAuthenticated()
            
            // Try to refresh token if needed
            if isAuthenticated {
                do {
                    try await AuthManager.shared.refreshTokenIfNeeded()
                } catch {
                    isAuthenticated = false
                }
            }
        }
        .onChange(of: AuthManager.shared.isAuthenticated()) { _, newValue in
            isAuthenticated = newValue
        }
    }
}
