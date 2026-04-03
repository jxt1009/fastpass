import SwiftUI
import Combine

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

    /// Maps to SwiftUI's `ColorScheme?` (nil = follow system).
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }
}

class AppSettings: ObservableObject {
    static let shared = AppSettings()

    @Published var keepScreenOn: Bool {
        didSet { UserDefaults.standard.set(keepScreenOn, forKey: "settings_keepScreenOn") }
    }

    @Published var preferredColorScheme: AppColorScheme {
        didSet { UserDefaults.standard.set(preferredColorScheme.rawValue, forKey: "settings_colorScheme") }
    }

    private init() {
        // keepScreenOn defaults to true — most users want this while recording
        if UserDefaults.standard.object(forKey: "settings_keepScreenOn") == nil {
            keepScreenOn = true
        } else {
            keepScreenOn = UserDefaults.standard.bool(forKey: "settings_keepScreenOn")
        }

        let raw = UserDefaults.standard.string(forKey: "settings_colorScheme") ?? "system"
        preferredColorScheme = AppColorScheme(rawValue: raw) ?? .system
    }
}
