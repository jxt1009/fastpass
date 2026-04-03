import SwiftUI
import Combine

// MARK: - Color Scheme

enum AppColorScheme: String, CaseIterable, Identifiable {
    case system = "system"
    case light  = "light"
    case dark   = "dark"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .system: return "System"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

// MARK: - Unit System

enum UnitSystem: String, CaseIterable, Identifiable {
    case imperial = "imperial"
    case metric   = "metric"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .imperial: return "Imperial"
        case .metric:   return "Metric"
        }
    }
}

// MARK: - AppSettings

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var keepScreenOn: Bool {
        didSet { UserDefaults.standard.set(keepScreenOn, forKey: "settings_keepScreenOn") }
    }

    @Published var preferredColorScheme: AppColorScheme {
        didSet {
            UserDefaults.standard.set(preferredColorScheme.rawValue, forKey: "settings_colorScheme")
            syncToServer()
        }
    }

    @Published var unitSystem: UnitSystem {
        didSet {
            UserDefaults.standard.set(unitSystem.rawValue, forKey: "settings_unitSystem")
            syncToServer()
        }
    }

    private init() {
        if UserDefaults.standard.object(forKey: "settings_keepScreenOn") == nil {
            keepScreenOn = true
        } else {
            keepScreenOn = UserDefaults.standard.bool(forKey: "settings_keepScreenOn")
        }

        let rawScheme = UserDefaults.standard.string(forKey: "settings_colorScheme") ?? "system"
        preferredColorScheme = AppColorScheme(rawValue: rawScheme) ?? .system

        let rawUnits = UserDefaults.standard.string(forKey: "settings_unitSystem") ?? "imperial"
        unitSystem = UnitSystem(rawValue: rawUnits) ?? .imperial
    }

    // MARK: - Server Sync

    func syncToServer() {
        let u = unitSystem.rawValue
        let c = preferredColorScheme.rawValue
        Task {
            try? await APIService.shared.uploadDisplaySettings(unitSystem: u, colorScheme: c)
        }
    }

    /// Applies server-side display settings. Call after sign-in / token refresh.
    @MainActor
    func restoreFromServer(unitSystem: String?, colorScheme: String?) {
        if let raw = unitSystem, let value = UnitSystem(rawValue: raw) {
            self.unitSystem = value
        }
        if let raw = colorScheme, let value = AppColorScheme(rawValue: raw) {
            self.preferredColorScheme = value
        }
    }

    // MARK: - Unit Helpers

    /// Multiply m/s by this to get display speed value.
    var speedFactor: Double   { unitSystem == .imperial ? 2.23694 : 3.6 }
    /// Multiply meters by this to get display distance value.
    var distanceFactor: Double { unitSystem == .imperial ? 0.000621371 : 0.001 }

    var speedUnit: String    { unitSystem == .imperial ? "mph"  : "km/h" }
    var distanceUnit: String { unitSystem == .imperial ? "mi"   : "km"   }

    /// Format a speed given in m/s for display (e.g. "65 mph" or "105 km/h").
    func speedDisplay(_ ms: Double, decimals: Int = 0) -> String {
        String(format: "%.\(decimals)f \(speedUnit)", ms * speedFactor)
    }

    /// Format a distance given in meters for display (e.g. "1.5 mi" or "2.4 km").
    func distanceDisplay(_ meters: Double, decimals: Int = 1) -> String {
        String(format: "%.\(decimals)f \(distanceUnit)", meters * distanceFactor)
    }

    /// Convert m/s to display units value (no label).
    func speedValue(_ ms: Double) -> Double { ms * speedFactor }

    /// Convert meters to display units value (no label).
    func distanceValue(_ meters: Double) -> Double { meters * distanceFactor }
}
