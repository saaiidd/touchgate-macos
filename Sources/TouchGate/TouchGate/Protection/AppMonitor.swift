import AppKit

// Observes NSWorkspace for app launches and routes protected ones through InterceptionHandler.
// LIMITATION: NSWorkspace notifications fire after the app has already launched.
// We cannot intercept a launch before it occurs at the user-space level.
final class AppMonitor {
    private weak var appState: AppState?
    private let interceptionHandler: InterceptionHandler

    // The token returned by the closure-based observer; kept alive for the observer's lifetime.
    private var observerToken: Any?

    // Debounce map: prevents hammering auth prompts if an app crashes and relaunches rapidly.
    // Keyed by bundle identifier; value is the last interception timestamp.
    private var lastInterceptionTime: [String: Date] = [:]
    private static let debounceInterval: TimeInterval = 2.0

    init(appState: AppState, interceptionHandler: InterceptionHandler) {
        self.appState = appState
        self.interceptionHandler = interceptionHandler
    }

    func start() {
        // Closure-based API does not require NSObject inheritance, unlike addObserver(_:selector:...).
        observerToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main   // notifications arrive on the main thread
        ) { [weak self] notification in
            self?.appDidLaunch(notification)
        }
    }

    func stop() {
        if let token = observerToken {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            observerToken = nil
        }
    }

    // Called on the main thread by the notification center.
    private func appDidLaunch(_ notification: Notification) {
        guard
            let runningApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            let bundleId = runningApp.bundleIdentifier,
            let appState
        else { return }

        // Allow if not protected or already within grace period.
        guard appState.isProtected(bundleIdentifier: bundleId) else { return }
        guard !appState.isUnlocked(bundleIdentifier: bundleId) else { return }

        // Debounce — if we intercepted this app very recently, don't pile on another auth prompt.
        let now = Date()
        if let last = lastInterceptionTime[bundleId],
           now.timeIntervalSince(last) < Self.debounceInterval {
            // Silently terminate the rapid relaunch attempt.
            runningApp.forceTerminate()
            return
        }
        lastInterceptionTime[bundleId] = now

        guard let protectedApp = appState.protectedApp(for: bundleId) else { return }

        // Capture the bundle URL before termination so we can relaunch later.
        let bundleURL = URL(fileURLWithPath: protectedApp.bundlePath)

        Task { @MainActor [weak self] in
            guard let self, let appState = self.appState else { return }

            let result = await self.interceptionHandler.intercept(
                runningApp: runningApp,
                protectedApp: protectedApp
            )

            switch result {
            case .unlocked:
                // SECURITY: Record the unlock timestamp BEFORE relaunching so the
                // incoming didLaunchApplicationNotification sees the grace period as active.
                await appState.recordUnlock(bundleIdentifier: bundleId)
                NSWorkspace.shared.open(bundleURL)

            case .cancelled, .failed, .alreadyPending:
                break
            }
        }
    }
}
