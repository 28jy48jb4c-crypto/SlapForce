import AVFoundation
import Foundation

@MainActor
final class SlapSoundEngine: ObservableObject {
    @Published private(set) var lastVolume: Float = 0
    @Published private(set) var lastPitch: Float = 0
    @Published private(set) var lastToneLabel = "Idle"

    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let pitch = AVAudioUnitTimePitch()
    private let eq = AVAudioUnitEQ(numberOfBands: 1)
    private let format = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private var importedBufferCache: [URL: AVAudioPCMBuffer] = [:]

    private struct PresetProfile {
        let baseFrequency: Double
        let frequencyRange: Double
        let modulation: Double
        let overtoneMultiplier: Double
        let overtoneMix: Double
        let noiseAmount: Float
        let decayBase: Double
    }

    init() {
        configureEngine()
        warmUpEngine()
    }

    func play(theme: SoundTheme, fileURL: URL?, force: Double, threshold: Double) {
        do {
            if !engine.isRunning {
                try engine.start()
            }

            let intensity = mapForceToIntensity(force, threshold: threshold)
            applyTone(intensity: intensity)
            player.volume = volume(for: intensity)

            if let fileURL {
                try playFile(url: fileURL, intensity: intensity)
            } else {
                let preset = theme.builtInPreset ?? .surprise
                let buffer = makeBuiltInBuffer(preset: preset, intensity: intensity)
                player.scheduleBuffer(buffer, at: nil, options: .interrupts)
            }

            player.play()
            lastVolume = player.volume
            lastPitch = pitch.pitch
        } catch {
            lastToneLabel = "Audio error: \(error.localizedDescription)"
        }
    }

    private func configureEngine() {
        let band = eq.bands[0]
        band.filterType = .parametric
        band.bypass = false
        band.frequency = 2_000
        band.bandwidth = 1.2
        band.gain = 0

        engine.attach(player)
        engine.attach(pitch)
        engine.attach(eq)
        engine.connect(player, to: pitch, format: format)
        engine.connect(pitch, to: eq, format: format)
        engine.connect(eq, to: engine.mainMixerNode, format: format)
        engine.mainMixerNode.outputVolume = 1.0
        engine.prepare()
    }

    private func warmUpEngine() {
        do {
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            lastToneLabel = "Audio warm-up failed: \(error.localizedDescription)"
        }
    }

    private func playFile(url: URL, intensity: Double) throws {
        let buffer: AVAudioPCMBuffer
        if let cached = importedBufferCache[url] {
            buffer = cached
        } else {
            let file = try AVAudioFile(forReading: url)
            let durationFrames = AVAudioFrameCount(min(Double(file.length), file.processingFormat.sampleRate * 1.4))
            let loaded = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: durationFrames)!
            try file.read(into: loaded, frameCount: durationFrames)
            importedBufferCache[url] = loaded
            buffer = loaded
        }
        player.scheduleBuffer(buffer, at: nil, options: .interrupts)
        lastToneLabel = label(for: intensity)
    }

    private func mapForceToIntensity(_ force: Double, threshold: Double) -> Double {
        let normalized = (force - threshold) / max(threshold * 2.2, 0.001)
        return min(max(normalized, 0.0), 1.0)
    }

    private func volume(for intensity: Double) -> Float {
        Float(0.18 + intensity * 0.82)
    }

    private func applyTone(intensity: Double) {
        switch intensity {
        case 0..<0.34:
            pitch.pitch = -160
            eq.bands[0].frequency = 900
            eq.bands[0].gain = -2
            lastToneLabel = "Soft"
        case 0.34..<0.72:
            pitch.pitch = 80
            eq.bands[0].frequency = 2_400
            eq.bands[0].gain = 2
            lastToneLabel = "Bright"
        default:
            pitch.pitch = 360
            eq.bands[0].frequency = 4_800
            eq.bands[0].gain = 7
            lastToneLabel = "Sharp"
        }
    }

    private func label(for intensity: Double) -> String {
        switch intensity {
        case 0..<0.34: return "Soft"
        case 0.34..<0.72: return "Bright"
        default: return "Sharp"
        }
    }

    private func makeBuiltInBuffer(preset: BuiltInSoundPreset, intensity: Double) -> AVAudioPCMBuffer {
        let profile = profile(for: preset)
        let duration = 0.10 + intensity * 0.16
        let frameCount = AVAudioFrameCount(format.sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]
        let chirpBase = profile.baseFrequency + intensity * profile.frequencyRange

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / format.sampleRate
            let progress = Double(frame) / Double(frameCount)
            let envelope = exp(-progress * (profile.decayBase - intensity * 1.6))
            let chirp = chirpBase + profile.modulation * progress * max(intensity, 0.15)
            let noise = Float.random(in: -profile.noiseAmount...profile.noiseAmount) * Float(0.35 + intensity)
            let tone = sin(2.0 * .pi * chirp * t)
            let overtone = sin(2.0 * .pi * (chirp * profile.overtoneMultiplier) * t) * (1.0 - progress)
            channel[frame] = Float((tone * (1.0 - profile.overtoneMix) + overtone * profile.overtoneMix) * envelope) + noise
        }
        return buffer
    }

    private func profile(for preset: BuiltInSoundPreset) -> PresetProfile {
        switch preset {
        case .animal:
            return PresetProfile(baseFrequency: 170, frequencyRange: 120, modulation: 90, overtoneMultiplier: 1.7, overtoneMix: 0.26, noiseAmount: 0.05, decayBase: 5.5)
        case .female:
            return PresetProfile(baseFrequency: 390, frequencyRange: 240, modulation: 150, overtoneMultiplier: 2.2, overtoneMix: 0.22, noiseAmount: 0.04, decayBase: 6.2)
        case .pain:
            return PresetProfile(baseFrequency: 260, frequencyRange: 360, modulation: 420, overtoneMultiplier: 2.8, overtoneMix: 0.34, noiseAmount: 0.08, decayBase: 6.8)
        case .surprise:
            return PresetProfile(baseFrequency: 480, frequencyRange: 520, modulation: 620, overtoneMultiplier: 2.5, overtoneMix: 0.28, noiseAmount: 0.06, decayBase: 6.1)
        case .comic:
            return PresetProfile(baseFrequency: 220, frequencyRange: 180, modulation: 110, overtoneMultiplier: 3.4, overtoneMix: 0.42, noiseAmount: 0.03, decayBase: 4.8)
        case .bassPunch:
            return PresetProfile(baseFrequency: 90, frequencyRange: 70, modulation: 55, overtoneMultiplier: 1.35, overtoneMix: 0.18, noiseAmount: 0.07, decayBase: 4.1)
        case .glitch:
            return PresetProfile(baseFrequency: 320, frequencyRange: 440, modulation: 760, overtoneMultiplier: 4.0, overtoneMix: 0.46, noiseAmount: 0.1, decayBase: 5.2)
        case .whip:
            return PresetProfile(baseFrequency: 240, frequencyRange: 310, modulation: 980, overtoneMultiplier: 3.6, overtoneMix: 0.38, noiseAmount: 0.05, decayBase: 7.0)
        }
    }
}
