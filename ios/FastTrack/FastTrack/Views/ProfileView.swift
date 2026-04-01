import SwiftUI

// MARK: - Dark Card Wrapper

private struct DarkCard<Content: View>: View {
    @ViewBuilder let content: Content
    var body: some View {
        content
            .padding()
            .background(Color(red: 0.17, green: 0.17, blue: 0.18))
            .cornerRadius(12)
    }
}

// MARK: - Profile Stat Cell (matches screenshot style)

private struct ProfileStatCell: View {
    let icon: String
    let iconColor: Color
    let label: String
    let value: String
    let unit: String

    var body: some View {
        DarkCard {
            VStack(alignment: .leading, spacing: 6) {
                Image(systemName: icon)
                    .foregroundColor(iconColor)
                    .font(.title3)
                Text(label)
                    .font(.caption)
                    .foregroundColor(Color(white: 0.6))
                HStack(alignment: .lastTextBaseline, spacing: 3) {
                    Text(value)
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    if !unit.isEmpty {
                        Text(unit)
                            .font(.caption)
                            .foregroundColor(Color(white: 0.5))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Turn Preference Bar

private struct TurnPreferenceBar: View {
    let leftFraction: Double  // 0–1

    var leftPct: Int { Int(leftFraction * 100) }
    var rightPct: Int { 100 - leftPct }

    var body: some View {
        DarkCard {
            VStack(alignment: .leading, spacing: 12) {
                Text("Turn Preference")
                    .font(.headline)
                    .foregroundColor(.white)
                GeometryReader { geo in
                    HStack(spacing: 2) {
                        Rectangle()
                            .fill(Color.blue)
                            .frame(width: max(geo.size.width * leftFraction, 4))
                        Rectangle()
                            .fill(Color.pink)
                    }
                    .cornerRadius(4)
                }
                .frame(height: 28)
                HStack {
                    Text("\(leftPct)%")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.blue)
                    Text("Left")
                        .font(.caption).foregroundColor(Color(white: 0.5))
                    Spacer()
                    Text("Right")
                        .font(.caption).foregroundColor(Color(white: 0.5))
                    Text("\(rightPct)%")
                        .font(.subheadline).fontWeight(.semibold)
                        .foregroundColor(.pink)
                }
            }
        }
    }
}

// MARK: - Section Header

private struct DarkSectionHeader: View {
    let title: String
    var body: some View {
        Text(title)
            .font(.title3).fontWeight(.bold)
            .foregroundColor(.white)
            .padding(.top, 8)
    }
}

// MARK: - Main Profile View

struct ProfileView: View {
    @StateObject private var profileManager = ProfileManager.shared
    @EnvironmentObject var driveManager: DriveManager
    @EnvironmentObject var locationManager: LocationManager
    @State private var showingSetup = false
    @State private var showingAddCar = false

    private var stats: UserStats {
        UserStats.from(drives: driveManager.drives)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        profileHeader
                        garageSection
                        mainStatsGrid
                        topSpeedCard
                        best060Card
                        DarkSectionHeader(title: "Maneuvers")
                        maneuvorsGrid
                        TurnPreferenceBar(leftFraction: stats.turnPreferencePct)
                        DarkSectionHeader(title: "Performance")
                        performanceGrid
                        DarkSectionHeader(title: "More Stats")
                        moreStatsGrid
                        signOutButton
                    }
                    .padding()
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showingSetup = true
                    } label: {
                        Image(systemName: "pencil.circle")
                            .foregroundColor(.white)
                    }
                }
            }
            .sheet(isPresented: $showingSetup) {
                ProfileSetupView()
            }
            .sheet(isPresented: $showingAddCar) {
                AddCarView()
            }
            .onAppear {
                if !profileManager.isProfileComplete {
                    showingSetup = true
                }
                driveManager.fetchDrives()
            }
        }
    }

    // MARK: Profile Header

    private var profileHeader: some View {
        DarkCard {
            HStack(spacing: 14) {
                // Avatar
                ZStack {
                    if let img = profileManager.profileImage {
                        Image(uiImage: img)
                            .resizable()
                            .scaledToFill()
                            .frame(width: 56, height: 56)
                            .clipShape(Circle())
                    } else {
                        Circle()
                            .fill(Color.blue.opacity(0.3))
                            .frame(width: 56, height: 56)
                        Image(systemName: "person.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(profileManager.profile?.username ?? "Set up profile")
                        .font(.title3).fontWeight(.bold)
                        .foregroundColor(.white)
                    let subtitle = [
                        profileManager.profile?.country,
                        profileManager.profile.flatMap { p in
                            p.carMake.isEmpty ? nil : p.carDisplayString
                        }
                    ].compactMap { $0 }.joined(separator: " · ")
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundColor(Color(white: 0.55))
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(Int(locationManager.currentSpeed * 2.23694))")
                        .font(.title2).fontWeight(.bold)
                        .foregroundColor(.white)
                    Text("mph")
                        .font(.caption2)
                        .foregroundColor(Color(white: 0.5))
                }
            }
        }
    }

    // MARK: - Garage Section
    
    private var garageSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Garage")
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                Spacer()
                Button {
                    showingAddCar = true
                } label: {
                    Image(systemName: "plus.circle.fill")
                        .foregroundColor(.blue)
                        .font(.title2)
                }
            }
            
            if let profile = profileManager.profile, !profile.garage.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible())], spacing: 8) {
                    ForEach(profile.garage) { car in
                        DarkCard {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(car.shortDisplay)
                                        .font(.headline)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.white)
                                    Text(car.displayString)
                                        .font(.subheadline)
                                        .foregroundColor(Color(white: 0.7))
                                }
                                Spacer()
                                if profile.selectedCarId == car.id {
                                    Text("SELECTED")
                                        .font(.caption2)
                                        .fontWeight(.semibold)
                                        .foregroundColor(.blue)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(Color.blue.opacity(0.2))
                                        .cornerRadius(8)
                                }
                            }
                        }
                        .onTapGesture {
                            selectCar(car.id)
                        }
                    }
                }
            } else {
                DarkCard {
                    VStack(spacing: 12) {
                        Image(systemName: "car")
                            .font(.title2)
                            .foregroundColor(Color(white: 0.5))
                        Text("No cars in garage")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.6))
                        Button("Add Your First Car") {
                            showingAddCar = true
                        }
                        .foregroundColor(.blue)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                }
            }
        }
    }

    // MARK: Main Stats Grid

    private var mainStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ProfileStatCell(
                icon: "location.fill", iconColor: .cyan,
                label: "Total Distance",
                value: String(format: "%.1f", stats.totalDistance * 0.000621371),
                unit: "mi"
            )
            ProfileStatCell(
                icon: "clock.fill", iconColor: .orange,
                label: "Total Duration",
                value: formatDuration(stats.totalDuration),
                unit: ""
            )
            ProfileStatCell(
                icon: "pause.fill", iconColor: .purple,
                label: "Stopped Time",
                value: formatDuration(stats.totalStoppedTime),
                unit: ""
            )
            ProfileStatCell(
                icon: "flag.fill", iconColor: .green,
                label: "Total Trips",
                value: "\(stats.totalTrips)",
                unit: ""
            )
        }
    }

    // MARK: Top Speed (full-width card)

    private var topSpeedCard: some View {
        DarkCard {
            HStack {
                Image(systemName: "bolt.fill")
                    .foregroundColor(.yellow)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Top Speed")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.55))
                    HStack(alignment: .lastTextBaseline, spacing: 4) {
                        Text(String(format: "%.0f", stats.topSpeed * 2.23694))
                            .font(.largeTitle).fontWeight(.bold)
                            .foregroundColor(.white)
                        Text("mph")
                            .font(.subheadline)
                            .foregroundColor(Color(white: 0.5))
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: Best 0-60

    private var best060Card: some View {
        DarkCard {
            HStack {
                Image(systemName: "timer")
                    .foregroundColor(Color.orange)
                    .font(.title2)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Best 0-60 mph time")
                        .font(.caption)
                        .foregroundColor(Color(white: 0.55))
                    if let t = stats.best060Time {
                        HStack(alignment: .lastTextBaseline, spacing: 4) {
                            Text(String(format: "%.2f", t))
                                .font(.largeTitle).fontWeight(.bold)
                                .foregroundColor(.white)
                            Text("sec")
                                .font(.subheadline)
                                .foregroundColor(Color(white: 0.5))
                        }
                    } else {
                        Text("—")
                            .font(.largeTitle).fontWeight(.bold)
                            .foregroundColor(Color(white: 0.4))
                    }
                }
                Spacer()
            }
        }
    }

    // MARK: Maneuvers Grid

    private var maneuvorsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ProfileStatCell(
                icon: "arrow.turn.up.left", iconColor: .blue,
                label: "Left Turns", value: "\(stats.totalLeftTurns)", unit: ""
            )
            ProfileStatCell(
                icon: "arrow.turn.up.right", iconColor: .orange,
                label: "Right Turns", value: "\(stats.totalRightTurns)", unit: ""
            )
            ProfileStatCell(
                icon: "hand.raised.fill", iconColor: .red,
                label: "Brake Events", value: "\(stats.totalBrakeEvents)", unit: ""
            )
            ProfileStatCell(
                icon: "arrow.left.arrow.right", iconColor: .green,
                label: "Lane Changes", value: "\(stats.totalLaneChanges)", unit: ""
            )
        }
    }

    // MARK: Performance Grid

    private var performanceGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ProfileStatCell(
                icon: "arrow.down.circle.fill", iconColor: .red,
                label: "Max Deceleration",
                value: String(format: "%.1f", stats.overallMaxDeceleration),
                unit: "m/s²"
            )
            ProfileStatCell(
                icon: "arrow.up.circle.fill", iconColor: .green,
                label: "Max Acceleration",
                value: String(format: "%.1f", stats.overallMaxAcceleration),
                unit: "m/s²"
            )
            ProfileStatCell(
                icon: "circle.circle.fill", iconColor: .orange,
                label: "Peak G-Force",
                value: String(format: "%.2f", stats.overallPeakGForce),
                unit: "G"
            )
            ProfileStatCell(
                icon: "arrow.triangle.2.circlepath", iconColor: .cyan,
                label: "Top Corner Speed",
                value: String(format: "%.0f", stats.overallTopCornerSpeed * 2.23694),
                unit: "mph"
            )
        }
    }

    // MARK: More Stats Grid

    private var moreStatsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            ProfileStatCell(
                icon: "car.fill", iconColor: .blue,
                label: "Total Trips", value: "\(stats.totalTrips)", unit: ""
            )
            ProfileStatCell(
                icon: "stop.circle.fill", iconColor: Color(white: 0.6),
                label: "Total Stops", value: "\(stats.totalStops)", unit: ""
            )
            ProfileStatCell(
                icon: "road.lanes", iconColor: .green,
                label: "Avg Trip Length",
                value: String(format: "%.1f", stats.avgTripLengthMeters * 0.000621371),
                unit: "mi"
            )
            ProfileStatCell(
                icon: "clock.arrow.circlepath", iconColor: .orange,
                label: "Total Duration",
                value: formatDuration(stats.totalDuration),
                unit: ""
            )
        }
    }

    // MARK: Sign Out

    private var signOutButton: some View {
        Button(role: .destructive) {
            ProfileManager.shared.clearProfile()
            AuthManager.shared.clearTokens()
        } label: {
            Text("Sign Out")
                .fontWeight(.semibold)
                .foregroundColor(.red)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(red: 0.17, green: 0.17, blue: 0.18))
                .cornerRadius(12)
        }
        .padding(.top, 8)
    }

    // MARK: Helpers

    private func formatDuration(_ seconds: Double) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        if h > 0 { return "\(h)h \(m)m" }
        return "\(m)m"
    }
    
    private func selectCar(_ carId: String) {
        guard var profile = profileManager.profile else { return }
        profile.selectCar(id: carId)
        profileManager.saveProfile(profile)
    }
}
