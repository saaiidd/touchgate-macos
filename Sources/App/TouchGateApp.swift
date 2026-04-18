import SwiftUI

// SDK: macOS 15 (Sequoia) — minimum deployment target: macOS 13.0 (Ventura)
// Concurrency: async/await throughout; @MainActor for all UI state; actors for storage/auth.
// Menu bar: NSStatusItem + NSPopover (not MenuBarExtra) for full popover dismiss control.
// LIMITATION: App interception is terminate-and-relaunch, not pre-launch blocking.

@main
struct TouchGateApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // The only SwiftUI scene is Settings — the menu bar is driven by NSStatusItem in AppDelegate.
        Settings {
            SettingsView()
                .environmentObject(appDelegate.appState)
        }
    }
}
