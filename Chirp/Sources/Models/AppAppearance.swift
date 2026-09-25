import SwiftUI

/// Day (the bright sky), Night (navy dusk), or whatever the iPhone is set to.
/// Stored under `AppAppearance.storageKey`; read by `ChirpApp`, set in Settings.
enum AppAppearance: String, CaseIterable, Identifiable, Sendable {
    case system
    case day
    case night

    static let storageKey = "chirp.appearance"

    var id: String { rawValue }

    /// `nil` hands the choice back to the system.
    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .day: return .light
        case .night: return .dark
        }
    }

    var title: String {
        switch self {
        case .system: return String(localized: "settings.appearance.system")
        case .day: return String(localized: "settings.appearance.day")
        case .night: return String(localized: "settings.appearance.night")
        }
    }

    var icon: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .day: return "sun.max.fill"
        case .night: return "moon.stars.fill"
        }
    }
}
