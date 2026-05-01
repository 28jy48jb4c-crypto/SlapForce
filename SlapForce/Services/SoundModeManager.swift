@preconcurrency import AVFoundation
import AppKit
import Foundation

enum SoundMode: String, CaseIterable, Codable, Identifiable {
    case 性感
    case 经典
    case 动物
    case 惊喜

    var id: String { rawValue }

    var displayName: String { rawValue }

    var systemImage: String {
        switch self {
        case .性感: return "heart"
        case .经典: return "waveform"
        case .动物: return "pawprint"
        case .惊喜: return "sparkles"
        }
    }

    var summary: String {
        switch self {
        case .性感:
            return "柔和贴近，轻拍时更柔，重拍时更饱满。"
        case .经典:
            return "直给稳定，主要靠力度和瞬态拉开层次。"
        case .动物:
            return "保留真实反应，轻重拍会对应不同强度的叫声反馈。"
        case .惊喜:
            return "更戏剧化，力度越大越亮、越夸张、越有存在感。"
        }
    }
}

enum IntensityTier: Int, CaseIterable, Identifiable {
    case 轻 = 0
    case 中 = 1
    case 重 = 2

    var id: Int { rawValue }

    var displayName: String {
        switch self {
        case .轻: return "轻"
        case .中: return "中"
        case .重: return "重"
        }
    }

    var suffix: String { "\(displayName)档" }
}

private enum SexySourceLayer: Int, CaseIterable {
    case 克制 = 1
    case 轻柔 = 2
    case 贴近 = 3
    case 投入 = 4
    case 炽热 = 5

    var displayName: String {
        switch self {
        case .克制: return "克制"
        case .轻柔: return "轻柔"
        case .贴近: return "贴近"
        case .投入: return "投入"
        case .炽热: return "炽热"
        }
    }

    var indexRange: ClosedRange<Int> {
        switch self {
        case .克制: return 1...10
        case .轻柔: return 11...21
        case .贴近: return 22...33
        case .投入: return 34...46
        case .炽热: return 47...59
        }
    }

    static func forOrderedIndex(_ index: Int) -> SexySourceLayer {
        switch index {
        case 1...10: return .克制
        case 11...21: return .轻柔
        case 22...33: return .贴近
        case 34...46: return .投入
        default: return .炽热
        }
    }

    static func baseLayer(for momentum: Double) -> SexySourceLayer {
        switch momentum {
        case ..<0.30: return .克制
        case ..<0.56: return .轻柔
        case ..<0.78: return .贴近
        case ..<0.93: return .投入
        default: return .炽热
        }
    }

    static func clamped(_ rawValue: Int) -> SexySourceLayer {
        SexySourceLayer(rawValue: min(max(rawValue, 1), 5)) ?? .克制
    }
}

struct SoundModeConfig {
    // 模式基础音量。normalizedMagnitude 为 0 时，播放从这里起步。
    let baseVolume: Float

    // 随力度映射的音调范围。轻拍靠近 lowerBound，重拍靠近 upperBound。
    let pitchRange: ClosedRange<Float>

    // 力度对音量和音调的放大系数。数值越大，轻重差异越明显。
    let intensityScale: Float

    // 当前模式扫描到的原始音频片段集合。
    let clipPool: [URL]
}

private struct PersistedModeSettings: Codable {
    let baseVolume: Double
    let pitchLower: Double
    let pitchUpper: Double
    let intensityScale: Double
}

private struct DerivedClipVariant {
    let id: String
    let sourceURL: URL?
    let sourceName: String
    let mode: SoundMode
    let tier: IntensityTier
    let displayName: String
    let sourceIntensity: Double
    let sourceMood: Double
    let sourceOrderedIndex: Int?
    let sexyLayer: SexySourceLayer?
    let buffer: AVAudioPCMBuffer
}

private struct SourceClipDescriptor {
    let url: URL
    let sourceName: String
    let buffer: AVAudioPCMBuffer
    let rawIntensity: Double
    let normalizedIntensity: Double
    let normalizedMood: Double
    let orderedIndex: Int?
    let sexyLayer: SexySourceLayer?
}

private struct ModePlaybackPool {
    var lightVariants: [DerivedClipVariant] = []
    var midVariants: [DerivedClipVariant] = []
    var heavyVariants: [DerivedClipVariant] = []

    var isEmpty: Bool {
        lightVariants.isEmpty && midVariants.isEmpty && heavyVariants.isEmpty
    }

    func variants(for tier: IntensityTier) -> [DerivedClipVariant] {
        switch tier {
        case .轻: return lightVariants
        case .中: return midVariants
        case .重: return heavyVariants
        }
    }

    var allVariants: [DerivedClipVariant] {
        lightVariants + midVariants + heavyVariants
    }

    var derivedSummary: String {
        "轻\(lightVariants.count)/中\(midVariants.count)/重\(heavyVariants.count)"
    }
}

private struct VariantRenderProfile {
    let lengthFactor: Double
    let gain: Float
    let brightness: Float
    let transientBoost: Float
    let fadeInSeconds: Double
    let fadeOutFraction: Double
    let tailPower: Double
    let saturation: Float
    let volumeMultiplier: Float
    let pitchOffset: Float
    let eqGainOffset: Float
    let eqFrequencyOffset: Float
}

private struct PlaybackEQSettings {
    let frequency: Float
    let gain: Float
    let bandwidth: Float
}

private struct PlaybackRequest {
    let buffer: AVAudioPCMBuffer
    let volume: Float
    let pitch: Float
    let eq: PlaybackEQSettings
}

private final class PlaybackCoordinator {
    private final class PlayerSlot {
        let player = AVAudioPlayerNode()
        let pitch = AVAudioUnitTimePitch()
        let eq = AVAudioUnitEQ(numberOfBands: 1)
        var busyUntil: TimeInterval = 0
        var lastUsedAt: TimeInterval = 0
    }

    private let engine = AVAudioEngine()
    private let queue = DispatchQueue(label: "SlapForce.AudioPlayback", qos: .userInitiated)
    private let format: AVAudioFormat
    private var slots: [PlayerSlot] = []

    init(format: AVAudioFormat, slotCount: Int = 4) {
        self.format = format
        configure(slotCount: slotCount)
    }

    func warmUp() {
        queue.async { [weak self] in
            guard let self else { return }
            try? self.ensureEngineRunning()
        }
    }

    func recoverIfNeeded() {
        queue.async { [weak self] in
            guard let self else { return }
            if !self.engine.isRunning {
                try? self.ensureEngineRunning()
            }
        }
    }

    func play(_ request: PlaybackRequest, completion: @escaping @Sendable (NSError?) -> Void) {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                try self.ensureEngineRunning()
                let now = ProcessInfo.processInfo.systemUptime
                let slot = self.selectSlot(now: now)

                slot.player.stop()
                slot.player.volume = request.volume
                slot.pitch.pitch = request.pitch

                let band = slot.eq.bands[0]
                band.filterType = .parametric
                band.bypass = false
                band.frequency = request.eq.frequency
                band.gain = request.eq.gain
                band.bandwidth = request.eq.bandwidth

                slot.lastUsedAt = now
                slot.busyUntil = now + Double(request.buffer.frameLength) / self.format.sampleRate + 0.05
                slot.player.scheduleBuffer(request.buffer, at: nil, options: .interrupts, completionHandler: nil)
                slot.player.play()
                completion(nil)
            } catch {
                self.recoverEngine()
                completion(error as NSError)
            }
        }
    }

    private func configure(slotCount: Int) {
        for _ in 0..<slotCount {
            let slot = PlayerSlot()
            let band = slot.eq.bands[0]
            band.filterType = .parametric
            band.bypass = false
            band.frequency = 1_800
            band.bandwidth = 1.2
            band.gain = 0

            engine.attach(slot.player)
            engine.attach(slot.pitch)
            engine.attach(slot.eq)
            engine.connect(slot.player, to: slot.pitch, format: format)
            engine.connect(slot.pitch, to: slot.eq, format: format)
            engine.connect(slot.eq, to: engine.mainMixerNode, format: format)
            slots.append(slot)
        }

        engine.mainMixerNode.outputVolume = 1.0
        engine.prepare()
    }

    private func ensureEngineRunning() throws {
        if !engine.isRunning {
            try engine.start()
        }
    }

    private func recoverEngine() {
        engine.stop()
        engine.reset()
        engine.prepare()
        try? engine.start()
    }

    private func selectSlot(now: TimeInterval) -> PlayerSlot {
        if let available = slots.first(where: { $0.busyUntil <= now }) {
            return available
        }
        return slots.min(by: { $0.lastUsedAt < $1.lastUsedAt }) ?? slots[0]
    }
}

@MainActor
final class SoundModeManager: ObservableObject {
    @Published var currentMode: SoundMode {
        didSet {
            UserDefaults.standard.set(currentMode.rawValue, forKey: Keys.currentMode)
            syncEditorsFromCurrentMode()
            playbackStatus = "已切换到\(currentMode.displayName)模式"
        }
    }

    @Published private(set) var lastVolume: Float = 0
    @Published private(set) var lastPitch: Float = 0
    @Published private(set) var lastClipName = "待机"
    @Published private(set) var lastSourceClipName = "待机"
    @Published private(set) var lastVariantName = "待机"
    @Published private(set) var lastTriggerTierName = "-"
    @Published private(set) var playbackStatus = "尚未触发播放"
    @Published private(set) var libraryStatus = "音效库尚未扫描"
    @Published private(set) var sexyStateLabel = "冷静"
    @Published private(set) var sexyStateValue: Double = 0
    @Published private(set) var sexySourceLayerLabel = "-"
    @Published private(set) var sexyBaseLayerLabel = "-"
    @Published private(set) var sexyImpactBoostLabel = "0"
    @Published private(set) var sexyFinalLayerLabel = "-"
    @Published private(set) var sexySelectionWindowLabel = "-"
    @Published private(set) var sexyLibraryLayerSummary = "克制0 / 轻柔0 / 贴近0 / 投入0 / 炽热0"
    @Published private(set) var currentSourceLayerLabel = "-"
    @Published private(set) var currentSelectionWindowLabel = "-"

    @Published var editableBaseVolume: Double = 0.6 {
        didSet { applyEditorChanges() }
    }
    @Published var editablePitchLower: Double = 0 {
        didSet { applyEditorChanges() }
    }
    @Published var editablePitchUpper: Double = 0 {
        didSet { applyEditorChanges() }
    }
    @Published var editableIntensityScale: Double = 1.0 {
        didSet { applyEditorChanges() }
    }
    @Published var editablePlaybackCooldown: Double = 0.08 {
        didSet {
            playbackCooldown = editablePlaybackCooldown
            UserDefaults.standard.set(editablePlaybackCooldown, forKey: Keys.playbackCooldown)
        }
    }

    private let playbackFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    private let fileManager = FileManager.default
    private lazy var playbackCoordinator = PlaybackCoordinator(format: playbackFormat, slotCount: 4)

    private let maxExpectedMagnitude: Double = 1.6
    private var playbackCooldown: TimeInterval = 0.08
    private var lastPlaybackTime: TimeInterval = 0
    private var clipCache: [URL: AVAudioPCMBuffer] = [:]
    private var modeConfigs: [SoundMode: SoundModeConfig] = [:]
    private var playbackPools: [SoundMode: ModePlaybackPool] = [:]
    private var lastPlayedVariantIDByMode: [SoundMode: String] = [:]
    private var isSyncingEditors = false
    private var sexyMomentum: Double = 0
    private var lastSexyMomentumUpdate: TimeInterval = 0
    private var lastSexyHitTime: TimeInterval = 0
    private let sexyDecayHalfLife: TimeInterval = 14
    private let sexyIdleResetAfter: TimeInterval = 6.5

    init() {
        if let raw = UserDefaults.standard.string(forKey: Keys.currentMode),
           let restored = SoundMode(rawValue: raw) {
            currentMode = restored
        } else {
            currentMode = .经典
        }

        let storedCooldown = UserDefaults.standard.object(forKey: Keys.playbackCooldown) as? Double
        editablePlaybackCooldown = min(max(storedCooldown ?? 0.08, 0.02), 0.40)
        playbackCooldown = editablePlaybackCooldown

        rebuildLibrary()
        syncEditorsFromCurrentMode()
        warmUpEngine()
    }

    var soundsDirectory: URL {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return support.appendingPathComponent("SlapForce", isDirectory: true)
            .appendingPathComponent("Sounds", isDirectory: true)
    }

    func openModeLibraryFolder() {
        try? fileManager.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([soundsDirectory])
    }

    func config(for magnitude: Double) -> SoundModeConfig {
        modeConfigs[currentMode] ?? defaultConfig(for: currentMode, clipPool: [])
    }

    func playSound(for magnitude: Double) {
        let normalizedMagnitude = normalize(magnitude)
        let mode = currentMode
        let config = config(for: magnitude)
        let tier = tier(for: normalizedMagnitude)

        Task { @MainActor in
            let now = ProcessInfo.processInfo.systemUptime
            guard now - lastPlaybackTime >= playbackCooldown else { return }
            lastPlaybackTime = now

            let sexyState = mode == .性感 ? updateSexyMomentum(now: now, normalizedMagnitude: normalizedMagnitude) : 0
            let profile = renderProfile(for: mode, tier: tier, sexyMomentum: sexyState)

            let baseVolume = config.baseVolume * (1 + Float(normalizedMagnitude) * config.intensityScale)
            let volume = clampedVolume(baseVolume * profile.volumeMultiplier)
            let pitch = mappedPitch(normalizedMagnitude: normalizedMagnitude, range: config.pitchRange) + profile.pitchOffset

            let eq = eqSettings(
                for: mode,
                tier: tier,
                normalizedMagnitude: normalizedMagnitude,
                profile: profile,
                sexyMomentum: sexyState
            )

            let request: PlaybackRequest
            if let variant = selectVariant(
                mode: mode,
                tier: tier,
                normalizedMagnitude: normalizedMagnitude,
                sexyMomentum: sexyState
            ) {
                request = PlaybackRequest(buffer: variant.buffer, volume: volume, pitch: pitch, eq: eq)
                lastPlayedVariantIDByMode[mode] = variant.id
                lastSourceClipName = variant.sourceName
                lastVariantName = variant.displayName
                lastClipName = variant.displayName
                lastTriggerTierName = tier.displayName
                currentSourceLayerLabel = variant.sexyLayer?.displayName ?? currentSourceLayerLabel
                currentSelectionWindowLabel = currentSelectionWindowLabel == "-" ? sexyWindowLabel(for: [variant]) : currentSelectionWindowLabel
                sexySourceLayerLabel = mode == .性感 ? currentSourceLayerLabel : "-"
                playbackStatus = mode == .性感
                    ? "\(mode.displayName)模式 \(tier.suffix)：\(variant.sourceName) · 状态\(sexyStateLabel) · 素材\(sexySourceLayerLabel)"
                    : "\(mode.displayName)模式 \(tier.suffix)：\(variant.sourceName) · 层级\(currentSourceLayerLabel)"
            } else {
                let fallback = makeFallbackBuffer(
                    for: mode,
                    normalizedMagnitude: normalizedMagnitude,
                    sexyMomentum: sexyState
                )
                request = PlaybackRequest(buffer: fallback, volume: volume, pitch: pitch, eq: eq)
                lastSourceClipName = "无导入片段"
                lastVariantName = "\(mode.displayName)合成回退"
                lastClipName = lastVariantName
                lastTriggerTierName = tier.displayName
                currentSourceLayerLabel = "-"
                currentSelectionWindowLabel = "-"
                sexySourceLayerLabel = mode == .性感 ? "回退音" : "-"
                playbackStatus = mode == .性感
                    ? "\(mode.displayName)模式暂无可用音频，当前使用状态化回退音 · \(sexyStateLabel)"
                    : "\(mode.displayName)模式暂无可用音频，当前使用回退音"
            }

            playbackCoordinator.play(request) { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    if let error {
                        self.lastClipName = "播放错误"
                        self.lastSourceClipName = "播放错误"
                        self.lastVariantName = "播放错误"
                        self.lastTriggerTierName = tier.displayName
                        self.playbackStatus = "模式播放错误 [\(error.domain):\(error.code)] \(error.localizedDescription)"
                    } else {
                        self.lastVolume = volume
                        self.lastPitch = pitch
                    }
                }
            }
        }
    }

    func rebuildLibrary() {
        do {
            try fileManager.createDirectory(at: soundsDirectory, withIntermediateDirectories: true)
        } catch {
            libraryStatus = "无法创建 Sounds 目录: \(error.localizedDescription)"
            return
        }

        let allFiles = scanSoundFiles()
        let grouped = classify(files: allFiles)

        clipCache.removeAll()
        lastPlayedVariantIDByMode.removeAll()
        modeConfigs = [
            .性感: defaultConfig(for: .性感, clipPool: grouped[.性感] ?? []),
            .经典: defaultConfig(for: .经典, clipPool: grouped[.经典] ?? []),
            .动物: defaultConfig(for: .动物, clipPool: grouped[.动物] ?? []),
            .惊喜: defaultConfig(for: .惊喜, clipPool: grouped[.惊喜] ?? [])
        ]

        applyPersistedSettings()
        playbackPools = buildPlaybackPools(from: grouped)
        autoSelectModeIfNeeded()
        syncEditorsFromCurrentMode()
        refreshSexyState(at: ProcessInfo.processInfo.systemUptime)
        refreshSexyLibraryLayerSummary()

        let totalRawCount = Set(modeConfigs.values.flatMap(\.clipPool)).count
        libraryStatus = buildLibraryStatus(totalRawCount: totalRawCount)
        playbackStatus = "已重建四种模式的轻/中/重派生池"
    }

    func currentConfigSummary() -> String {
        guard let config = modeConfigs[currentMode] else { return "暂无配置" }
        let poolSummary = playbackPools[currentMode]?.derivedSummary ?? "轻0/中0/重0"
        if currentMode == .性感 {
            return "基础音量 \(String(format: "%.2f", config.baseVolume))  音调 \(Int(config.pitchRange.lowerBound))...\(Int(config.pitchRange.upperBound))  力度增益 \(String(format: "%.2f", config.intensityScale))  派生 \(poolSummary)  分层 \(sexyLibraryLayerSummary)"
        }
        return "基础音量 \(String(format: "%.2f", config.baseVolume))  音调 \(Int(config.pitchRange.lowerBound))...\(Int(config.pitchRange.upperBound))  力度增益 \(String(format: "%.2f", config.intensityScale))  派生 \(poolSummary)"
    }

    private func warmUpEngine() {
        playbackCoordinator.warmUp()
    }

    private func scanSoundFiles() -> [URL] {
        let allowedExtensions = Set(["wav", "mp3", "m4a", "aif", "aiff", "caf"])
        var collected: [URL] = []

        for directory in candidateSoundDirectories() {
            guard let enumerator = fileManager.enumerator(
                at: directory,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles]
            ) else { continue }

            for case let url as URL in enumerator {
                let ext = url.pathExtension.lowercased()
                guard allowedExtensions.contains(ext) else { continue }
                let values = try? url.resourceValues(forKeys: [.isRegularFileKey])
                guard values?.isRegularFile == true else { continue }
                collected.append(url)
            }
        }

        return Array(Set(collected)).sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private func candidateSoundDirectories() -> [URL] {
        var urls = [soundsDirectory]
        if let bundleSounds = Bundle.main.resourceURL?.appendingPathComponent("Sounds", isDirectory: true),
           fileManager.fileExists(atPath: bundleSounds.path) {
            urls.append(bundleSounds)
        }
        return urls
    }

    private func classify(files: [URL]) -> [SoundMode: [URL]] {
        var grouped: [SoundMode: [URL]] = [
            .性感: [],
            .经典: [],
            .动物: [],
            .惊喜: []
        ]

        for file in files {
            let name = file.deletingPathExtension().lastPathComponent.lowercased()
            if matches(name: name, keywords: ["sexy", "性感"]) {
                grouped[.性感, default: []].append(file)
            } else if matches(name: name, keywords: ["classic", "经典"]) {
                grouped[.经典, default: []].append(file)
            } else if matches(name: name, keywords: ["animal", "动物"]) {
                grouped[.动物, default: []].append(file)
            } else if matches(name: name, keywords: ["surprise", "惊喜"]) {
                grouped[.惊喜, default: []].append(file)
            }
        }

        for mode in SoundMode.allCases {
            grouped[mode] = (grouped[mode] ?? []).sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        return grouped
    }

    private func matches(name: String, keywords: [String]) -> Bool {
        keywords.contains { keyword in
            name.localizedCaseInsensitiveContains(keyword)
        }
    }

    private func defaultConfig(for mode: SoundMode, clipPool: [URL]) -> SoundModeConfig {
        switch mode {
        case .性感:
            return SoundModeConfig(
                baseVolume: 0.42,
                pitchRange: -240...280,
                intensityScale: 0.82,
                clipPool: clipPool
            )
        case .经典:
            return SoundModeConfig(
                baseVolume: 0.6,
                pitchRange: -10...35,
                intensityScale: 0.92,
                clipPool: clipPool
            )
        case .动物:
            return SoundModeConfig(
                baseVolume: 0.68,
                pitchRange: -110...220,
                intensityScale: 1.10,
                clipPool: clipPool
            )
        case .惊喜:
            return SoundModeConfig(
                baseVolume: 0.52,
                pitchRange: -260...680,
                intensityScale: 1.62,
                clipPool: clipPool
            )
        }
    }

    private func buildPlaybackPools(from grouped: [SoundMode: [URL]]) -> [SoundMode: ModePlaybackPool] {
        var result: [SoundMode: ModePlaybackPool] = [:]

        for mode in SoundMode.allCases {
            var pool = ModePlaybackPool()
            let descriptors = buildSourceDescriptors(for: grouped[mode] ?? [], mode: mode)
            for descriptor in descriptors {
                do {
                    for tier in IntensityTier.allCases {
                        let variant = try deriveVariant(
                            from: descriptor.buffer,
                            sourceURL: descriptor.url,
                            sourceName: descriptor.sourceName,
                            sourceIntensity: descriptor.normalizedIntensity,
                            sourceMood: descriptor.normalizedMood,
                            sourceOrderedIndex: descriptor.orderedIndex,
                            sexyLayer: descriptor.sexyLayer,
                            mode: mode,
                            tier: tier
                        )
                        switch tier {
                        case .轻:
                            pool.lightVariants.append(variant)
                        case .中:
                            pool.midVariants.append(variant)
                        case .重:
                            pool.heavyVariants.append(variant)
                        }
                    }
                } catch {
                    NSLog("SlapForce: failed to derive variants for %@: %@", descriptor.url.lastPathComponent, error.localizedDescription)
                }
            }
            result[mode] = pool
        }

        return result
    }

    private func buildSourceDescriptors(for urls: [URL], mode: SoundMode) -> [SourceClipDescriptor] {
        var rawDescriptors: [(url: URL, name: String, buffer: AVAudioPCMBuffer, rawIntensity: Double)] = []

        for url in urls {
            do {
                let baseBuffer = try buffer(for: url)
                let score = analyzeIntensity(of: baseBuffer)
                rawDescriptors.append((
                    url: url,
                    name: url.deletingPathExtension().lastPathComponent,
                    buffer: baseBuffer,
                    rawIntensity: score
                ))
            } catch {
                NSLog("SlapForce: failed to analyze %@: %@", url.lastPathComponent, error.localizedDescription)
            }
        }

        let sorted = rawDescriptors.sorted { left, right in
            if left.rawIntensity == right.rawIntensity {
                return left.name < right.name
            }
            return left.rawIntensity < right.rawIntensity
        }

        guard !sorted.isEmpty else { return [] }
        let minScore = sorted.first?.rawIntensity ?? 0
        let maxScore = sorted.last?.rawIntensity ?? 1
        let span = max(maxScore - minScore, 0.0001)

        let orderedDescriptors = rawDescriptors.compactMap { descriptor -> (descriptor: (url: URL, name: String, buffer: AVAudioPCMBuffer, rawIntensity: Double), index: Int)? in
            guard let index = orderedIndex(from: descriptor.name, mode: mode) else { return nil }
            return (descriptor, index)
        }

        if !orderedDescriptors.isEmpty {
            let ordered = orderedDescriptors.sorted { left, right in
                let leftIndex = left.index
                let rightIndex = right.index
                switch (leftIndex, rightIndex) {
                default:
                    if leftIndex == rightIndex {
                        return left.descriptor.name < right.descriptor.name
                    }
                    return leftIndex < rightIndex
                }
            }

            return ordered.enumerated().map { index, descriptor in
                let orderedIndex = descriptor.index
                let sequencePosition = ordered.count == 1 ? 0.5 : Double(index) / Double(ordered.count - 1)
                let normalized: Double
                let layer: SexySourceLayer
                if mode == .性感 {
                    normalized = max(0, Double(orderedIndex - 1) / 58.0)
                    layer = SexySourceLayer.forOrderedIndex(orderedIndex)
                } else {
                    normalized = sequencePosition
                    layer = orderedLayerForSequencePosition(index: index, totalCount: ordered.count)
                }
                return SourceClipDescriptor(
                    url: descriptor.descriptor.url,
                    sourceName: descriptor.descriptor.name,
                    buffer: descriptor.descriptor.buffer,
                    rawIntensity: descriptor.descriptor.rawIntensity,
                    normalizedIntensity: normalized,
                    normalizedMood: normalized,
                    orderedIndex: orderedIndex,
                    sexyLayer: layer
                )
            }
        }

        return sorted.enumerated().map { index, descriptor in
            let rankPosition = sorted.count == 1 ? 0.5 : Double(index) / Double(sorted.count - 1)
            let normalizedByFeature = (descriptor.rawIntensity - minScore) / span
            let normalized = sorted.count == 1 ? 0.5 : (normalizedByFeature * 0.55 + rankPosition * 0.45)
            let moodHint = sexyMoodHint(for: descriptor.name)
            let normalizedMood = moodHint >= 0 ? moodHint : normalized
            return SourceClipDescriptor(
                url: descriptor.url,
                sourceName: descriptor.name,
                buffer: descriptor.buffer,
                rawIntensity: descriptor.rawIntensity,
                normalizedIntensity: normalized,
                normalizedMood: normalizedMood,
                orderedIndex: nil,
                sexyLayer: nil
            )
        }
    }

    private func sexyMoodHint(for sourceName: String) -> Double {
        let lowered = sourceName.lowercased()
        let buckets: [(Double, [String])] = [
            (0.10, ["soft", "gentle", "mild", "tender", "light", "calm", "shy", "轻", "柔", "温柔", "含蓄", "低"]),
            (0.45, ["warm", "tease", "flirty", "close", "mid", "center", "中", "暖", "贴近", "投入"]),
            (0.85, ["hot", "intense", "deep", "moan", "breath", "high", "heavy", "重", "热", "炽热", "浓", "高"])
        ]

        for (value, keywords) in buckets {
            if keywords.contains(where: { lowered.localizedCaseInsensitiveContains($0) }) {
                return value
            }
        }

        return -1
    }

    private func deriveVariant(
        from sourceBuffer: AVAudioPCMBuffer,
        sourceURL: URL?,
        sourceName: String,
        sourceIntensity: Double,
        sourceMood: Double,
        sourceOrderedIndex: Int?,
        sexyLayer: SexySourceLayer?,
        mode: SoundMode,
        tier: IntensityTier
    ) throws -> DerivedClipVariant {
        let profile = renderProfile(for: mode, tier: tier)
        let sourceFrames = Int(sourceBuffer.frameLength)
        let minFrames = Int(playbackFormat.sampleRate * 0.08)
        let targetFrames = min(
            sourceFrames,
            max(minFrames, Int(Double(sourceFrames) * profile.lengthFactor))
        )

        guard let output = AVAudioPCMBuffer(
            pcmFormat: playbackFormat,
            frameCapacity: AVAudioFrameCount(targetFrames)
        ) else {
            throw NSError(
                domain: "SoundModeManager",
                code: 2001,
                userInfo: [NSLocalizedDescriptionKey: "无法创建派生音频缓存"]
            )
        }

        output.frameLength = AVAudioFrameCount(targetFrames)
        guard
            let sourceChannel = sourceBuffer.floatChannelData?.pointee,
            let outputChannel = output.floatChannelData?.pointee
        else {
            throw NSError(
                domain: "SoundModeManager",
                code: 2002,
                userInfo: [NSLocalizedDescriptionKey: "无法访问音频采样数据"]
            )
        }

        let fadeInFrames = max(16, Int(playbackFormat.sampleRate * profile.fadeInSeconds))
        let fadeOutFrames = max(32, Int(Double(targetFrames) * profile.fadeOutFraction))
        let lowAlpha = lowpassAlpha(for: profile.brightness)
        var lowState: Float = 0
        var maxAbs: Float = 0

        for frame in 0..<targetFrames {
            let progress = Double(frame) / Double(max(targetFrames - 1, 1))
            var sample = sourceChannel[min(frame, sourceFrames - 1)] * profile.gain

            lowState += lowAlpha * (sample - lowState)
            let high = sample - lowState
            if profile.brightness >= 0 {
                sample = lowState * (1 - profile.brightness * 0.08) + high * (0.40 + profile.brightness * 0.85)
            } else {
                let darkness = abs(profile.brightness)
                sample = lowState * (1 + darkness * 0.18) + high * (0.32 - darkness * 0.16)
            }

            if frame < fadeInFrames {
                let attackProgress = Float(frame) / Float(max(fadeInFrames, 1))
                let transient = 1 + profile.transientBoost * (1 - attackProgress)
                sample *= transient
            }

            if frame >= max(0, targetFrames - fadeOutFrames) {
                let remaining = Double(targetFrames - frame) / Double(max(fadeOutFrames, 1))
                sample *= Float(pow(max(remaining, 0.0), profile.tailPower))
            }

            if profile.saturation > 0 {
                let drive = 1 + profile.saturation * 1.8
                sample = Float(tanh(Double(sample * drive)) / tanh(Double(drive)))
            }

            outputChannel[frame] = sample
            maxAbs = max(maxAbs, abs(sample))

            if progress > 0.995 {
                outputChannel[frame] *= 0.8
            }
        }

        if maxAbs > 0.001 {
            let normalizeGain = min(0.96 / maxAbs, 1.55)
            for frame in 0..<targetFrames {
                outputChannel[frame] *= normalizeGain
            }
        }

        let variantName = "\(sourceName)・\(tier.suffix)"
        return DerivedClipVariant(
            id: variantID(for: sourceURL, tier: tier),
            sourceURL: sourceURL,
            sourceName: sourceName,
            mode: mode,
            tier: tier,
            displayName: variantName,
            sourceIntensity: sourceIntensity,
            sourceMood: sourceMood,
            sourceOrderedIndex: sourceOrderedIndex,
            sexyLayer: sexyLayer,
            buffer: output
        )
    }

    private func renderProfile(
        for mode: SoundMode,
        tier: IntensityTier,
        sexyMomentum: Double = 0
    ) -> VariantRenderProfile {
        switch (mode, tier) {
        case (.性感, .轻):
            return VariantRenderProfile(
                lengthFactor: 0.82 + sexyMomentum * 0.08,
                gain: 0.70 + Float(sexyMomentum) * 0.05,
                brightness: -0.68 + Float(sexyMomentum) * 0.18,
                transientBoost: 0.03 + Float(sexyMomentum) * 0.05,
                fadeInSeconds: 0.012,
                fadeOutFraction: 0.30,
                tailPower: 1.45 - sexyMomentum * 0.10,
                saturation: 0.01 + Float(sexyMomentum) * 0.03,
                volumeMultiplier: 0.84 + Float(sexyMomentum) * 0.06,
                pitchOffset: -78 + Float(sexyMomentum) * 26,
                eqGainOffset: -1.0 + Float(sexyMomentum) * 0.8,
                eqFrequencyOffset: -420 + Float(sexyMomentum) * 120
            )
        case (.性感, .中):
            return VariantRenderProfile(
                lengthFactor: 0.98 + sexyMomentum * 0.10,
                gain: 0.94 + Float(sexyMomentum) * 0.06,
                brightness: -0.18 + Float(sexyMomentum) * 0.22,
                transientBoost: 0.06 + Float(sexyMomentum) * 0.05,
                fadeInSeconds: 0.009,
                fadeOutFraction: 0.24,
                tailPower: 1.28 - sexyMomentum * 0.14,
                saturation: 0.04 + Float(sexyMomentum) * 0.05,
                volumeMultiplier: 0.98 + Float(sexyMomentum) * 0.09,
                pitchOffset: -6 + Float(sexyMomentum) * 34,
                eqGainOffset: 0.1 + Float(sexyMomentum) * 0.9,
                eqFrequencyOffset: -150 + Float(sexyMomentum) * 160
            )
        case (.性感, .重):
            return VariantRenderProfile(
                lengthFactor: 1.02 + sexyMomentum * 0.12,
                gain: 1.12 + Float(sexyMomentum) * 0.08,
                brightness: 0.08 + Float(sexyMomentum) * 0.20,
                transientBoost: 0.12 + Float(sexyMomentum) * 0.08,
                fadeInSeconds: 0.007,
                fadeOutFraction: 0.22,
                tailPower: 1.18 - sexyMomentum * 0.16,
                saturation: 0.08 + Float(sexyMomentum) * 0.08,
                volumeMultiplier: 1.14 + Float(sexyMomentum) * 0.12,
                pitchOffset: 36 + Float(sexyMomentum) * 40,
                eqGainOffset: 1.0 + Float(sexyMomentum) * 1.2,
                eqFrequencyOffset: 40 + Float(sexyMomentum) * 220
            )

        case (.经典, .轻):
            return VariantRenderProfile(lengthFactor: 0.84, gain: 0.76, brightness: -0.08, transientBoost: 0.12, fadeInSeconds: 0.008, fadeOutFraction: 0.14, tailPower: 1.08, saturation: 0.03, volumeMultiplier: 0.82, pitchOffset: -6, eqGainOffset: -0.1, eqFrequencyOffset: -90)
        case (.经典, .中):
            return VariantRenderProfile(lengthFactor: 0.94, gain: 0.98, brightness: 0.01, transientBoost: 0.12, fadeInSeconds: 0.007, fadeOutFraction: 0.13, tailPower: 1.04, saturation: 0.04, volumeMultiplier: 1.0, pitchOffset: 0, eqGainOffset: 0.0, eqFrequencyOffset: 0)
        case (.经典, .重):
            return VariantRenderProfile(lengthFactor: 0.86, gain: 1.10, brightness: 0.10, transientBoost: 0.22, fadeInSeconds: 0.005, fadeOutFraction: 0.10, tailPower: 0.98, saturation: 0.08, volumeMultiplier: 1.08, pitchOffset: 8, eqGainOffset: 0.5, eqFrequencyOffset: 80)

        case (.动物, .轻):
            return VariantRenderProfile(lengthFactor: 0.70, gain: 0.68, brightness: -0.46, transientBoost: 0.04, fadeInSeconds: 0.011, fadeOutFraction: 0.18, tailPower: 1.22, saturation: 0.02, volumeMultiplier: 0.82, pitchOffset: -74, eqGainOffset: -0.7, eqFrequencyOffset: -280)
        case (.动物, .中):
            return VariantRenderProfile(lengthFactor: 0.96, gain: 0.98, brightness: 0.00, transientBoost: 0.11, fadeInSeconds: 0.008, fadeOutFraction: 0.15, tailPower: 1.08, saturation: 0.04, volumeMultiplier: 1.0, pitchOffset: 0, eqGainOffset: 0.2, eqFrequencyOffset: 40)
        case (.动物, .重):
            return VariantRenderProfile(lengthFactor: 0.82, gain: 1.16, brightness: 0.38, transientBoost: 0.24, fadeInSeconds: 0.006, fadeOutFraction: 0.11, tailPower: 0.92, saturation: 0.14, volumeMultiplier: 1.16, pitchOffset: 64, eqGainOffset: 2.0, eqFrequencyOffset: 280)

        case (.惊喜, .轻):
            return VariantRenderProfile(lengthFactor: 0.66, gain: 0.74, brightness: 0.12, transientBoost: 0.14, fadeInSeconds: 0.006, fadeOutFraction: 0.14, tailPower: 0.96, saturation: 0.16, volumeMultiplier: 0.92, pitchOffset: 70, eqGainOffset: 1.2, eqFrequencyOffset: 260)
        case (.惊喜, .中):
            return VariantRenderProfile(lengthFactor: 0.82, gain: 1.04, brightness: 0.36, transientBoost: 0.24, fadeInSeconds: 0.005, fadeOutFraction: 0.12, tailPower: 0.90, saturation: 0.24, volumeMultiplier: 1.08, pitchOffset: 170, eqGainOffset: 2.4, eqFrequencyOffset: 420)
        case (.惊喜, .重):
            return VariantRenderProfile(lengthFactor: 0.70, gain: 1.24, brightness: 0.62, transientBoost: 0.34, fadeInSeconds: 0.004, fadeOutFraction: 0.08, tailPower: 0.78, saturation: 0.34, volumeMultiplier: 1.24, pitchOffset: 300, eqGainOffset: 4.2, eqFrequencyOffset: 680)
        }
    }

    private func lowpassAlpha(for brightness: Float) -> Float {
        let normalized = (brightness + 1) / 2
        return 0.08 + normalized * 0.34
    }

    private func syncEditorsFromCurrentMode() {
        guard let config = modeConfigs[currentMode] else { return }
        isSyncingEditors = true
        editableBaseVolume = Double(config.baseVolume)
        editablePitchLower = Double(config.pitchRange.lowerBound)
        editablePitchUpper = Double(config.pitchRange.upperBound)
        editableIntensityScale = Double(config.intensityScale)
        editablePlaybackCooldown = playbackCooldown
        isSyncingEditors = false
    }

    private func applyEditorChanges() {
        guard !isSyncingEditors, let config = modeConfigs[currentMode] else { return }

        let clampedBaseVolume = min(max(editableBaseVolume, 0.1), 1.4)
        let clampedIntensity = min(max(editableIntensityScale, 0.1), 2.5)
        let lower = min(editablePitchLower, editablePitchUpper - 1)
        let upper = max(editablePitchUpper, lower + 1)

        if clampedBaseVolume != editableBaseVolume ||
            clampedIntensity != editableIntensityScale ||
            lower != editablePitchLower ||
            upper != editablePitchUpper {
            isSyncingEditors = true
            editableBaseVolume = clampedBaseVolume
            editableIntensityScale = clampedIntensity
            editablePitchLower = lower
            editablePitchUpper = upper
            isSyncingEditors = false
        }

        modeConfigs[currentMode] = SoundModeConfig(
            baseVolume: Float(clampedBaseVolume),
            pitchRange: Float(lower)...Float(upper),
            intensityScale: Float(clampedIntensity),
            clipPool: config.clipPool
        )
        persistCurrentModeSettings()
    }

    private func persistCurrentModeSettings() {
        let payload = PersistedModeSettings(
            baseVolume: editableBaseVolume,
            pitchLower: editablePitchLower,
            pitchUpper: editablePitchUpper,
            intensityScale: editableIntensityScale
        )

        do {
            let data = try JSONEncoder().encode(payload)
            UserDefaults.standard.set(data, forKey: persistenceKey(for: currentMode))
        } catch {
            playbackStatus = "保存模式参数失败: \(error.localizedDescription)"
        }
    }

    private func applyPersistedSettings() {
        for mode in SoundMode.allCases {
            guard
                let data = UserDefaults.standard.data(forKey: persistenceKey(for: mode)),
                let persisted = try? JSONDecoder().decode(PersistedModeSettings.self, from: data),
                let config = modeConfigs[mode]
            else { continue }

            modeConfigs[mode] = SoundModeConfig(
                baseVolume: Float(min(max(persisted.baseVolume, 0.1), 1.4)),
                pitchRange: Float(persisted.pitchLower)...Float(max(persisted.pitchUpper, persisted.pitchLower + 1)),
                intensityScale: Float(min(max(persisted.intensityScale, 0.1), 2.5)),
                clipPool: config.clipPool
            )
        }
    }

    private func autoSelectModeIfNeeded() {
        let populatedModes = SoundMode.allCases.filter { !(playbackPools[$0]?.isEmpty ?? true) }
        if (playbackPools[currentMode]?.isEmpty ?? true),
           populatedModes.count == 1,
           let onlyMode = populatedModes.first {
            currentMode = onlyMode
        }
    }

    private func persistenceKey(for mode: SoundMode) -> String {
        "\(Keys.modeSettingsPrefix).\(mode.rawValue)"
    }

    private func normalize(_ magnitude: Double) -> Double {
        min(max(magnitude / maxExpectedMagnitude, 0), 1)
    }

    private func tier(for normalizedMagnitude: Double) -> IntensityTier {
        switch normalizedMagnitude {
        case ..<0.34: return .轻
        case ..<0.72: return .中
        default: return .重
        }
    }

    private func mappedPitch(normalizedMagnitude: Double, range: ClosedRange<Float>) -> Float {
        let span = range.upperBound - range.lowerBound
        return range.lowerBound + Float(normalizedMagnitude) * span
    }

    private func clampedVolume(_ value: Float) -> Float {
        min(max(value, 0.05), 1.5)
    }

    private func selectVariant(
        mode: SoundMode,
        tier: IntensityTier,
        normalizedMagnitude: Double,
        sexyMomentum: Double = 0
    ) -> DerivedClipVariant? {
        if let variant = selectOrderedVariant(
            mode: mode,
            tier: tier,
            normalizedMagnitude: normalizedMagnitude,
            sexyMomentum: sexyMomentum
        ) {
            return variant
        }

        sexyBaseLayerLabel = "-"
        sexyImpactBoostLabel = "0"
        sexyFinalLayerLabel = "-"
        sexySelectionWindowLabel = "-"
        currentSourceLayerLabel = "-"
        currentSelectionWindowLabel = "-"

        return selectGeneralVariant(
            mode: mode,
            tier: tier,
            normalizedMagnitude: normalizedMagnitude,
            sexyMomentum: sexyMomentum
        )
    }

    private func selectGeneralVariant(
        mode: SoundMode,
        tier: IntensityTier,
        normalizedMagnitude: Double,
        sexyMomentum: Double = 0
    ) -> DerivedClipVariant? {
        guard let pool = playbackPools[mode], !pool.isEmpty else { return nil }

        let selectedTier = effectiveTier(for: mode, baseTier: tier, sexyMomentum: sexyMomentum)
        var candidates = pool.variants(for: selectedTier)
        if candidates.isEmpty {
            candidates = pool.allVariants
        }
        guard !candidates.isEmpty else { return nil }

        if let lastID = lastPlayedVariantIDByMode[mode], candidates.count > 1 {
            let filtered = candidates.filter { $0.id != lastID }
            if !filtered.isEmpty {
                candidates = filtered
            }
        }

        let targetIntensity = tierTargetIntensity(
            for: tier,
            exactMagnitude: normalizedMagnitude,
            mode: mode,
            sexyMomentum: sexyMomentum
        )
        let targetMood = mode == .性感 ? sexyTargetMood(for: tier, sexyMomentum: sexyMomentum) : targetIntensity
        let sortedCandidates = candidates.sorted { left, right in
            let leftDistance = variantDistance(
                for: left,
                mode: mode,
                targetIntensity: targetIntensity,
                targetMood: targetMood
            )
            let rightDistance = variantDistance(
                for: right,
                mode: mode,
                targetIntensity: targetIntensity,
                targetMood: targetMood
            )
            if leftDistance == rightDistance {
                return left.sourceName < right.sourceName
            }
            return leftDistance < rightDistance
        }

        let shortlistCount = min(max(1, Int(ceil(Double(sortedCandidates.count) * 0.5))), 3)
        let shortlist = Array(sortedCandidates.prefix(shortlistCount))
        return shortlist.randomElement() ?? sortedCandidates.first
    }

    private func selectOrderedVariant(
        mode: SoundMode,
        tier: IntensityTier,
        normalizedMagnitude: Double,
        sexyMomentum: Double
    ) -> DerivedClipVariant? {
        guard let pool = playbackPools[mode], !pool.isEmpty else { return nil }

        var candidates = pool.variants(for: tier)
        if candidates.isEmpty {
            candidates = pool.allVariants
        }

        let orderedCandidates = candidates
            .filter { $0.sourceOrderedIndex != nil && $0.sexyLayer != nil }
            .sorted { ($0.sourceOrderedIndex ?? 0) < ($1.sourceOrderedIndex ?? 0) }

        guard !orderedCandidates.isEmpty else { return nil }

        let baseLayer: SexySourceLayer
        let impactBoost: Int
        var finalLayer: SexySourceLayer

        if mode == .性感 {
            baseLayer = SexySourceLayer.baseLayer(for: sexyMomentum)
            impactBoost = sexyImpactBoost(for: normalizedMagnitude)
            finalLayer = SexySourceLayer.clamped(baseLayer.rawValue + impactBoost)

            if normalizedMagnitude >= 0.92 {
                finalLayer = SexySourceLayer.clamped(max(finalLayer.rawValue, SexySourceLayer.投入.rawValue))
            }
            if normalizedMagnitude >= 0.985 {
                finalLayer = .炽热
            }
        } else {
            baseLayer = orderedBaseLayer(for: normalizedMagnitude)
            impactBoost = 0
            finalLayer = baseLayer
        }

        var layerCandidates = orderedCandidates.filter { $0.sexyLayer == finalLayer }
        if layerCandidates.isEmpty {
            layerCandidates = nearestSexyLayerCandidates(
                from: orderedCandidates,
                targetLayer: finalLayer
            )
        }
        guard !layerCandidates.isEmpty else { return nil }

        if let lastID = lastPlayedVariantIDByMode[mode], layerCandidates.count > 1 {
            let filtered = layerCandidates.filter { $0.id != lastID }
            if !filtered.isEmpty {
                layerCandidates = filtered
            }
        }

        let windowBias = mode == .性感
            ? sexyWindowBias(
                normalizedMagnitude: normalizedMagnitude,
                sexyMomentum: sexyMomentum,
                impactBoost: impactBoost
            )
            : orderedWindowBias(for: normalizedMagnitude)
        let shortlist = sexyWindowedShortlist(from: layerCandidates, bias: windowBias)
        let chosen = shortlist.randomElement() ?? layerCandidates.first

        currentSourceLayerLabel = chosen?.sexyLayer?.displayName ?? finalLayer.displayName
        currentSelectionWindowLabel = sexyWindowLabel(for: shortlist.isEmpty ? layerCandidates : shortlist)

        if mode == .性感 {
            sexyBaseLayerLabel = baseLayer.displayName
            sexyImpactBoostLabel = impactBoost >= 0 ? "+\(impactBoost)" : "\(impactBoost)"
            sexyFinalLayerLabel = finalLayer.displayName
            sexySourceLayerLabel = currentSourceLayerLabel
            sexySelectionWindowLabel = currentSelectionWindowLabel
        }

        return chosen
    }

    private func orderedBaseLayer(for normalizedMagnitude: Double) -> SexySourceLayer {
        switch normalizedMagnitude {
        case ..<0.16: return .克制
        case ..<0.36: return .轻柔
        case ..<0.60: return .贴近
        case ..<0.82: return .投入
        default: return .炽热
        }
    }

    private func orderedWindowBias(for normalizedMagnitude: Double) -> Double {
        switch normalizedMagnitude {
        case ..<0.18: return 0.16
        case ..<0.38: return 0.30
        case ..<0.62: return 0.48
        case ..<0.82: return 0.66
        default: return 0.84
        }
    }

    private func orderedLayerForSequencePosition(index: Int, totalCount: Int) -> SexySourceLayer {
        guard totalCount > 1 else { return .贴近 }
        let normalized = Double(index) / Double(totalCount - 1)
        switch normalized {
        case ..<0.20: return .克制
        case ..<0.40: return .轻柔
        case ..<0.60: return .贴近
        case ..<0.80: return .投入
        default: return .炽热
        }
    }

    private func sexyImpactBoost(for normalizedMagnitude: Double) -> Int {
        switch normalizedMagnitude {
        case ..<0.32:
            return -1
        case ..<0.78:
            return 0
        case ..<0.93:
            return 1
        default:
            return 2
        }
    }

    private func sexyWindowBias(
        normalizedMagnitude: Double,
        sexyMomentum: Double,
        impactBoost: Int
    ) -> Double {
        if normalizedMagnitude >= 0.90 {
            return min(1.0, 0.84 + (normalizedMagnitude - 0.90) * 1.6)
        }

        if impactBoost < 0 {
            return max(0.10, 0.18 + sexyMomentum * 0.18)
        }

        if impactBoost == 0 {
            return min(0.62, 0.22 + sexyMomentum * 0.24 + normalizedMagnitude * 0.10)
        }

        return min(0.82, 0.48 + sexyMomentum * 0.18 + normalizedMagnitude * 0.14)
    }

    private func sexyWindowedShortlist(
        from candidates: [DerivedClipVariant],
        bias: Double
    ) -> [DerivedClipVariant] {
        let ordered = candidates.sorted { ($0.sourceOrderedIndex ?? 0) < ($1.sourceOrderedIndex ?? 0) }
        guard ordered.count > 5 else { return ordered }

        let anchor = Int(round(bias * Double(max(ordered.count - 1, 1))))
        let radius = min(2, max(1, ordered.count / 7))
        let start = max(0, anchor - radius)
        let end = min(ordered.count - 1, anchor + radius)
        return Array(ordered[start...end])
    }

    private func nearestSexyLayerCandidates(
        from candidates: [DerivedClipVariant],
        targetLayer: SexySourceLayer
    ) -> [DerivedClipVariant] {
        for distance in 1...4 {
            let lower = SexySourceLayer(rawValue: targetLayer.rawValue - distance)
            let upper = SexySourceLayer(rawValue: targetLayer.rawValue + distance)
            let match = candidates.filter { candidate in
                candidate.sexyLayer == lower || candidate.sexyLayer == upper
            }
            if !match.isEmpty {
                return match
            }
        }
        return candidates
    }

    private func effectiveTier(for mode: SoundMode, baseTier: IntensityTier, sexyMomentum: Double) -> IntensityTier {
        guard mode == .性感 else { return baseTier }

        switch (baseTier, sexyMomentum) {
        case (.轻, let momentum) where momentum >= 0.78:
            return .中
        case (.中, let momentum) where momentum >= 0.88:
            return .重
        default:
            return baseTier
        }
    }

    private func variantDistance(
        for variant: DerivedClipVariant,
        mode: SoundMode,
        targetIntensity: Double,
        targetMood: Double
    ) -> Double {
        let intensityDistance = abs(variant.sourceIntensity - targetIntensity)
        if mode == .性感 {
            let moodDistance = abs(variant.sourceMood - targetMood)
            return moodDistance * 0.68 + intensityDistance * 0.32
        }
        return intensityDistance
    }

    private func tierTargetIntensity(
        for tier: IntensityTier,
        exactMagnitude: Double,
        mode: SoundMode,
        sexyMomentum: Double
    ) -> Double {
        let base: Double
        switch tier {
        case .轻:
            base = min(exactMagnitude * 0.55, 0.26)
        case .中:
            base = 0.42 + exactMagnitude * 0.18
        case .重:
            base = max(0.72, exactMagnitude * 0.95)
        }

        if mode == .性感 {
            return min(1.0, base + sexyMomentum * 0.16)
        }
        return base
    }

    private func sexyTargetMood(for tier: IntensityTier, sexyMomentum: Double) -> Double {
        let base: Double
        switch tier {
        case .轻:
            base = 0.18
        case .中:
            base = 0.46
        case .重:
            base = 0.76
        }

        return min(1.0, base + sexyMomentum * 0.24)
    }

    private func sexyMoodLabel(for mood: Double) -> String {
        switch mood {
        case ..<0.25:
            return "轻柔层"
        case ..<0.60:
            return "贴近层"
        default:
            return "炽热层"
        }
    }

    private func analyzeIntensity(of buffer: AVAudioPCMBuffer) -> Double {
        guard let channel = buffer.floatChannelData?.pointee else { return 0.5 }

        let frameCount = Int(buffer.frameLength)
        guard frameCount > 0 else { return 0.5 }

        var sumSquares: Double = 0
        var peak: Float = 0
        var transientSum: Double = 0
        var brightSum: Double = 0
        var previous: Float = channel[0]
        var lowState: Float = channel[0]
        let alpha: Float = 0.12

        for index in 0..<frameCount {
            let sample = channel[index]
            let absSample = abs(sample)
            peak = max(peak, absSample)
            sumSquares += Double(sample * sample)

            let delta = abs(sample - previous)
            transientSum += Double(delta)
            previous = sample

            lowState += alpha * (sample - lowState)
            brightSum += Double(abs(sample - lowState))
        }

        let rms = sqrt(sumSquares / Double(frameCount))
        let transient = transientSum / Double(frameCount)
        let brightness = brightSum / Double(frameCount)

        let weighted = rms * 0.50 + Double(peak) * 0.22 + transient * 1.9 + brightness * 1.2
        return weighted
    }

    private func eqSettings(
        for mode: SoundMode,
        tier: IntensityTier,
        normalizedMagnitude: Double,
        profile: VariantRenderProfile,
        sexyMomentum: Double = 0
    ) -> PlaybackEQSettings {
        let frequency: Float
        let gain: Float
        switch mode {
        case .性感:
            frequency = 900 + Float(normalizedMagnitude) * 520 + profile.eqFrequencyOffset + Float(sexyMomentum) * 140
            gain = 0.2 + Float(normalizedMagnitude) * 1.4 + profile.eqGainOffset + Float(sexyMomentum) * 0.9
        case .经典:
            frequency = 1_450 + Float(normalizedMagnitude) * 220 + profile.eqFrequencyOffset
            gain = Float(normalizedMagnitude) * 0.45 + profile.eqGainOffset
        case .动物:
            frequency = 1_700 + Float(normalizedMagnitude) * 1_420 + profile.eqFrequencyOffset
            gain = 1.1 + Float(normalizedMagnitude) * 2.5 + profile.eqGainOffset
        case .惊喜:
            frequency = 2_400 + Float(normalizedMagnitude) * 2_200 + profile.eqFrequencyOffset
            gain = 2.8 + Float(normalizedMagnitude) * 3.8 + profile.eqGainOffset
        }

        let bandwidth: Float
        switch mode {
        case .性感:
            bandwidth = tier == .重 ? max(0.95, 1.15 - Float(sexyMomentum) * 0.18) : max(1.10, 1.35 - Float(sexyMomentum) * 0.12)
        case .经典:
            bandwidth = 1.25
        case .动物:
            bandwidth = tier == .轻 ? 1.15 : 0.92
        case .惊喜:
            bandwidth = tier == .重 ? 0.72 : 0.95
        }

        return PlaybackEQSettings(frequency: frequency, gain: gain, bandwidth: bandwidth)
    }

    private func buildLibraryStatus(totalRawCount: Int) -> String {
        let modeDetails = SoundMode.allCases.map { mode -> String in
            let rawCount = modeConfigs[mode]?.clipPool.count ?? 0
            let derived = playbackPools[mode]?.derivedSummary ?? "轻0/中0/重0"
            if mode == .性感 {
                return "\(mode.displayName) 原始\(rawCount)条 派生\(derived) 分层\(sexyLibraryLayerSummary)"
            }
            return "\(mode.displayName) 原始\(rawCount)条 派生\(derived)"
        }.joined(separator: "；")
        return "已扫描 Sounds 目录，识别到 \(totalRawCount) 个原始音频。\(modeDetails)"
    }

    private func refreshSexyLibraryLayerSummary() {
        let sexyVariants = playbackPools[.性感]?.allVariants ?? []
        let uniqueSources = Dictionary(grouping: sexyVariants, by: \.sourceName).compactMap { $0.value.first }
        let counts = SexySourceLayer.allCases.map { layer in
            "\(layer.displayName)\(uniqueSources.filter { $0.sexyLayer == layer }.count)"
        }
        sexyLibraryLayerSummary = counts.joined(separator: " / ")
    }

    private func sexyWindowLabel(for candidates: [DerivedClipVariant]) -> String {
        let ordered = candidates.compactMap(\.sourceOrderedIndex).sorted()
        guard let first = ordered.first, let last = ordered.last else { return "-" }
        if first == last {
            return String(format: "%02d", first)
        }
        return String(format: "%02d-%02d", first, last)
    }

    private func orderedIndex(from sourceName: String, mode: SoundMode) -> Int? {
        let lowered = sourceName.lowercased()
        let english: String
        switch mode {
        case .性感: english = "sexy"
        case .经典: english = "classic"
        case .动物: english = "animal"
        case .惊喜: english = "surprise"
        }
        guard lowered.contains("audio_\(english)") ||
                lowered.contains("audio-\(english)") ||
                lowered.contains("audio\(english)") ||
                lowered.contains(mode.rawValue.lowercased()) ||
                lowered.contains(english) else {
            return nil
        }

        let digitGroups = lowered
            .components(separatedBy: CharacterSet.decimalDigits.inverted)
            .filter { !$0.isEmpty }
        guard let last = digitGroups.last, let value = Int(last) else { return nil }
        return value
    }

    private func variantID(for sourceURL: URL?, tier: IntensityTier) -> String {
        let base = sourceURL?.absoluteString ?? UUID().uuidString
        return "\(base)#\(tier.rawValue)"
    }

    private func buffer(for url: URL) throws -> AVAudioPCMBuffer {
        if let cached = clipCache[url] {
            return cached
        }

        let file = try AVAudioFile(forReading: url)
        let sourceFormat = file.processingFormat
        let maxFrames = AVAudioFrameCount(min(Double(file.length), sourceFormat.sampleRate * 1.8))

        guard let sourceBuffer = AVAudioPCMBuffer(pcmFormat: sourceFormat, frameCapacity: maxFrames) else {
            throw NSError(
                domain: "SoundModeManager",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "无法为源音频创建缓存"]
            )
        }

        try file.read(into: sourceBuffer, frameCount: maxFrames)
        let buffer = try convertBufferIfNeeded(sourceBuffer, from: sourceFormat)
        clipCache[url] = buffer
        return buffer
    }

    private func convertBufferIfNeeded(
        _ sourceBuffer: AVAudioPCMBuffer,
        from sourceFormat: AVAudioFormat
    ) throws -> AVAudioPCMBuffer {
        let sampleRateMatches = abs(sourceFormat.sampleRate - playbackFormat.sampleRate) < 0.5
        let channelsMatch = sourceFormat.channelCount == playbackFormat.channelCount

        if sampleRateMatches && channelsMatch {
            return sourceBuffer
        }

        guard let converter = AVAudioConverter(from: sourceFormat, to: playbackFormat) else {
            throw NSError(
                domain: "SoundModeManager",
                code: 1002,
                userInfo: [NSLocalizedDescriptionKey: "无法把导入音频转换为统一播放格式"]
            )
        }

        let ratio = playbackFormat.sampleRate / sourceFormat.sampleRate
        let convertedCapacity = AVAudioFrameCount(max(1, ceil(Double(sourceBuffer.frameLength) * ratio)))

        guard let convertedBuffer = AVAudioPCMBuffer(
            pcmFormat: playbackFormat,
            frameCapacity: convertedCapacity
        ) else {
            throw NSError(
                domain: "SoundModeManager",
                code: 1003,
                userInfo: [NSLocalizedDescriptionKey: "无法为转换后的音频创建缓存"]
            )
        }

        var conversionError: NSError?
        var hasProvidedInput = false

        let status = converter.convert(to: convertedBuffer, error: &conversionError) { _, outStatus in
            if hasProvidedInput {
                outStatus.pointee = .noDataNow
                return nil
            }

            hasProvidedInput = true
            outStatus.pointee = .haveData
            return sourceBuffer
        }

        if let conversionError {
            throw conversionError
        }

        guard status == .haveData || status == .inputRanDry else {
            throw NSError(
                domain: "SoundModeManager",
                code: 1004,
                userInfo: [NSLocalizedDescriptionKey: "音频转换未返回可播放数据"]
            )
        }

        if convertedBuffer.frameLength == 0 {
            throw NSError(
                domain: "SoundModeManager",
                code: 1005,
                userInfo: [NSLocalizedDescriptionKey: "转换后的音频长度为 0"]
            )
        }

        return convertedBuffer
    }

    private func makeFallbackBuffer(
        for mode: SoundMode,
        normalizedMagnitude: Double,
        sexyMomentum: Double = 0
    ) -> AVAudioPCMBuffer {
        let duration: Double
        if mode == .性感 {
            duration = 0.16 + normalizedMagnitude * 0.10 + sexyMomentum * 0.12
        } else {
            duration = 0.08 + normalizedMagnitude * 0.14
        }
        let frameCount = AVAudioFrameCount(playbackFormat.sampleRate * duration)
        let buffer = AVAudioPCMBuffer(pcmFormat: playbackFormat, frameCapacity: frameCount)!
        buffer.frameLength = frameCount
        let channel = buffer.floatChannelData![0]

        let baseFrequency: Double
        switch mode {
        case .性感: baseFrequency = 170 + normalizedMagnitude * 45 + sexyMomentum * 35
        case .经典: baseFrequency = 230 + normalizedMagnitude * 40
        case .动物: baseFrequency = 280 + normalizedMagnitude * 180
        case .惊喜: baseFrequency = 340 + normalizedMagnitude * 320
        }

        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / playbackFormat.sampleRate
            let progress = Double(frame) / Double(frameCount)
            if mode == .性感 {
                let glide = 1.0 + (0.12 + sexyMomentum * 0.08) * (1.0 - progress)
                let movingFrequency = baseFrequency * glide
                let envelope = pow(max(1.0 - progress, 0.0), 0.82 + sexyMomentum * 0.18)
                let body = sin(2.0 * .pi * movingFrequency * t)
                let air = sin(2.0 * .pi * (movingFrequency * 1.5) * t + 0.35) * (0.34 + sexyMomentum * 0.10)
                let shimmer = sin(2.0 * .pi * (movingFrequency * 2.02) * t) * 0.12 * progress
                let pulse = 0.82 + 0.18 * sin(2.0 * .pi * (3.2 + sexyMomentum * 1.4) * t)
                channel[frame] = Float((body * 0.52 + air * 0.34 + shimmer * 0.14) * envelope * pulse)
            } else {
                let envelope = exp(-progress * (5.4 - normalizedMagnitude * 1.6))
                let tone = sin(2.0 * .pi * baseFrequency * t)
                let harmonic = sin(2.0 * .pi * (baseFrequency * 2.3) * t) * (1 - progress)
                channel[frame] = Float((tone * 0.65 + harmonic * 0.35) * envelope)
            }
        }
        return buffer
    }

    private enum Keys {
        static let currentMode = "soundMode.currentMode"
        static let playbackCooldown = "soundMode.playbackCooldown"
        static let modeSettingsPrefix = "soundMode.settings"
    }

    private func updateSexyMomentum(now: TimeInterval, normalizedMagnitude: Double) -> Double {
        let decayed = decayedSexyMomentum(at: now)
        let cadenceBonus: Double
        if lastSexyHitTime > 0 {
            let interval = now - lastSexyHitTime
            cadenceBonus = max(0, (1.2 - min(interval, 1.2)) / 1.2) * 0.18
        } else {
            cadenceBonus = 0
        }

        let impulse = 0.05 + normalizedMagnitude * 0.18 + cadenceBonus * 0.85
        sexyMomentum = min(1.0, decayed + impulse)
        lastSexyMomentumUpdate = now
        lastSexyHitTime = now
        publishSexyState()
        return sexyMomentum
    }

    private func refreshSexyState(at now: TimeInterval) {
        sexyMomentum = decayedSexyMomentum(at: now)
        lastSexyMomentumUpdate = now
        publishSexyState()
    }

    private func decayedSexyMomentum(at now: TimeInterval) -> Double {
        guard lastSexyMomentumUpdate > 0 else { return sexyMomentum }
        if lastSexyHitTime > 0, now - lastSexyHitTime >= sexyIdleResetAfter {
            return 0
        }
        let elapsed = max(0, now - lastSexyMomentumUpdate)
        guard sexyMomentum > 0 else { return 0 }
        let decay = pow(0.5, elapsed / sexyDecayHalfLife)
        return sexyMomentum * decay
    }

    private func publishSexyState() {
        sexyStateValue = sexyMomentum
        switch sexyMomentum {
        case ..<0.30:
            sexyStateLabel = "冷静"
        case ..<0.56:
            sexyStateLabel = "升温"
        case ..<0.78:
            sexyStateLabel = "投入"
        default:
            sexyStateLabel = "炽热"
        }
    }
}
