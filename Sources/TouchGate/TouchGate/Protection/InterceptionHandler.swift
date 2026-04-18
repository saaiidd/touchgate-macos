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

    init(authManager: AuthenticationManager, logger: UnlockLogger) {
        self.authManager = authManager
        self.logger = logger
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

        // Bring TouchGate forward so the system auth sheet appears above other windows.
        await MainActor.run {
            NSApp.activate(ignoringOtherApps: true)
        }

        do {
            let success = try await authManager.authenticate(
                reason: "Authenticate to open \(protectedApp.displayName)"
            )
            await logger.log(appName: protectedApp.displayName, success: success)
            return success ? .unlocked : .failed
        } catch let error as AuthenticationManager.AuthError {
            await logger.log(appName: protectedApp.displayName, success: false)
            switch error {
            case .userCancelled, .systemCancelled:
                return .cancelled
            default:
                return .failed
            }
        } catch {
            await logger.log(appName: protectedApp.displayName, success: false)
            return .failed
        }
    }
}
