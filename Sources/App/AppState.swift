import AppKit
import Combine
import OSLog

// Single source of truth for the entire app. All @Published mutations happen on the main actor.
// THREAD SAFETY: @MainActor guarantees all state (including `sessionUnlockedApps`) is accessed
// serially on the main thread. No additional locking is needed.
@MainActor
final class AppState: ObservableObject {
    @Published var protectedApps: [ProtectedApp] = []
    @Published var hasAccessibilityPermission: Bool = false

    // Security Mode — global policy. Mutated ONLY via setSecurityMode(_:) and
    // setBalancedModeTimeout(_:) so that Keychain writes always complete BEFORE the
    // @Published value flips. See those methods for the crash-safety ordering.
    @Published private(set) var securityMode: SecurityMode
    @Published private(set) var balancedModeTimeout: Int   // minutes

    // Relaxed mode: in-memory set of currently-unlocked bundle IDs.
    // LIFETIME: cleared on mode switch, on system wake, and on process exit (implicit).
    // NOTE: This is process-scoped, NOT system-session-scoped — killing TouchGate wipes it.
    //       The UI description text makes this explicit to the user.
    private var sessionUnlockedApps: Set<String> = []

    let logger: UnlockLogger
    let authManager: AuthenticationManager
    private let store: ProtectedAppStore
    let interceptionHandler: InterceptionHandler
    let activeTimeTracker: ActiveTimeTracker
    private var appMonitor: AppMonitor?

    private static let log = Logger(subsystem: "com.touchgate.app", category: "AppState")

    // UserDefaults keys — kept as constants to avoid string typos across reads/writes.
    private enum DefaultsKey {
        static let securityMode = "securityMode"
        static let balancedModeTimeout = "balancedModeTimeout"
    }

    init() {
        let logger = UnlockLogger()
        let authManager = AuthenticationManager()
        let store = ProtectedAppStore()
        let activeTimeTracker = ActiveTimeTracker()

        self.logger = logger
        self.authManager = authManager
        self.store = store
        self.activeTimeTracker = activeTimeTracker
        self.interceptionHandler = InterceptionHandler(
            authManager: authManager,
            logger: logger,
            activeTracker: activeTimeTracker
        )

        // Load persisted mode + timeout from UserDefaults with sensible defaults.
        let defaults = UserDefaults.standard
        let rawMode = defaults.string(forKey: DefaultsKey.securityMode) ?? SecurityMode.balanced.rawValue
        self.securityMode = SecurityMode(rawValue: rawMode) ?? .balanced
        let storedTimeout = defaults.integer(forKey: DefaultsKey.balancedModeTimeout)
        // UserDefaults returns 0 when key is missing — use 10-minute default in that case.
        self.balancedModeTimeout = storedTimeout > 0 ? storedTimeout : 10

        checkAccessibilityPermission()
    }

    // MARK: - Lifecycle

    func loadProtectedApps() async {
        do {
            var apps = try await store.load()

            // BUNDLE ID MIGRATION:
            // The bundleIdentifier stored at add-time may be stale — e.g. the user dragged the
            // app to the file picker before the app's bundle was fully indexed, or the app has
            // since been updated and its bundle ID changed, or a sandboxed bundle reports a
            // different ID at runtime.
            //
            // Fix: re-read the actual ID from Bundle(url:) on every launch and patch any mismatch
            // before the AppMonitor starts. Without this, isProtected(bundleIdentifier:) will never
            // match and interception silently does nothing.
            var migrationCount = 0
            for i in apps.indices {
                let bundleURL = URL(fileURLWithPath: apps[i].bundlePath)
                if let bundle = Bundle(url: bundleURL),
                   let actualId = bundle.bundleIdentifier,
                   actualId != apps[i].bundleIdentifier {
                    let name = apps[i].displayName
                    let storedId = apps[i].bundleIdentifier
                    Self.log.warning("Bundle ID mismatch for '\(name, privacy: .public)': stored='\(storedId, privacy: .public)' actual='\(actualId, privacy: .public)' — auto-correcting")
                    apps[i].bundleIdentifier = actualId
                    migrationCount += 1
                }
            }

            protectedApps = apps

            // Diagnostic: log every stored app so mismatches are obvious in log stream.
            for app in apps {
                Self.log.info("Loaded protected app: '\(app.displayName, privacy: .public)' bundleId='\(app.bundleIdentifier, privacy: .public)' path='\(app.bundlePath, privacy: .public)'")
            }

            if migrationCount > 0 {
                Self.log.info("Migrated \(migrationCount) bundle ID(s) — saving to Keychain")
                await persistApps()
            }
        } catch {
            // Non-fatal: start with an empty list and let the user re-add apps.
            Self.log.error("Failed to load protected apps from Keychain: \(error.localizedDescription)")
        }
    }

    func startMonitoring() {
        Task { await activeTimeTracker.start() }
        appMonitor = AppMonitor(appState: self, interceptionHandler: interceptionHandler)
        appMonitor?.start()
    }

    func stopMonitoring() {
        appMonitor?.stop()
        Task { await activeTimeTracker.stop() }
    }

    // MARK: - App Management

    func addApp(_ app: ProtectedApp) async {
        guard !protectedApps.contains(where: { $0.bundleIdentifier == app.bundleIdentifier }) else { return }
        protectedApps.append(app)
        await persistApps()
    }

    func removeApp(id: UUID) async {
        protectedApps.removeAll { $0.id == id }
        await persistApps()
    }

    // Retained for potential future per-app override UI (see ProtectedApp.unlockTimeout).
    // Not called from anywhere in v1 but kept so the API surface doesn't shift.
    func updateTimeout(for id: UUID, timeout: TimeInterval) async {
        guard let index = protectedApps.firstIndex(where: { $0.id == id }) else { return }
        protectedApps[index].unlockTimeout = timeout
        await persistApps()
    }

    // MARK: - Security Mode

    // Central authentication decision. The ONLY place mode logic lives.
    // Called from AppMonitor on every launch notification.
    func requiresAuthentication(for bundleIdentifier: String) -> Bool {
        switch securityMode {
        case .strict:
            return true

        case .relaxed:
            return !sessionUnlockedApps.contains(bundleIdentifier)

        case .balanced:
            // LIMITATION: Uses wall-clock time (Date()). A user who manually advances
            // the system clock can jump past the inactivity window. This is accepted
            // because (a) it requires physical access to the unlocked Mac, at which
            // point most threat models collapse anyway, and (b) monotonic time is
            // awkward to plumb through Codable/Keychain.
            guard let app = protectedApp(for: bundleIdentifier),
                  let lastUnlocked = app.lastUnlocked else { return true }
            let windowSeconds = TimeInterval(balancedModeTimeout * 60)
            return Date().timeIntervalSince(lastUnlocked) >= windowSeconds
        }
    }

    // Switch modes. Critical ordering: clear all auth state → persist Keychain →
    // persist UserDefaults → flip @Published mode. If we crash mid-transition, the
    // Keychain reflects the cleared state, so there's no window where stale
    // lastUnlocked timestamps could satisfy the new mode's check.
    func setSecurityMode(_ newMode: SecurityMode) async {
        guard newMode != securityMode else { return }

        sessionUnlockedApps.removeAll()
        for index in protectedApps.indices {
            protectedApps[index].lastUnlocked = nil
        }
        await persistApps()                    // Keychain written FIRST
        UserDefaults.standard.set(newMode.rawValue, forKey: DefaultsKey.securityMode)
        securityMode = newMode                 // @Published flip LAST
    }

    // Change Balanced mode's inactivity window. No state to clear — existing
    // lastUnlocked timestamps remain valid; only the comparison window changes.
    // Shortening may re-lock some apps immediately (correct behavior).
    func setBalancedModeTimeout(_ minutes: Int) async {
        guard minutes != balancedModeTimeout else { return }
        UserDefaults.standard.set(minutes, forKey: DefaultsKey.balancedModeTimeout)
        balancedModeTimeout = minutes
    }

    // Called by AppMonitor on NSWorkspace.didWakeNotification. Wipes the Relaxed
    // session set; no-op for Balanced/Strict (they don't consult this state).
    func clearSessionUnlocks() {
        sessionUnlockedApps.removeAll()
    }

    // MARK: - Lock / Unlock

    // Called by AppMonitor after a successful auth. Mode-aware: records state
    // in whichever place the current mode reads from.
    func recordUnlock(bundleIdentifier: String) async {
        switch securityMode {
        case .relaxed:
            sessionUnlockedApps.insert(bundleIdentifier)

        case .balanced:
            guard let index = protectedApps.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
            protectedApps[index].lastUnlocked = Date()
            await persistApps()

        case .strict:
            // No state to record — every launch re-auths.
            break
        }
    }

    func lockAll() async {
        sessionUnlockedApps.removeAll()
        for index in protectedApps.indices {
            protectedApps[index].lastUnlocked = nil
        }
        await persistApps()
    }

    func lockApp(id: UUID) async {
        guard let index = protectedApps.firstIndex(where: { $0.id == id }) else { return }
        sessionUnlockedApps.remove(protectedApps[index].bundleIdentifier)
        protectedApps[index].lastUnlocked = nil
        await persistApps()
    }

    // MARK: - Queries (called from notification callbacks on main thread)

    func isProtected(bundleIdentifier: String) -> Bool {
        protectedApps.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    func protectedApp(for bundleIdentifier: String) -> ProtectedApp? {
        protectedApps.first { $0.bundleIdentifier == bundleIdentifier }
    }

    // MARK: - Gate Rules

    func setGateRule(_ rule: GateRule?, for id: UUID) async {
        guard let index = protectedApps.firstIndex(where: { $0.id == id }) else { return }
        protectedApps[index].gateRule = rule
        await persistApps()
    }

    /// Minutes `bundleId` was frontmost today (includes the running session if currently active).
    func activeMinutesToday(for bundleId: String) async -> Int {
        let seconds = await activeTimeTracker.activeSeconds(for: bundleId)
        return Int(seconds / 60)
    }

    // MARK: - Permissions

    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    // MARK: - Icon State

    enum MenuBarIconState {
        case neutral   // No protected apps configured
        case locked    // Apps protected, no active grace period
        case unlocked  // At least one app is currently authenticated
    }

    var menuBarIconState: MenuBarIconState {
        guard !protectedApps.isEmpty else { return .neutral }
        let anyUnlocked = protectedApps.contains { !requiresAuthentication(for: $0.bundleIdentifier) }
        return anyUnlocked ? .unlocked : .locked
    }

    // MARK: - Private

    private func persistApps() async {
        do {
            try await store.save(protectedApps)
        } catch {
            Self.log.error("Failed to save protected apps to Keychain: \(error.localizedDescription)")
        }
    }
}
