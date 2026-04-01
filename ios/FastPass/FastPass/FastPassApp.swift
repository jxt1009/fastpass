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
    @State private var isAuthenticated = false
    
    init() {
        let locMgr = LocationManager()
        let drvMgr = DriveManager()
        drvMgr.setLocationManager(locMgr)
        
        _locationManager = StateObject(wrappedValue: locMgr)
        _driveManager = StateObject(wrappedValue: drvMgr)
    }
    
    var body: some Scene {
        WindowGroup {
            if isAuthenticated {
                ContentView()
                    .environmentObject(locationManager)
                    .environmentObject(driveManager)
                    .onAppear {
                        locationManager.requestPermission()
                    }
            } else {
                SignInView()
            }
        }
        .onChange(of: isAuthenticated) { _, newValue in
            if newValue {
                locationManager.requestPermission()
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
    }
}
