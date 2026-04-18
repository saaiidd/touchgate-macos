import AppKit

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appState = AppState()
    private var statusBarController: StatusBarController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Belt-and-suspenders: Info.plist sets LSUIElement=YES, this confirms it at runtime.
        NSApp.setActivationPolicy(.accessory)

        statusBarController = StatusBarController(appState: appState)

        Task {
            await appState.loadProtectedApps()
            appState.startMonitoring()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        appState.stopMonitoring()
    }
}
