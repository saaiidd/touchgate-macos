import AppKit
import LocalAuthentication

actor InterceptionHandler {

    enum InterceptionResult {
        case unlocked
        case cancelled      // User dismissed auth
        case failed         // Auth rejected or error
        case alreadyPending // Second launch while first auth is in progress
    }

    private var pendingAuthentications: Set<String> = []
    private let authManager: AuthenticationManager
    private let logger: UnlockLogger

    /// Weak reference to the currently-visible intent prompt, so tearDown() can cancel it.
    private weak var activePromptWindow: IntentPromptWindow?

    init(authManager: AuthenticationManager, logger: UnlockLogger) {
        self.authManager = authManager
        self.logger = logger
    }

    /// Cancel any in-flight intent prompt and resolve its continuation cleanly.
    /// Called from applicationWillTerminate so the process can exit without leaving a dangling
    /// continuation or showing a zombie window.
    func tearDown() {
        let panel = activePromptWindow
        Task { @MainActor in
            panel?.viewModel.cancel()
        }
    }

    func intercept(
        runningApp: NSRunningApplication,
        protectedApp: ProtectedApp
    ) async -> InterceptionResult {
        let bundleId = protectedApp.bundleIdentifier

        // Second launch of the same protected app while auth is pending — kill it silently
        // so the user only sees one prompt.
        if pendingAuthentications.contains(bundleId) {
            runningApp.forceTerminate()
            return .alreadyPending
        }

        pendingAuthentications.insert(bundleId)
        defer { pendingAuthentications.remove(bundleId) }

        // SECURITY: Terminate immediately before the app fully initialises.
        // LIMITATION: The app will briefly appear on screen — unavoidable at user-space level.
        _ = runningApp.terminate()

        // Give the app 500 ms to exit gracefully, then force-kill.
        try? await Task.sleep(nanoseconds: 500_000_000)
        if !runningApp.isTerminated {
            runningApp.forceTerminate()
        }

        // Extra 300 ms to ensure the process is fully gone before we relaunch.
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Bring TouchGate forward so the intent panel (and later the auth sheet) appear on top.
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }

        // ── Intent Journaling ─────────────────────────────────────────────────────────────────
        // Show a 3-second "Why are you opening this?" panel before Touch ID fires.
        // nil return  → "Don't Open": skip authentication entirely.
        // ""  return  → timer elapsed or user skipped: proceed to Touch ID with empty reason.
        // non-empty   → user typed an intent: proceed to Touch ID and log the reason.
        let intentReason: String? = await {
            let panel = await MainActor.run {
                let icon = protectedApp.iconData.flatMap { NSImage(data: $0) }
                return IntentPromptWindow(appName: protectedApp.displayName, appIcon: icon)
            }
            // Store weak ref for tearDown().
            self.activePromptWindow = panel
            let result = await panel.promptAndWait()
            self.activePromptWindow = nil
            return result
        }()

        guard let reason = intentReason else {
            // User chose "Don't Open" — record the refusal and bail.
            await logger.log(appName: protectedApp.displayName, success: false, reason: nil)
            return .cancelled
        }
        // ─────────────────────────────────────────────────────────────────────────────────────

        do {
            let success = try await authManager.authenticate(
                reason: "Authenticate to open \(protectedApp.displayName)"
            )
            await logger.log(appName: protectedApp.displayName, success: success, reason: reason)
            return success ? .unlocked : .failed
        } catch let error as AuthenticationManager.AuthError {
            await logger.log(appName: protectedApp.displayName, success: false, reason: reason)
            switch error {
            case .userCancelled, .systemCancelled:
                return .cancelled
            default:
                return .failed
            }
        } catch {
            await logger.log(appName: protectedApp.displayName, success: false, reason: reason)
            return .failed
        }
    }
}
