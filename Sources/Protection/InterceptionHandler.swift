import AppKit
import LocalAuthentication

actor InterceptionHandler {

    enum InterceptionResult {
        case unlocked
        case cancelled      // User dismissed auth or gate was not met
        case failed         // Auth rejected or error
        case alreadyPending // Second launch while first auth is in progress
    }

    private var pendingAuthentications: Set<String> = []
    private let authManager: AuthenticationManager
    private let logger: UnlockLogger
    private let activeTracker: ActiveTimeTracker

    /// Weak reference to the currently-visible intent or gate panel, so tearDown() can cancel it.
    private weak var activePromptWindow: IntentPromptWindow?

    init(authManager: AuthenticationManager, logger: UnlockLogger, activeTracker: ActiveTimeTracker) {
        self.authManager = authManager
        self.logger = logger
        self.activeTracker = activeTracker
    }

    /// Cancel any in-flight intent prompt and resolve its continuation cleanly.
    func tearDown() {
        let panel = activePromptWindow
        Task { @MainActor in panel?.viewModel.cancel() }
    }

    func intercept(
        runningApp: NSRunningApplication,
        protectedApp: ProtectedApp
    ) async -> InterceptionResult {
        let bundleId = protectedApp.bundleIdentifier

        if pendingAuthentications.contains(bundleId) {
            runningApp.forceTerminate()
            return .alreadyPending
        }

        pendingAuthentications.insert(bundleId)
        defer { pendingAuthentications.remove(bundleId) }

        // SECURITY: Terminate immediately before the app fully initialises.
        _ = runningApp.terminate()
        try? await Task.sleep(nanoseconds: 500_000_000)
        if !runningApp.isTerminated { runningApp.forceTerminate() }
        try? await Task.sleep(nanoseconds: 300_000_000)

        // Bring TouchGate forward so our panels appear above other windows.
        await MainActor.run { NSApp.activate(ignoringOtherApps: true) }

        // ── Prerequisite Gate ──────────────────────────────────────────────────────────────────
        // Check the gate rule BEFORE showing the intent prompt. If the gate is not met, inform
        // the user and bail. They must earn the required time first.
        if let gate = protectedApp.gateRule {
            let todaySeconds = await activeTracker.activeSeconds(for: gate.requiredBundleId)
            let requiredSeconds = TimeInterval(gate.requiredMinutes * 60)

            if todaySeconds < requiredSeconds {
                let doneMinutes = Int(todaySeconds / 60)
                let blockedPanel = await MainActor.run {
                    let icon = protectedApp.iconData.flatMap { NSImage(data: $0) }
                    return GateBlockedWindow(
                        blockedAppName: protectedApp.displayName,
                        requiredAppName: gate.requiredDisplayName,
                        requiredMinutes: gate.requiredMinutes,
                        doneMinutes: doneMinutes,
                        blockedAppIcon: icon
                    )
                }
                await blockedPanel.showAndWait()
                let logReason = "gate:\(gate.requiredDisplayName)·\(doneMinutes)/\(gate.requiredMinutes)min"
                await logger.log(appName: protectedApp.displayName, success: false, reason: logReason)
                return .cancelled
            }
        }
        // ──────────────────────────────────────────────────────────────────────────────────────

        // ── Intent Journaling ─────────────────────────────────────────────────────────────────
        let intentReason: String? = await {
            let panel = await MainActor.run {
                let icon = protectedApp.iconData.flatMap { NSImage(data: $0) }
                return IntentPromptWindow(appName: protectedApp.displayName, appIcon: icon)
            }
            self.activePromptWindow = panel
            let result = await panel.promptAndWait()
            self.activePromptWindow = nil
            return result
        }()

        guard let reason = intentReason else {
            await logger.log(appName: protectedApp.displayName, success: false, reason: nil)
            return .cancelled
        }
        // ──────────────────────────────────────────────────────────────────────────────────────

        do {
            let success = try await authManager.authenticate(
                reason: "Authenticate to open \(protectedApp.displayName)"
            )
            await logger.log(appName: protectedApp.displayName, success: success, reason: reason)
            return success ? .unlocked : .failed
        } catch let error as AuthenticationManager.AuthError {
            await logger.log(appName: protectedApp.displayName, success: false, reason: reason)
            switch error {
            case .userCancelled, .systemCancelled: return .cancelled
            default: return .failed
            }
        } catch {
            await logger.log(appName: protectedApp.displayName, success: false, reason: reason)
            return .failed
        }
    }
}
