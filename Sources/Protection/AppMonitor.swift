import AppKit
import OSLog

// Observes NSWorkspace for app launches and routes protected ones through InterceptionHandler.
// LIMITATION: NSWorkspace notifications fire after the app has already launched.
// We cannot intercept a launch before it occurs at the user-space level.
// @MainActor ensures all AppState access (which is @MainActor) is safe without async/await.
// NSWorkspace notifications are delivered on the main thread, so this isolation matches reality.
@MainActor
final class AppMonitor {
    private weak var appState: AppState?
    private let interceptionHandler: InterceptionHandler

    private static let log = Logger(subsystem: "com.touchgate.app", category: "AppMonitor")

    // The token returned by the closure-based observer; kept alive for the observer's lifetime.
    private var observerToken: Any?
    // Second observer: system wake notification, used to reset Relaxed mode session state.
    private var wakeObserverToken: Any?

    // Debounce map: prevents hammering auth prompts if an app crashes and relaunches rapidly.
    // Keyed by bundle identifier; value is the last interception timestamp.
    private var lastInterceptionTime: [String: Date] = [:]
    private static let debounceInterval: TimeInterval = 2.0

    // One-shot set of bundle IDs that just authenticated and are waiting for their relaunch.
    //
    // ROOT CAUSE OF THE INFINITE-LOOP BUG:
    //   When unlockTimeout == 0 ("Always require Touch ID"), isCurrentlyUnlocked always returns
    //   false — even immediately after a successful auth — because the timeout guard fails.
    //   So when the app is relaunched after auth, the next didLaunchApplicationNotification
    //   sees it as locked again and terminates it, prompting infinitely.
    //
    // FIX: After a successful auth we insert the bundle ID here BEFORE calling NSWorkspace.open.
    //   The very next launch notification for that ID skips interception and removes it from the
    //   set. This allows exactly one post-auth relaunch regardless of the timeout setting.
    private var justAuthenticated: Set<String> = []

    init(appState: AppState, interceptionHandler: InterceptionHandler) {
        self.appState = appState
        self.interceptionHandler = interceptionHandler
    }

    func start() {
        let trusted = AXIsProcessTrusted()
        let appCount = self.appState?.protectedApps.count ?? -1
        Self.log.info("AppMonitor starting. Accessibility trusted: \(trusted, privacy: .public). Protected apps: \(appCount, privacy: .public)")

        // Closure-based API does not require NSObject inheritance, unlike addObserver(_:selector:...).
        observerToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main   // notifications arrive on the main thread
        ) { [weak self] notification in
            // queue: .main guarantees main thread; assumeIsolated satisfies the compiler without
            // a Task allocation on every launch notification.
            MainActor.assumeIsolated {
                self?.appDidLaunch(notification)
            }
        }

        // System wake resets the Relaxed mode session set. No-op for Balanced/Strict
        // (they don't consult sessionUnlockedApps). Registered on the workspace
        // notification center, same thread as launch notifications.
        wakeObserverToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.appState?.clearSessionUnlocks()
            }
        }

        Self.log.info("AppMonitor observer registered.")
    }

    func stop() {
        if let token = observerToken {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            observerToken = nil
        }
        if let token = wakeObserverToken {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
            wakeObserverToken = nil
        }
    }

    // Called on the main thread by the notification center.
    private func appDidLaunch(_ notification: Notification) {
        guard
            let runningApp = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
            let bundleId = runningApp.bundleIdentifier,
            let appState
        else { return }

        Self.log.info("Launch detected: \(bundleId, privacy: .public)")

        guard appState.isProtected(bundleIdentifier: bundleId) else { return }

        Self.log.info("Protected app intercepted: \(bundleId, privacy: .public)")

        // Allow the one post-auth relaunch through — this handles the unlockTimeout == 0 case
        // where isCurrentlyUnlocked would incorrectly return false right after authentication.
        if justAuthenticated.contains(bundleId) {
            justAuthenticated.remove(bundleId)
            Self.log.info("Post-auth relaunch — allowing through: \(bundleId, privacy: .public)")
            return
        }

        // Central authentication decision. The ONLY place that decides if a launch needs
        // auth — all mode-specific logic (Relaxed session, Balanced timeout, Strict) lives
        // inside AppState.requiresAuthentication(for:).
        let needsAuth = appState.requiresAuthentication(for: bundleId)
        let modeStr = String(describing: appState.securityMode)
        Self.log.info("requiresAuthentication=\(needsAuth, privacy: .public) mode=\(modeStr, privacy: .public) bundleId=\(bundleId, privacy: .public)")
        guard needsAuth else { return }

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

        Self.log.info("Dispatching interception for: \(bundleId, privacy: .public)")

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
                // Mark this bundle ID as just-authenticated BEFORE calling open(), so the
                // incoming didLaunchApplicationNotification is allowed through unconditionally.
                Self.log.info("Auth succeeded for \(bundleId, privacy: .public) — relaunching")
                self.justAuthenticated.insert(bundleId)
                await appState.recordUnlock(bundleIdentifier: bundleId)
                NSWorkspace.shared.open(bundleURL)

            case .cancelled:
                Self.log.info("Auth cancelled for \(bundleId, privacy: .public)")
            case .failed:
                Self.log.info("Auth failed for \(bundleId, privacy: .public)")
            case .alreadyPending:
                Self.log.info("Auth already pending for \(bundleId, privacy: .public)")
            }
        }
    }
}
