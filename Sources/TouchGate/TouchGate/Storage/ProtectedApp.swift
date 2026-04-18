import Foundation

struct ProtectedApp: Codable, Identifiable, Sendable {
    let id: UUID
    let bundleIdentifier: String
    let displayName: String
    let bundlePath: String
    let iconData: Data?
    var unlockTimeout: TimeInterval   // 0 = require auth every launch
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

    var isCurrentlyUnlocked: Bool {
        guard unlockTimeout > 0, let lastUnlocked else { return false }
        return Date().timeIntervalSince(lastUnlocked) < unlockTimeout
    }
}
