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

            Section {
                Picker("Unit System", selection: $settings.unitSystem) {
                    ForEach(UnitSystem.allCases) { system in
                        Text(system.displayName).tag(system)
                    }
                }
                .pickerStyle(.segmented)
                .listRowInsets(.init(top: 12, leading: 16, bottom: 12, trailing: 16))
            } header: {
                Text("Units")
            } footer: {
                Text(settings.unitSystem == .imperial
                     ? "Speeds shown in mph, distances in miles."
                     : "Speeds shown in km/h, distances in km.")
            }

            Section {
                SpeedometerCalibrationRow(settings: settings)
            } header: {
                Text("Speedometer Calibration")
            } footer: {
                Text("Car speedometers are intentionally calibrated to read 2–7% higher than actual speed (GPS truth). Use this to match the app's displayed speed to your car. Raw drive data is always stored as true GPS speed.")
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

// MARK: - Speedometer Calibration Row

private struct SpeedometerCalibrationRow: View {
    @ObservedObject var settings: AppSettings
    // Stepper works in 0.5% increments; range ±10%
    private let step = 0.5
    private let range = -10.0...10.0

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Bias Offset", systemImage: "speedometer")
                Spacer()
                Text(biasLabel)
                    .monospacedDigit()
                    .foregroundStyle(settings.speedometerBiasPercent == 0 ? .secondary : .primary)
            }

            // Slider for quick adjustment
            Slider(
                value: $settings.speedometerBiasPercent,
                in: range,
                step: step
            )
            .tint(sliderColor)

            // Stepper-style fine adjustment buttons
            HStack(spacing: 0) {
                Button {
                    settings.speedometerBiasPercent = max(range.lowerBound,
                                                          settings.speedometerBiasPercent - step)
                } label: {
                    Image(systemName: "minus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)

                Text(biasLabel)
                    .font(.subheadline).fontWeight(.semibold)
                    .monospacedDigit()
                    .frame(minWidth: 70)
                    .multilineTextAlignment(.center)

                Button {
                    settings.speedometerBiasPercent = min(range.upperBound,
                                                          settings.speedometerBiasPercent + step)
                } label: {
                    Image(systemName: "plus")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.bordered)
            }

            if settings.speedometerBiasPercent != 0 {
                Button("Reset to 0%") {
                    settings.speedometerBiasPercent = 0
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private var biasLabel: String {
        let val = settings.speedometerBiasPercent
        if val == 0 { return "0% (off)" }
        return String(format: "%+.1f%%", val)
    }

    private var sliderColor: Color {
        settings.speedometerBiasPercent > 0 ? .orange : .blue
    }
}

#Preview {
    NavigationStack {
        SettingsView()
    }
}
