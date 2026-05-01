import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var sensitivity: Double {
        didSet { UserDefaults.standard.set(sensitivity, forKey: Keys.sensitivity) }
    }

    @Published var cooldown: Double {
        didSet { UserDefaults.standard.set(cooldown, forKey: Keys.cooldown) }
    }

    @Published var selectedThemeID: UUID? {
        didSet { UserDefaults.standard.set(selectedThemeID?.uuidString, forKey: Keys.selectedThemeID) }
    }

    @Published var keepAwakeWhileListening: Bool {
        didSet { UserDefaults.standard.set(keepAwakeWhileListening, forKey: Keys.keepAwake) }
    }

    init() {
        let defaults = UserDefaults.standard
        let storedSensitivity = defaults.object(forKey: Keys.sensitivity) as? Double
        sensitivity = min(max(storedSensitivity ?? 0.12, 0.02), 1.5)
        let storedCooldown = defaults.object(forKey: Keys.cooldown) as? Double
        cooldown = min(max(storedCooldown ?? 0.12, 0.03), 1.5)
        keepAwakeWhileListening = defaults.object(forKey: Keys.keepAwake) as? Bool ?? false
        if let raw = defaults.string(forKey: Keys.selectedThemeID) {
            selectedThemeID = UUID(uuidString: raw)
        } else {
            selectedThemeID = nil
        }
    }

    private enum Keys {
        static let sensitivity = "sensitivity"
        static let cooldown = "cooldown"
        static let selectedThemeID = "selectedThemeID"
        static let keepAwake = "keepAwakeWhileListening"
    }
}
