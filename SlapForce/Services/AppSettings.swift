import Combine
import Foundation

struct DetectionTuning: Codable, Equatable {
    var lowPassAlpha: Double
    var envelopeSmoothing: Double
    var staWindowMs: Double
    var ltaWindowMs: Double
    var triggerRatio: Double
    var rearmRatio: Double
    var absoluteFloor: Double
    var sensorDedupeCooldown: Double

    static let `default` = DetectionTuning(
        lowPassAlpha: 0.085,
        envelopeSmoothing: 0.22,
        staWindowMs: 45,
        ltaWindowMs: 320,
        triggerRatio: 2.35,
        rearmRatio: 1.18,
        absoluteFloor: 0.045,
        sensorDedupeCooldown: 0.085
    )

    func clamped() -> DetectionTuning {
        DetectionTuning(
            lowPassAlpha: min(max(lowPassAlpha, 0.01), 0.40),
            envelopeSmoothing: min(max(envelopeSmoothing, 0.01), 0.60),
            staWindowMs: min(max(staWindowMs, 12), 180),
            ltaWindowMs: min(max(ltaWindowMs, 120), 1800),
            triggerRatio: min(max(triggerRatio, 1.10), 8.0),
            rearmRatio: min(max(rearmRatio, 0.80), 4.0),
            absoluteFloor: min(max(absoluteFloor, 0.005), 1.0),
            sensorDedupeCooldown: min(max(sensorDedupeCooldown, 0.03), 0.50)
        )
    }
}

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

    @Published var detectionTuning: DetectionTuning {
        didSet {
            let sanitized = detectionTuning.clamped()
            if sanitized != detectionTuning {
                detectionTuning = sanitized
                return
            }
            persistDetectionTuning()
        }
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

        if let data = defaults.data(forKey: Keys.detectionTuning),
           let decoded = try? JSONDecoder().decode(DetectionTuning.self, from: data) {
            detectionTuning = decoded.clamped()
        } else {
            detectionTuning = .default
        }
    }

    private func persistDetectionTuning() {
        do {
            let data = try JSONEncoder().encode(detectionTuning)
            UserDefaults.standard.set(data, forKey: Keys.detectionTuning)
        } catch {
            NSLog("SlapForce: failed to persist detection tuning: %@", error.localizedDescription)
        }
    }

    private enum Keys {
        static let sensitivity = "sensitivity"
        static let cooldown = "cooldown"
        static let selectedThemeID = "selectedThemeID"
        static let keepAwake = "keepAwakeWhileListening"
        static let detectionTuning = "detectionTuning"
    }
}
