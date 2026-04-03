import SwiftUI

struct SettingsView: View {
    @ObservedObject private var settings = AppSettings.shared

    var body: some View {
        List {
            Section {
                Toggle(isOn: $settings.keepScreenOn) {
                    Label("Keep Screen On While Recording", systemImage: "sun.max.fill")
                }
            } footer: {
                Text("Prevents the display from sleeping during an active drive. Disabling this saves battery but may pause recording if the screen locks.")
            }

            Section("Units") {
                Picker("Unit System", selection: $settings.unitSystem) {
                    ForEach(UnitSystem.allCases) { system in
                        Text(system.displayName).tag(system)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
            } footer: {
                Text(settings.unitSystem == .imperial
                     ? "Speeds shown in mph, distances in miles."
                     : "Speeds shown in km/h, distances in km.")
            }

            Section("Appearance") {
                Picker("Color Scheme", selection: $settings.preferredColorScheme) {
                    ForEach(AppColorScheme.allCases) { scheme in
                        Text(scheme.displayName).tag(scheme)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
            }
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
