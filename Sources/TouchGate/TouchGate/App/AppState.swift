import AppKit
import Combine

// Single source of truth for the entire app. All @Published mutations happen on the main actor.
@MainActor
final class AppState: ObservableObject {
    @Published var protectedApps: [ProtectedApp] = []
    @Published var hasAccessibilityPermission: Bool = false

    let logger: UnlockLogger
    let authManager: AuthenticationManager
    private let store: ProtectedAppStore
    let interceptionHandler: InterceptionHandler
    private var appMonitor: AppMonitor?

    init() {
        let logger = UnlockLogger()
        let authManager = AuthenticationManager()
        let store = ProtectedAppStore()

        self.logger = logger
        self.authManager = authManager
        self.store = store
        self.interceptionHandler = InterceptionHandler(authManager: authManager, logger: logger)

        checkAccessibilityPermission()
    }

    // MARK: - Lifecycle

    func loadProtectedApps() async {
        do {
            protectedApps = try await store.load()
        } catch {
            // Non-fatal: start with an empty list and let the user re-add apps.
            print("[TouchGate] Failed to load protected apps from Keychain: \(error.localizedDescription)")
        }
    }

    func startMonitoring() {
        appMonitor = AppMonitor(appState: self, interceptionHandler: interceptionHandler)
        appMonitor?.start()
    }

    func stopMonitoring() {
        appMonitor?.stop()
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

    func updateTimeout(for id: UUID, timeout: TimeInterval) async {
        guard let index = protectedApps.firstIndex(where: { $0.id == id }) else { return }
        protectedApps[index].unlockTimeout = timeout
        await persistApps()
    }

    // MARK: - Lock / Unlock

    func recordUnlock(bundleIdentifier: String) async {
        guard let index = protectedApps.firstIndex(where: { $0.bundleIdentifier == bundleIdentifier }) else { return }
        protectedApps[index].lastUnlocked = Date()
        await persistApps()
    }

    func lockAll() async {
        for index in protectedApps.indices {
            protectedApps[index].lastUnlocked = nil
        }
        await persistApps()
    }

    func lockApp(id: UUID) async {
        guard let index = protectedApps.firstIndex(where: { $0.id == id }) else { return }
        protectedApps[index].lastUnlocked = nil
        await persistApps()
    }

    // MARK: - Queries (called from notification callbacks on main thread)

    func isProtected(bundleIdentifier: String) -> Bool {
        protectedApps.contains { $0.bundleIdentifier == bundleIdentifier }
    }

    func isUnlocked(bundleIdentifier: String) -> Bool {
        protectedApps.first { $0.bundleIdentifier == bundleIdentifier }?.isCurrentlyUnlocked ?? false
    }

    func protectedApp(for bundleIdentifier: String) -> ProtectedApp? {
        protectedApps.first { $0.bundleIdentifier == bundleIdentifier }
    }

    // MARK: - Permissions

    func checkAccessibilityPermission() {
        hasAccessibilityPermission = AXIsProcessTrusted()
    }

    // MARK: - Icon State

    enum MenuBarIconState {
        case neutral   // No protected apps configured
        case locked    // Apps protected, no active grace period
        case unlocked  // At least one app is within its grace period
    }

    var menuBarIconState: MenuBarIconState {
        guard !protectedApps.isEmpty else { return .neutral }
        return protectedApps.contains { $0.isCurrentlyUnlocked } ? .unlocked : .locked
    }

    // MARK: - Private

    private func persistApps() async {
        do {
            try await store.save(protectedApps)
        } catch {
            print("[TouchGate] Failed to save protected apps to Keychain: \(error.localizedDescription)")
        }
    }
}
