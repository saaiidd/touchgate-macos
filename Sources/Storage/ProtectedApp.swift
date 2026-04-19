import Foundation

// Codable model persisted to Keychain as JSON. Schema is intentionally stable.
//
// FIELD NOTES:
// - `unlockTimeout` is retained for Keychain schema compatibility with v1 installs
//   AND as the data path for a future per-app override feature (likely gated by a
//   new `usesGlobalMode: Bool` flag). It is NOT consulted by the v2 auth decision —
//   AppState.requiresAuthentication(for:) is the only place that matters.
// - `lastUnlocked` IS actively used — it's how Balanced mode tracks the
//   inactivity window across TouchGate restarts.
struct ProtectedApp: Codable, Identifiable, Sendable {
    let id: UUID
    var bundleIdentifier: String   // var: migration in AppState.loadProtectedApps() may correct a stale ID
    let displayName: String
    let bundlePath: String
    let iconData: Data?
    var unlockTimeout: TimeInterval   // Legacy; retained for schema + future per-app override
    var lastUnlocked: Date?

    init(
        id: UUID = UUID(),
        bundleIdentifier: String,
        displayName: String,
        bundlePath: String,
        iconData: Data?,
        unlockTimeout: TimeInterval = 0
    ) {
        self.id = id
        self.bundleIdentifier = bundleIdentifier
        self.displayName = displayName
        self.bundlePath = bundlePath
        self.iconData = iconData
        self.unlockTimeout = unlockTimeout
        self.lastUnlocked = nil
    }
}
