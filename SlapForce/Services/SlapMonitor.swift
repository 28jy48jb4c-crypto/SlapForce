import Combine
import Foundation

private enum TriggerTrackingState {
    case idle
    case rising
    case locked

    var displayName: String {
        switch self {
        case .idle: return "空闲"
        case .rising: return "检测主峰"
        case .locked: return "触发锁定"
        }
    }
}

@MainActor
final class SlapMonitor: ObservableObject {
    @Published private(set) var isListening = false
    @Published private(set) var latestSample = AccelerationSample.zero
    @Published private(set) var latestImpact: Double = 0
    @Published private(set) var latestTriggerMagnitude: Double = 0
    @Published private(set) var baselineMagnitude: Double = 0
    @Published private(set) var eventCount = 0
    @Published var sensorStatus = "Idle"
    @Published private(set) var startAttempts = 0
    @Published private(set) var triggerStateLabel = TriggerTrackingState.idle.displayName
    @Published private(set) var lastTriggerTimeLabel = "-"
    @Published private(set) var ignoredSecondaryPeakCount = 0

    private let accelerometer = HIDAccelerometerService()
    private var settings: AppSettings?
    private var soundModeManager: SoundModeManager?
    private var lastTriggerDate = Date.distantPast
    private var baselineSample: AccelerationSample?
    private var previousSample: AccelerationSample?
    private var trackingState: TriggerTrackingState = .idle {
        didSet {
            triggerStateLabel = trackingState.displayName
        }
    }
    private var peakImpactCandidate: Double = 0
    private var lastImpactValue: Double = 0
    private var risingSampleCount = 0
    private var fallingSampleCount = 0
    private var hasCountedSuppressedPeak = false
    private let dedupeMinimumCooldown: TimeInterval = 0.08

    func configure(settings: AppSettings, soundModeManager: SoundModeManager) {
        self.settings = settings
        self.soundModeManager = soundModeManager
        accelerometer.onSample = { [weak self] sample in
            Task { @MainActor in
                self?.handle(sample)
            }
        }
        accelerometer.onStatus = { [weak self] status in
            Task { @MainActor in
                self?.sensorStatus = status
            }
        }
    }

    func start() {
        guard !isListening else { return }
        startAttempts += 1
        sensorStatus = "Starting HID accelerometer..."
        NSLog("SlapForce: Start Listening tapped")
        do {
            try accelerometer.start()
            baselineSample = nil
            previousSample = nil
            trackingState = .idle
            peakImpactCandidate = 0
            lastImpactValue = 0
            risingSampleCount = 0
            fallingSampleCount = 0
            hasCountedSuppressedPeak = false
            latestImpact = 0
            isListening = true
            if sensorStatus.hasPrefix("Starting") {
                sensorStatus = "Listening"
            }
        } catch {
            sensorStatus = error.localizedDescription
            NSLog("SlapForce: accelerometer start failed: \(error.localizedDescription)")
            isListening = false
        }
    }

    func stop() {
        accelerometer.stop()
        isListening = false
        previousSample = nil
        trackingState = .idle
        peakImpactCandidate = 0
        lastImpactValue = 0
        risingSampleCount = 0
        fallingSampleCount = 0
        hasCountedSuppressedPeak = false
        sensorStatus = "Stopped"
    }

    func toggle() {
        isListening ? stop() : start()
    }

    private func handle(_ sample: AccelerationSample) {
        latestSample = sample
        guard let settings, let soundModeManager else { return }

        if baselineSample == nil {
            baselineSample = sample
            previousSample = sample
            baselineMagnitude = sample.magnitude
            return
        }

        guard let baseline = baselineSample else { return }
        let baselineDistance = distance(from: sample, to: baseline)
        let transientDistance = previousSample.map { distance(from: sample, to: $0) } ?? 0
        let impact = max(baselineDistance * 5.0, transientDistance * 11.0)
        latestImpact = impact
        baselineMagnitude = baseline.magnitude
        let delta = impact - lastImpactValue
        let riseDelta = max(settings.sensitivity * 0.06, 0.010)
        let fallDelta = max(settings.sensitivity * 0.08, 0.014)
        let preArmThreshold = max(settings.sensitivity * 0.55, 0.040)
        let rearmThreshold = max(settings.sensitivity * 0.30, 0.020)
        let quietDelta = max(settings.sensitivity * 0.04, 0.008)

        if delta > riseDelta {
            risingSampleCount += 1
            fallingSampleCount = 0
        } else if delta < -fallDelta {
            fallingSampleCount += 1
            risingSampleCount = 0
        } else {
            risingSampleCount = 0
            fallingSampleCount = 0
        }

        // Keep the baseline tracking slow posture changes and gravity, but do
        // not immediately absorb strong impact spikes.
        let smoothing = impact < settings.sensitivity ? 0.05 : 0.006
        baselineSample = AccelerationSample(
            x: baseline.x + (sample.x - baseline.x) * smoothing,
            y: baseline.y + (sample.y - baseline.y) * smoothing,
            z: baseline.z + (sample.z - baseline.z) * smoothing
        )
        previousSample = sample

        let threshold = settings.sensitivity
        let now = Date()
        let effectiveCooldown = max(settings.cooldown, dedupeMinimumCooldown)

        switch trackingState {
        case .idle:
            if impact >= preArmThreshold, delta > 0, risingSampleCount >= 1 {
                trackingState = .rising
                peakImpactCandidate = impact
                hasCountedSuppressedPeak = false
            }

        case .rising:
            peakImpactCandidate = max(peakImpactCandidate, impact)

            if fallingSampleCount >= 1, peakImpactCandidate >= threshold {
                if now.timeIntervalSince(lastTriggerDate) >= effectiveCooldown {
                    lastTriggerDate = now
                    latestTriggerMagnitude = peakImpactCandidate
                    eventCount += 1
                    trackingState = .locked
                    hasCountedSuppressedPeak = false
                    lastTriggerTimeLabel = Self.timestampFormatter.string(from: now)

                    soundModeManager.playSound(for: peakImpactCandidate)
                    sensorStatus = "Slap detected: peak \(String(format: "%.3f", peakImpactCandidate)), threshold \(String(format: "%.2f", threshold)), mode \(soundModeManager.currentMode.displayName)"
                } else {
                    trackingState = .locked
                    hasCountedSuppressedPeak = false
                }
            } else if fallingSampleCount >= 2, peakImpactCandidate < threshold, impact < preArmThreshold {
                trackingState = .idle
                peakImpactCandidate = 0
            }

        case .locked:
            if impact <= rearmThreshold, abs(delta) <= quietDelta {
                trackingState = .idle
                peakImpactCandidate = 0
                hasCountedSuppressedPeak = false
            } else if impact >= threshold, delta > riseDelta, !hasCountedSuppressedPeak {
                ignoredSecondaryPeakCount += 1
                hasCountedSuppressedPeak = true
                sensorStatus = "Ignored rebound peak: impact \(String(format: "%.3f", impact))"
            }
        }

        lastImpactValue = impact
    }

    private func distance(from sample: AccelerationSample, to baseline: AccelerationSample) -> Double {
        let dx = sample.x - baseline.x
        let dy = sample.y - baseline.y
        let dz = sample.z - baseline.z
        return sqrt(dx * dx + dy * dy + dz * dz)
    }

    private static let timestampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss.SSS"
        return formatter
    }()
}
