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

private struct DetectorState {
    var gravity = AccelerationSample.zero
    var envelope: Double = 0
    var sta: Double = 0
    var lta: Double = 0
    var initialized = false
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
    @Published private(set) var staValue: Double = 0
    @Published private(set) var ltaValue: Double = 0
    @Published private(set) var staLtaRatio: Double = 1
    @Published private(set) var filteredMagnitude: Double = 0
    @Published private(set) var detectionConfidence: Double = 0

    private let accelerometer = HIDAccelerometerService()
    private var settings: AppSettings?
    private var soundModeManager: SoundModeManager?
    private var lastTriggerDate = Date.distantPast
    private var previousSample: AccelerationSample?
    private var trackingState: TriggerTrackingState = .idle {
        didSet { triggerStateLabel = trackingState.displayName }
    }
    private var peakImpactCandidate: Double = 0
    private var peakRatioCandidate: Double = 0
    private var lastFilteredValue: Double = 0
    private var risingSampleCount = 0
    private var fallingSampleCount = 0
    private var quietSampleCount = 0
    private var hasCountedSuppressedPeak = false
    private var detector = DetectorState()
    private var lastSampleUptime: TimeInterval = 0
    private var lastUIRefreshUptime: TimeInterval = 0
    private var lastStatusRefreshUptime: TimeInterval = 0
    private var staleMonitorTask: Task<Void, Never>?

    private let uiRefreshInterval: TimeInterval = 1.0 / 15.0
    private let statusRefreshInterval: TimeInterval = 0.25
    private let staleSampleTimeout: TimeInterval = 2.0

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
                self?.publishSensorStatus(status, force: true)
            }
        }
    }

    func start() {
        guard !isListening else { return }
        startAttempts += 1
        publishSensorStatus("Starting HID accelerometer...", force: true)
        NSLog("SlapForce: Start Listening tapped")

        do {
            resetDetectionState()
            try accelerometer.start()
            isListening = true
            publishSensorStatus("Listening", force: true)
            startStaleMonitor()
        } catch {
            publishSensorStatus(error.localizedDescription, force: true)
            isListening = false
        }
    }

    func stop() {
        accelerometer.stop()
        staleMonitorTask?.cancel()
        staleMonitorTask = nil
        isListening = false
        resetDetectionState()
        publishSensorStatus("Stopped", force: true)
    }

    func toggle() {
        isListening ? stop() : start()
    }

    private func resetDetectionState() {
        previousSample = nil
        trackingState = .idle
        peakImpactCandidate = 0
        peakRatioCandidate = 0
        lastFilteredValue = 0
        risingSampleCount = 0
        fallingSampleCount = 0
        quietSampleCount = 0
        hasCountedSuppressedPeak = false
        detector = DetectorState()
        latestImpact = 0
        latestTriggerMagnitude = 0
        baselineMagnitude = 0
        filteredMagnitude = 0
        staValue = 0
        ltaValue = 0
        staLtaRatio = 1
        detectionConfidence = 0
        lastSampleUptime = 0
        lastUIRefreshUptime = 0
        lastStatusRefreshUptime = 0
    }

    private func handle(_ sample: AccelerationSample) {
        guard let settings, let soundModeManager else { return }

        let nowUptime = ProcessInfo.processInfo.systemUptime
        let dt = sampleDeltaTime(current: nowUptime)
        lastSampleUptime = nowUptime

        if !detector.initialized {
            detector.gravity = sample
            detector.initialized = true
            previousSample = sample
            latestSample = sample
            baselineMagnitude = sample.magnitude
            return
        }

        let tuning = settings.detectionTuning
        let lowPassAlpha = tuning.lowPassAlpha
        detector.gravity = AccelerationSample(
            x: detector.gravity.x + (sample.x - detector.gravity.x) * lowPassAlpha,
            y: detector.gravity.y + (sample.y - detector.gravity.y) * lowPassAlpha,
            z: detector.gravity.z + (sample.z - detector.gravity.z) * lowPassAlpha
        )

        let highPass = AccelerationSample(
            x: sample.x - detector.gravity.x,
            y: sample.y - detector.gravity.y,
            z: sample.z - detector.gravity.z
        )
        let highPassMagnitude = sqrt(highPass.x * highPass.x + highPass.y * highPass.y + highPass.z * highPass.z)

        let transientDistance = previousSample.map { distance(from: sample, to: $0) } ?? 0
        let mixedMagnitude = max(highPassMagnitude, transientDistance * 0.85)

        detector.envelope += tuning.envelopeSmoothing * (mixedMagnitude - detector.envelope)
        let staAlpha = smoothingAlpha(windowMs: tuning.staWindowMs, dt: dt)
        let ltaAlpha = smoothingAlpha(windowMs: tuning.ltaWindowMs, dt: dt)
        detector.sta += staAlpha * (detector.envelope - detector.sta)
        detector.lta += ltaAlpha * (detector.envelope - detector.lta)

        let ratio = detector.sta / max(detector.lta, 0.0001)
        let delta = detector.envelope - lastFilteredValue
        let rearmEnvelope = max(tuning.absoluteFloor * 0.58, settings.sensitivity * 0.35)
        let absoluteFloor = max(tuning.absoluteFloor, settings.sensitivity * 0.40)
        let effectiveCooldown = max(settings.cooldown, tuning.sensorDedupeCooldown)
        let triggerRiseDelta = max(absoluteFloor * 0.12, 0.004)
        let fallDelta = max(absoluteFloor * 0.10, 0.004)
        let quietDelta = max(absoluteFloor * 0.06, 0.002)

        if delta > triggerRiseDelta {
            risingSampleCount += 1
            fallingSampleCount = 0
            quietSampleCount = 0
        } else if delta < -fallDelta {
            fallingSampleCount += 1
            risingSampleCount = 0
            quietSampleCount = 0
        } else if abs(delta) <= quietDelta {
            quietSampleCount += 1
            risingSampleCount = 0
            fallingSampleCount = 0
        } else {
            risingSampleCount = 0
            fallingSampleCount = 0
            quietSampleCount = 0
        }

        let canArm = detector.envelope >= absoluteFloor * 0.85 && ratio >= max(1.02, tuning.rearmRatio * 0.95)
        let canTrigger = detector.envelope >= absoluteFloor && ratio >= tuning.triggerRatio
        let confidence = min(
            1.0,
            max(0, (ratio - tuning.rearmRatio) / max(tuning.triggerRatio - tuning.rearmRatio, 0.01))
                * min(1.0, detector.envelope / max(absoluteFloor, 0.0001))
        )

        switch trackingState {
        case .idle:
            if canArm && delta > 0 && risingSampleCount >= 1 {
                trackingState = .rising
                peakImpactCandidate = detector.envelope
                peakRatioCandidate = ratio
                hasCountedSuppressedPeak = false
            }

        case .rising:
            peakImpactCandidate = max(peakImpactCandidate, detector.envelope)
            peakRatioCandidate = max(peakRatioCandidate, ratio)

            if fallingSampleCount >= 1 && canTrigger {
                let now = Date()
                if now.timeIntervalSince(lastTriggerDate) >= effectiveCooldown {
                    lastTriggerDate = now
                    let playbackMagnitude = playbackMagnitudeForPeak(
                        peakEnvelope: peakImpactCandidate,
                        peakRatio: peakRatioCandidate
                    )
                    latestTriggerMagnitude = playbackMagnitude
                    eventCount += 1
                    trackingState = .locked
                    hasCountedSuppressedPeak = false
                    lastTriggerTimeLabel = Self.timestampFormatter.string(from: now)

                    soundModeManager.playSound(for: playbackMagnitude)
                    publishSensorStatus(
                        "Slap detected: env \(String(format: "%.3f", peakImpactCandidate)), ratio \(String(format: "%.2f", peakRatioCandidate)), mode \(soundModeManager.currentMode.displayName)"
                    )
                } else {
                    trackingState = .locked
                    hasCountedSuppressedPeak = false
                }
            } else if fallingSampleCount >= 2 && ratio < tuning.rearmRatio && detector.envelope < absoluteFloor {
                trackingState = .idle
                peakImpactCandidate = 0
                peakRatioCandidate = 0
            }

        case .locked:
            if ratio <= tuning.rearmRatio && detector.envelope <= rearmEnvelope && quietSampleCount >= 2 {
                trackingState = .idle
                peakImpactCandidate = 0
                peakRatioCandidate = 0
                hasCountedSuppressedPeak = false
            } else if canTrigger && delta > triggerRiseDelta && !hasCountedSuppressedPeak {
                ignoredSecondaryPeakCount += 1
                hasCountedSuppressedPeak = true
                publishSensorStatus("Ignored rebound peak: ratio \(String(format: "%.2f", ratio))")
            }
        }

        previousSample = sample
        lastFilteredValue = detector.envelope
        baselineMagnitude = detector.gravity.magnitude

        if shouldRefreshUI(at: nowUptime) {
            latestSample = sample
            latestImpact = detector.envelope
            filteredMagnitude = mixedMagnitude
            staValue = detector.sta
            ltaValue = detector.lta
            staLtaRatio = ratio
            detectionConfidence = confidence
            lastUIRefreshUptime = nowUptime
        }
    }

    private func sampleDeltaTime(current now: TimeInterval) -> Double {
        guard lastSampleUptime > 0 else { return 1.0 / 120.0 }
        return min(max(now - lastSampleUptime, 1.0 / 400.0), 0.12)
    }

    private func smoothingAlpha(windowMs: Double, dt: Double) -> Double {
        let seconds = max(windowMs / 1_000.0, 0.001)
        return 1.0 - exp(-dt / seconds)
    }

    private func playbackMagnitudeForPeak(peakEnvelope: Double, peakRatio: Double) -> Double {
        let ratioContribution = max(0, peakRatio - 1.0) * 0.28
        let envelopeContribution = peakEnvelope * 2.8
        return min(1.8, max(0.04, envelopeContribution + ratioContribution))
    }

    private func shouldRefreshUI(at now: TimeInterval) -> Bool {
        lastUIRefreshUptime == 0 || now - lastUIRefreshUptime >= uiRefreshInterval
    }

    private func publishSensorStatus(_ status: String, force: Bool = false) {
        let now = ProcessInfo.processInfo.systemUptime
        if force || lastStatusRefreshUptime == 0 || now - lastStatusRefreshUptime >= statusRefreshInterval {
            sensorStatus = status
            lastStatusRefreshUptime = now
        }
    }

    private func startStaleMonitor() {
        staleMonitorTask?.cancel()
        staleMonitorTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                await MainActor.run {
                    guard let self, self.isListening else { return }
                    let now = ProcessInfo.processInfo.systemUptime
                    guard self.lastSampleUptime > 0 else { return }
                    if now - self.lastSampleUptime >= self.staleSampleTimeout {
                        self.publishSensorStatus("采样停滞，等待 AppleSPU 恢复...", force: true)
                    }
                }
            }
        }
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
