import SwiftUI

struct MoreView: View {
    @ObservedObject private var profileManager = ProfileManager.shared

    var body: some View {
        NavigationStack {
            List {
                // Profile summary header
                if let profile = profileManager.profile {
                    Section {
                        HStack(spacing: 14) {
                            // Avatar
                            Group {
                                if let image = profileManager.profileImage {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 56, height: 56)
                                        .clipShape(Circle())
                                } else {
                                    ZStack {
                                        Circle()
                                            .fill(LinearGradient(
                                                colors: [.blue, .purple],
                                                startPoint: .topLeading,
                                                endPoint: .bottomTrailing
                                            ))
                                            .frame(width: 56, height: 56)
                                        Text(String(profile.username.prefix(1)).uppercased())
                                            .font(.title2)
                                            .fontWeight(.bold)
                                            .foregroundStyle(.white)
                                    }
                                }
                            }

                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.username)
                                    .font(.headline)
                                if !profile.country.isEmpty {
                                    Text(profile.country)
                                        .font(.subheadline)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 4)
                    }
                }

                // Navigation rows
                Section {
                    NavigationLink(destination: ProfileView()) {
                        Label("My Profile", systemImage: "person.fill")
                    }

                    NavigationLink(destination: AchievementsView()) {
                        Label("Achievements", systemImage: "trophy.fill")
                    }
                }

                Section {
                    NavigationLink(destination: SettingsView()) {
                        Label("Settings", systemImage: "gearshape.fill")
                    }
                }
            }
            .navigationTitle("More")
            .navigationBarTitleDisplayMode(.large)
        }
    }
}

#Preview {
    MoreView()
}
