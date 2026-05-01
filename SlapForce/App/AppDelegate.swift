import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Debug-friendly mode: show the Dock icon and bring SlapForce forward
        // when launched from Xcode. The menu-bar panel still remains available.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
            NSApplication.shared.sendAction(#selector(NSWindow.newWindowForTab(_:)), to: nil, from: nil)
            NSApplication.shared.windows.first(where: { $0.canBecomeMain })?.makeKeyAndOrderFront(nil)
            NSApplication.shared.activate(ignoringOtherApps: true)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}
