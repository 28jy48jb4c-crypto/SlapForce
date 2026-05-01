import SwiftUI

struct ContentView: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var soundModeManager: SoundModeManager
    @EnvironmentObject private var monitor: SlapMonitor
    @EnvironmentObject private var power: PowerAssertionController

    var body: some View {
        GeometryReader { proxy in
            let compact = proxy.size.width < 1180

            ScrollView {
                VStack(spacing: 0) {
                    header
                    sensorBanner
                    Divider()
                    if compact {
                        VStack(alignment: .leading, spacing: 24) {
                            forcePanel(compact: true)
                            controlsPanel
                        }
                        .padding(20)
                    } else {
                        HStack(alignment: .top, spacing: 28) {
                            forcePanel(compact: false)
                            controlsPanel
                        }
                        .padding(24)
                    }
                }
            }
            .background(Color(nsColor: .windowBackgroundColor))
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
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("SlapForce")
                    .font(.system(size: 28, weight: .semibold))
                Text(monitor.isListening ? "监听中" : "未监听")
                    .font(.callout)
                    .foregroundStyle(monitor.isListening ? .green : .secondary)
            }
            Spacer()
            Button {
                NSLog("SlapForce: header Start/Stop button clicked")
                monitor.toggle()
            } label: {
                Label(monitor.isListening ? "停止监听" : "开始监听", systemImage: monitor.isListening ? "stop.fill" : "play.fill")
                    .frame(width: 150)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 18)
    }

    private var sensorBanner: some View {
        HStack(spacing: 10) {
            Image(systemName: monitor.isListening ? "checkmark.circle.fill" : "info.circle.fill")
                .foregroundStyle(monitor.isListening ? .green : .orange)
            Text("传感器状态：")
                .fontWeight(.semibold)
            Text(monitor.sensorStatus)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
            Spacer()
        }
        .font(.callout)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
        .background(monitor.isListening ? Color.green.opacity(0.08) : Color.orange.opacity(0.09))
    }

    private func forcePanel(compact: Bool) -> some View {
        VStack(spacing: 24) {
            ZStack {
                Circle()
                    .fill(RadialGradient(colors: [.red.opacity(0.16), .clear], center: .center, startRadius: 20, endRadius: 170))
                    .scaleEffect(1 + min(monitor.latestTriggerMagnitude / 6, 0.45))
                    .animation(.spring(response: 0.22, dampingFraction: 0.48), value: monitor.latestTriggerMagnitude)

                Gauge(value: min(monitor.latestImpact, 4), in: 0...4) {
                    Text("冲击值")
                } currentValueLabel: {
                    Text(monitor.latestImpact, format: .number.precision(.fractionLength(2)))
                        .font(.system(size: 40, weight: .bold, design: .rounded))
                }
                .gaugeStyle(.accessoryCircularCapacity)
                .scaleEffect(compact ? 2.0 : 2.4)
            }
            .frame(width: compact ? 260 : 320, height: compact ? 240 : 300)
            .frame(maxWidth: .infinity)

            LazyVGrid(columns: compact ? adaptiveMetricColumns(minimum: 88) : adaptiveMetricColumns(minimum: 72), spacing: 18) {
                AxisValue(label: "X", value: monitor.latestSample.x)
                AxisValue(label: "Y", value: monitor.latestSample.y)
                AxisValue(label: "Z", value: monitor.latestSample.z)
            }

            LazyVGrid(columns: compact ? adaptiveMetricColumns(minimum: 110) : adaptiveMetricColumns(minimum: 92), spacing: 18) {
                MetricTile(title: "触发次数", value: "\(monitor.eventCount)")
                MetricTile(title: "音量", value: String(format: "%.0f%%", soundModeManager.lastVolume * 100))
                MetricTile(title: "音调", value: String(format: "%.0f", soundModeManager.lastPitch))
                MetricTile(title: "当前档位", value: soundModeManager.lastTriggerTierName)
                MetricTile(title: "触发锁定", value: monitor.triggerStateLabel)
                MetricTile(title: "启动次数", value: "\(monitor.startAttempts)")
                MetricTile(title: "静止基线", value: String(format: "%.2f", monitor.baselineMagnitude))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var controlsPanel: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 10) {
                Text("声音模式")
                    .font(.headline)
                Picker("模式", selection: $soundModeManager.currentMode) {
                    ForEach(SoundMode.allCases) { mode in
                        Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                    }
                }
                Text(soundModeManager.currentMode.summary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if soundModeManager.currentMode == .性感 {
                    HStack(spacing: 8) {
                        Text("性感状态")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(soundModeManager.sexyStateLabel)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                        Text(String(format: "%.0f%%", soundModeManager.sexyStateValue * 100))
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    HStack(spacing: 8) {
                        Text("素材层级")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(soundModeManager.sexySourceLayerLabel)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                    HStack(spacing: 8) {
                        Text("素材分层")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(soundModeManager.sexyLibraryLayerSummary)
                            .font(.caption)
                            .fontWeight(.semibold)
                        Spacer()
                    }
                }
                HStack {
                    Button {
                        soundModeManager.openModeLibraryFolder()
                    } label: {
                        Label("打开音效库", systemImage: "folder")
                    }
                    Button {
                        soundModeManager.rebuildLibrary()
                    } label: {
                        Label("重新扫描", systemImage: "arrow.clockwise")
                    }
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text("原始片段")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(soundModeManager.lastSourceClipName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("派生版本")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(soundModeManager.lastVariantName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("播放状态")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(soundModeManager.playbackStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("触发调试")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("状态：\(monitor.triggerStateLabel)")
                        Text("最近触发：\(monitor.lastTriggerTimeLabel)")
                        Text("最近主峰：\(String(format: "%.3f", monitor.latestTriggerMagnitude))")
                        Text("已忽略次峰：\(monitor.ignoredSecondaryPeakCount)")
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("音效库状态")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(soundModeManager.libraryStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }

                VStack(alignment: .leading, spacing: 14) {
                    Text("模式参数")
                        .font(.headline)

                    Text(soundModeManager.currentConfigSummary())
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    SliderRow(
                        title: "基础音量",
                        value: $soundModeManager.editableBaseVolume,
                        range: 0.1...1.4,
                        format: "%.2f",
                        help: "决定该模式的起始音量。"
                    )

                    SliderRow(
                        title: "力度增益",
                        value: $soundModeManager.editableIntensityScale,
                        range: 0.1...2.0,
                        format: "%.2f",
                        help: "力度越大，对音量和音调的放大越明显。"
                    )

                    SliderRow(
                        title: "最低音调",
                        value: $soundModeManager.editablePitchLower,
                        range: -600...600,
                        format: "%.0f",
                        help: "轻力度时优先落在这个音调附近。"
                    )

                    SliderRow(
                        title: "最高音调",
                        value: $soundModeManager.editablePitchUpper,
                        range: -600...600,
                        format: "%.0f",
                        help: "重力度时会逼近这个音调。"
                    )

                    SliderRow(
                        title: "播放冷却",
                        value: $soundModeManager.editablePlaybackCooldown,
                        range: 0.02...0.40,
                        format: "%.2fs",
                        help: "降低可以更跟手，升高可以减少连发堆叠。"
                    )
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                Text("检测参数")
                    .font(.headline)

                SliderRow(
                    title: "灵敏度",
                    value: $settings.sensitivity,
                    range: 0.02...1.5,
                    format: "%.2f",
                    help: "越低越容易触发轻拍。"
                )

                SliderRow(
                    title: "检测冷却",
                    value: $settings.cooldown,
                    range: 0.05...1.5,
                    format: "%.2fs",
                    help: "两次拍打触发之间的最短间隔。"
                )

                Toggle(isOn: $settings.keepAwakeWhileListening) {
                    Label("监听时阻止系统休眠", systemImage: power.isActive ? "bolt.fill" : "bolt")
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("传感器状态")
                        .font(.subheadline)
                        .fontWeight(.semibold)
                    Text(monitor.sensorStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }
        .frame(maxWidth: 360, alignment: .leading)
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
                Text("SlapForce")
                    .font(.headline)
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

            Button {
                monitor.configure(settings: settings, soundModeManager: soundModeManager)
                monitor.toggle()
                power.update(shouldKeepAwake: settings.keepAwakeWhileListening, isListening: monitor.isListening)
            } label: {
                Label(monitor.isListening ? "停止监听" : "开始监听", systemImage: monitor.isListening ? "stop.fill" : "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Gauge(value: min(monitor.latestImpact, 4), in: 0...4) {
                Text("冲击值")
            } currentValueLabel: {
                Text(monitor.latestImpact, format: .number.precision(.fractionLength(2)))
            }

            Picker("模式", selection: $soundModeManager.currentMode) {
                ForEach(SoundMode.allCases) { mode in
                    Label(mode.displayName, systemImage: mode.systemImage).tag(mode)
                }
            }

            HStack {
                Text("当前档位")
                Spacer()
                Text(soundModeManager.lastTriggerTierName)
                    .foregroundStyle(.secondary)
            }

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
}

private struct AxisValue: View {
    let label: String
    let value: Double

    var body: some View {
        VStack(spacing: 6) {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value, format: .number.precision(.fractionLength(2)))
                .font(.system(.title3, design: .monospaced))
        }
        .frame(minWidth: 72, maxWidth: .infinity, minHeight: 64)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private struct MetricTile: View {
    let title: String
    let value: String

    var body: some View {
        VStack(spacing: 6) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.headline)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .frame(minWidth: 92, maxWidth: .infinity, minHeight: 68)
        .background(.tertiary, in: RoundedRectangle(cornerRadius: 8))
    }
}

private func adaptiveMetricColumns(minimum: CGFloat) -> [GridItem] {
    [GridItem(.adaptive(minimum: minimum, maximum: 180), spacing: 18)]
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
