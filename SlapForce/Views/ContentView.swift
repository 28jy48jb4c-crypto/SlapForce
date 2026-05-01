import SwiftUI

private struct ModePalette {
    let accent: Color
    let secondary: Color
    let glow: Color
}

private extension SoundMode {
    var palette: ModePalette {
        switch self {
        case .性感:
            return ModePalette(accent: .pink, secondary: .purple, glow: Color(red: 1.0, green: 0.55, blue: 0.78))
        case .经典:
            return ModePalette(accent: .blue, secondary: .cyan, glow: Color(red: 0.34, green: 0.63, blue: 1.0))
        case .动物:
            return ModePalette(accent: .orange, secondary: .green, glow: Color(red: 0.98, green: 0.67, blue: 0.28))
        case .惊喜:
            return ModePalette(accent: .yellow, secondary: .mint, glow: Color(red: 0.96, green: 0.82, blue: 0.25))
        }
    }
}

struct ContentView: View {
    private enum DashboardPanel: String, CaseIterable, Identifiable {
        case 参数
        case 状态
        case 调试

        var id: String { rawValue }
    }

    @Environment(\.colorScheme) private var colorScheme
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var soundModeManager: SoundModeManager
    @EnvironmentObject private var monitor: SlapMonitor
    @EnvironmentObject private var power: PowerAssertionController

    @State private var showAdvancedTuning = false
    @State private var showDebug = false
    @State private var selectedPanel: DashboardPanel = .参数

    private var palette: ModePalette { soundModeManager.currentMode.palette }
    private var normalizedImpact: Double { min(max(monitor.latestImpact / 4.0, 0), 1) }

    var body: some View {
        ZStack {
            backgroundLayer

            GeometryReader { geometry in
                ScrollView(.vertical, showsIndicators: true) {
                    VStack(spacing: 12) {
                        compactTopSection(compactWidth: geometry.size.width < 860)
                        compactControlDeck
                    }
                    .padding(14)
                    .frame(minHeight: geometry.size.height, alignment: .top)
                }
            }
        }
        .onAppear {
            monitor.configure(settings: settings, soundModeManager: soundModeManager)
        }
        .onChange(of: monitor.isListening) {
            power.update(shouldKeepAwake: settings.keepAwakeWhileListening, isListening: monitor.isListening)
        }
        .onChange(of: settings.keepAwakeWhileListening) {
            power.update(shouldKeepAwake: settings.keepAwakeWhileListening, isListening: monitor.isListening)
        }
        .animation(.easeInOut(duration: 0.25), value: soundModeManager.currentMode)
        .animation(.spring(response: 0.36, dampingFraction: 0.82), value: monitor.latestImpact)
    }

    private var backgroundLayer: some View {
        LinearGradient(
            colors: [
                palette.accent.opacity(colorScheme == .dark ? 0.28 : 0.20),
                palette.secondary.opacity(colorScheme == .dark ? 0.22 : 0.14),
                Color(nsColor: .windowBackgroundColor)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay(alignment: .topTrailing) {
            Circle()
                .fill(palette.glow.opacity(colorScheme == .dark ? 0.22 : 0.16))
                .frame(width: 320, height: 320)
                .blur(radius: 90)
                .offset(x: 120, y: -100)
        }
    }

    @ViewBuilder
    private func compactTopSection(compactWidth: Bool) -> some View {
        if compactWidth {
            VStack(spacing: 12) {
                heroSection
                impactSection
            }
        } else {
            HStack(alignment: .top, spacing: 12) {
                heroSection
                impactSection
                    .frame(width: 290)
            }
        }
    }

    private var heroSection: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("SlapForce")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)

                        Text(soundModeManager.currentMode.displayName)
                            .font(.system(size: 30, weight: .bold, design: .rounded))
                            .foregroundStyle(.primary)

                        Text(soundModeManager.currentMode.summary)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    statusBadge(
                        title: monitor.isListening ? "监听中" : "已停止",
                        systemImage: monitor.isListening ? "waveform.path.ecg" : "pause.fill",
                        tint: monitor.isListening ? .green : .secondary
                    )
                }

                HStack(spacing: 10) {
                    Button {
                        soundModeManager.openModeLibraryFolder()
                    } label: {
                        Label("音效库", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        soundModeManager.rebuildLibrary()
                    } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)

                    Spacer()

                    Button {
                        monitor.toggle()
                    } label: {
                        Label(monitor.isListening ? "停止监听" : "开始监听", systemImage: monitor.isListening ? "stop.fill" : "play.fill")
                            .frame(minWidth: 128)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(palette.accent)
                }

                modeSwitcherSection
            }
        }
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            palette.accent.opacity(colorScheme == .dark ? 0.20 : 0.14),
                            palette.secondary.opacity(colorScheme == .dark ? 0.18 : 0.12),
                            .clear
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
    }

    private var impactSection: some View {
        card {
            VStack(spacing: 12) {
                HStack(alignment: .center, spacing: 14) {
                    ZStack {
                        Circle()
                            .stroke(Color.primary.opacity(0.10), lineWidth: 16)

                        Circle()
                            .trim(from: 0, to: normalizedImpact)
                            .stroke(
                                AngularGradient(
                                    colors: [palette.secondary, palette.accent, palette.glow],
                                    center: .center
                                ),
                                style: StrokeStyle(lineWidth: 16, lineCap: .round)
                            )
                            .rotationEffect(.degrees(-90))
                            .shadow(color: palette.accent.opacity(0.35), radius: 12, y: 5)

                        Circle()
                            .fill(.ultraThinMaterial)
                            .padding(24)

                        VStack(spacing: 2) {
                            Text(monitor.latestImpact, format: .number.precision(.fractionLength(2)))
                                .font(.system(size: 30, weight: .bold, design: .rounded))
                            Text("力度")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 156, height: 156)

                    VStack(spacing: 8) {
                        statChip(title: "档位", value: soundModeManager.lastTriggerTierName)
                        statChip(title: "音量", value: String(format: "%.0f%%", soundModeManager.lastVolume * 100))
                        statChip(title: "音调", value: String(format: "%.0f", soundModeManager.lastPitch))
                        statChip(title: "事件", value: "\(monitor.eventCount)")
                    }
                }

                HStack(spacing: 8) {
                    axisChip(label: "X", value: monitor.latestSample.x)
                    axisChip(label: "Y", value: monitor.latestSample.y)
                    axisChip(label: "Z", value: monitor.latestSample.z)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private var modeSwitcherSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("模式切换")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(SoundMode.allCases) { mode in
                    modeButton(mode)
                }
            }
        }
    }

    private var compactControlDeck: some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                Picker("面板", selection: $selectedPanel) {
                    ForEach(DashboardPanel.allCases) { panel in
                        Text(panel.rawValue).tag(panel)
                    }
                }
                .pickerStyle(.segmented)

                Group {
                    switch selectedPanel {
                    case .参数:
                        compactSection("参数") {
                            SliderRow(title: "灵敏度", value: $settings.sensitivity, range: 0.02...1.5, format: "%.2f", help: "越低越容易触发轻拍。")
                            SliderRow(title: "检测冷却", value: $settings.cooldown, range: 0.05...1.5, format: "%.2fs", help: "两次拍打之间的最短检测间隔。")
                            SliderRow(title: "基础音量", value: $soundModeManager.editableBaseVolume, range: 0.1...1.4, format: "%.2f", help: "决定模式的起始音量。")
                            SliderRow(title: "力度增益", value: $soundModeManager.editableIntensityScale, range: 0.1...2.0, format: "%.2f", help: "力度越大，声音变化越明显。")
                            Toggle(isOn: $settings.keepAwakeWhileListening) {
                                Label("阻止休眠", systemImage: power.isActive ? "bolt.fill" : "bolt")
                            }
                            .font(.subheadline)
                        }
                    case .状态:
                        compactSection("状态") {
                            infoRow("播放状态", soundModeManager.playbackStatus)
                            infoRow("当前片段", soundModeManager.lastSourceClipName)
                            infoRow("派生版本", soundModeManager.lastVariantName)
                            infoRow("当前层级", soundModeManager.currentMode == .性感 ? soundModeManager.sexySourceLayerLabel : soundModeManager.currentSourceLayerLabel)
                            infoRow("当前窗口", soundModeManager.currentMode == .性感 ? soundModeManager.sexySelectionWindowLabel : soundModeManager.currentSelectionWindowLabel)
                            if soundModeManager.currentMode == .性感 {
                                infoRow("性感状态", "\(soundModeManager.sexyStateLabel)  \(String(format: "%.0f%%", soundModeManager.sexyStateValue * 100))")
                            }
                            infoRow("传感器状态", monitor.sensorStatus)
                        }
                    case .调试:
                        compactSection("调试") {
                            infoRow("STA / LTA", "\(String(format: "%.3f", monitor.staValue)) / \(String(format: "%.3f", monitor.ltaValue))")
                            infoRow("Ratio", String(format: "%.2f", monitor.staLtaRatio))
                            infoRow("Confidence", String(format: "%.0f%%", monitor.detectionConfidence * 100))
                            infoRow("滤波冲击", String(format: "%.3f", monitor.filteredMagnitude))
                            infoRow("锁定状态", monitor.triggerStateLabel)
                            infoRow("最近触发", monitor.lastTriggerTimeLabel)

                            DisclosureGroup("检测参数", isExpanded: $showAdvancedTuning) {
                                VStack(alignment: .leading, spacing: 10) {
                                    SliderRow(title: "低通 Alpha", value: tuningBinding(\.lowPassAlpha), range: 0.01...0.40, format: "%.3f", help: "估计重力分量。")
                                    SliderRow(title: "包络平滑", value: tuningBinding(\.envelopeSmoothing), range: 0.01...0.60, format: "%.3f", help: "冲击包络平滑程度。")
                                    SliderRow(title: "STA 窗口", value: tuningBinding(\.staWindowMs), range: 12...180, format: "%.0fms", help: "短时平均窗口。")
                                    SliderRow(title: "LTA 窗口", value: tuningBinding(\.ltaWindowMs), range: 120...1800, format: "%.0fms", help: "长时平均窗口。")
                                    SliderRow(title: "触发比值", value: tuningBinding(\.triggerRatio), range: 1.10...8.0, format: "%.2f", help: "STA/LTA 触发阈值。")
                                    SliderRow(title: "重置比值", value: tuningBinding(\.rearmRatio), range: 0.80...4.0, format: "%.2f", help: "重新武装阈值。")
                                    SliderRow(title: "绝对门限", value: tuningBinding(\.absoluteFloor), range: 0.005...1.0, format: "%.3f", help: "最小冲击门限。")
                                    SliderRow(title: "去重冷却", value: tuningBinding(\.sensorDedupeCooldown), range: 0.03...0.50, format: "%.2fs", help: "压制回弹二次触发。")
                                }
                                .padding(.top, 8)
                            }
                            .tint(palette.accent)

                            DisclosureGroup("播放调试", isExpanded: $showDebug) {
                                VStack(alignment: .leading, spacing: 8) {
                                    infoRow("音效库状态", soundModeManager.libraryStatus)
                                    infoRow("忽略次峰", "\(monitor.ignoredSecondaryPeakCount)")
                                    infoRow("最近主峰", String(format: "%.3f", monitor.latestTriggerMagnitude))
                                }
                                .padding(.top, 8)
                            }
                            .tint(palette.secondary)
                        }
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private func modeButton(_ mode: SoundMode) -> some View {
        let buttonPalette = mode.palette
        let selected = soundModeManager.currentMode == mode

        return Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                soundModeManager.currentMode = mode
            }
        } label: {
            VStack(spacing: 6) {
                Image(systemName: mode.systemImage)
                    .font(.subheadline)
                Text(mode.displayName)
                    .font(.caption.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? buttonPalette.accent.opacity(colorScheme == .dark ? 0.32 : 0.20) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(selected ? buttonPalette.accent.opacity(0.9) : Color.primary.opacity(0.10), lineWidth: selected ? 1.4 : 1)
            )
            .foregroundStyle(selected ? buttonPalette.accent : .primary)
        }
        .buttonStyle(.plain)
    }

    private func compactSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(14)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06), lineWidth: 1)
            )
            .shadow(color: .black.opacity(colorScheme == .dark ? 0.18 : 0.08), radius: 18, y: 10)
    }

    private func statChip(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .monospaced))
                .fontWeight(.medium)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func axisChip(label: String, value: Double) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value, format: .number.precision(.fractionLength(2)))
                .font(.system(.subheadline, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func infoRow(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer(minLength: 12)
            Text(value)
                .multilineTextAlignment(.trailing)
                .lineLimit(4)
                .textSelection(.enabled)
        }
        .font(.callout)
    }

    private func statusBadge(title: String, systemImage: String, tint: Color) -> some View {
        Label(title, systemImage: systemImage)
            .font(.callout.weight(.medium))
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(tint.opacity(0.15), in: Capsule())
            .foregroundStyle(tint)
    }

    private func tuningBinding(_ keyPath: WritableKeyPath<DetectionTuning, Double>) -> Binding<Double> {
        Binding(
            get: { settings.detectionTuning[keyPath: keyPath] },
            set: { newValue in
                var tuning = settings.detectionTuning
                tuning[keyPath: keyPath] = newValue
                settings.detectionTuning = tuning
            }
        )
    }
}

struct MenuBarPanel: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var soundModeManager: SoundModeManager
    @EnvironmentObject private var monitor: SlapMonitor
    @EnvironmentObject private var power: PowerAssertionController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SlapForce")
                        .font(.headline)
                    Text(monitor.isListening ? "正在监听" : "已停止")
                        .font(.caption)
                        .foregroundStyle(monitor.isListening ? .green : .secondary)
                }
                Spacer()
                Button {
                    NSApp.activate(ignoringOtherApps: true)
                    NSApp.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
                    monitor.configure(settings: settings, soundModeManager: soundModeManager)
                } label: {
                    Image(systemName: "macwindow")
                }
                .help("打开主窗口")
            }

            Text(monitor.sensorStatus)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            Button {
                monitor.configure(settings: settings, soundModeManager: soundModeManager)
                monitor.toggle()
                power.update(shouldKeepAwake: settings.keepAwakeWhileListening, isListening: monitor.isListening)
            } label: {
                Label(monitor.isListening ? "停止监听" : "开始监听", systemImage: monitor.isListening ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Picker("模式", selection: $soundModeManager.currentMode) {
                ForEach(SoundMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                }
            }

            summaryRow(title: "冲击值", value: String(format: "%.2f", monitor.latestImpact))
            summaryRow(title: "当前档位", value: soundModeManager.lastTriggerTierName)
            summaryRow(title: "当前层级", value: soundModeManager.currentMode == .性感 ? soundModeManager.sexySourceLayerLabel : soundModeManager.currentSourceLayerLabel)

            SliderRow(title: "灵敏度", value: $settings.sensitivity, range: 0.02...1.5, format: "%.2f", help: "")
            SliderRow(title: "检测冷却", value: $settings.cooldown, range: 0.05...1.5, format: "%.2fs", help: "")

            Divider()
            Button("退出 SlapForce") {
                power.release()
                NSApplication.shared.terminate(nil)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            monitor.configure(settings: settings, soundModeManager: soundModeManager)
        }
    }

    private func summaryRow(title: String, value: String) -> some View {
        HStack {
            Text(title)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .lineLimit(2)
                .multilineTextAlignment(.trailing)
        }
        .font(.callout)
    }
}

private struct SliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: String
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(title)
                Spacer()
                Text(String(format: format, value))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Slider(value: $value, in: range)
        }
        .help(help)
    }
}
