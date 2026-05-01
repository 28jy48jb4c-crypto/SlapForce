import SwiftUI

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()

    let settings = AppSettings()
    let soundModeManager = SoundModeManager()
    let monitor = SlapMonitor()
    let power = PowerAssertionController()

    private init() {}

    @MainActor
    func makeMainView() -> some View {
        ContentView()
            .environmentObject(settings)
            .environmentObject(soundModeManager)
            .environmentObject(monitor)
            .environmentObject(power)
            .frame(minWidth: 620, minHeight: 430)
            .onAppear {
                self.monitor.configure(settings: self.settings, soundModeManager: self.soundModeManager)
            }
    }

    @MainActor
    func makeMenuBarPanel() -> some View {
        MenuBarPanel()
            .environmentObject(settings)
            .environmentObject(soundModeManager)
            .environmentObject(monitor)
            .environmentObject(power)
    }
}

@main
struct SlapForceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var settings: AppSettings
    @StateObject private var soundModeManager: SoundModeManager
    @StateObject private var monitor: SlapMonitor
    @StateObject private var power: PowerAssertionController

    init() {
        let runtime = AppRuntime.shared
        _settings = StateObject(wrappedValue: runtime.settings)
        _soundModeManager = StateObject(wrappedValue: runtime.soundModeManager)
        _monitor = StateObject(wrappedValue: runtime.monitor)
        _power = StateObject(wrappedValue: runtime.power)
    }

    var body: some Scene {
        MenuBarExtra("SlapForce", systemImage: monitor.isListening ? "waveform.path.ecg" : "hand.raised") {
            AppRuntime.shared.makeMenuBarPanel()
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(after: .newItem) {
                Button("显示主窗口") {
                    appDelegate.showMainWindow()
                }
                .keyboardShortcut("1", modifiers: [.command])
            }

            CommandGroup(replacing: .appInfo) {
                Button("About SlapForce") {
                    NSApplication.shared.orderFrontStandardAboutPanel()
                }
            }
        }
    }
}
