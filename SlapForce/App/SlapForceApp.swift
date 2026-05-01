import SwiftUI

@main
struct SlapForceApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @StateObject private var settings = AppSettings()
    @StateObject private var soundModeManager = SoundModeManager()
    @StateObject private var monitor = SlapMonitor()
    @StateObject private var power = PowerAssertionController()

    var body: some Scene {
        MenuBarExtra("SlapForce", systemImage: monitor.isListening ? "waveform.path.ecg" : "hand.raised") {
            MenuBarPanel()
                .environmentObject(settings)
                .environmentObject(soundModeManager)
                .environmentObject(monitor)
                .environmentObject(power)
        }
        .menuBarExtraStyle(.window)

        WindowGroup("SlapForce") {
            ContentView()
                .environmentObject(settings)
                .environmentObject(soundModeManager)
                .environmentObject(monitor)
                .environmentObject(power)
                .frame(minWidth: 620, minHeight: 430)
                .onAppear {
                    monitor.configure(settings: settings, soundModeManager: soundModeManager)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appInfo) {
                Button("About SlapForce") {
                    NSApplication.shared.orderFrontStandardAboutPanel()
                }
            }
        }
    }
}
