import Foundation

struct LogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let appName: String
    let success: Bool
    // nil  = entry was recorded before Intent Journaling existed (legacy)
    // ""   = prompt was shown but timer elapsed / user skipped
    // text = user typed a reason
    let reason: String?

    // Custom decoder: treat missing `reason` key as nil so old JSON files
    // (which predate this field) round-trip without throwing.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id        = try c.decode(UUID.self,   forKey: .id)
        timestamp = try c.decode(Date.self,   forKey: .timestamp)
        appName   = try c.decode(String.self, forKey: .appName)
        success   = try c.decode(Bool.self,   forKey: .success)
        reason    = try c.decodeIfPresent(String.self, forKey: .reason)
    }

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        appName: String,
        success: Bool,
        reason: String?
    ) {
        self.id        = id
        self.timestamp = timestamp
        self.appName   = appName
        self.success   = success
        self.reason    = reason
    }
}

actor UnlockLogger {
    private let fileURL: URL
    private static let maxEntries = 1000

    init() {
        // BUG-03 FIX: Replace force-unwrap with a safe fallback. FileManager.urls() returns an
        // empty array only on deeply broken sandboxed environments — but a crash here would prevent
        // TouchGate from launching at all, so we provide a reasonable fallback.
        let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let appDir = supportDir.appendingPathComponent("TouchGate")
        // createDirectory is idempotent with withIntermediateDirectories: true.
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        fileURL = appDir.appendingPathComponent("unlock_log.json")
    }

    // reason: String? = nil default keeps all pre-journaling call sites compiling unchanged.
    func log(appName: String, success: Bool, reason: String? = nil) {
        var entries = (try? load()) ?? []
        entries.append(LogEntry(
            id: UUID(),
            timestamp: Date(),
            appName: appName,
            success: success,
            reason: reason
        ))

        // Cap log size so the file never grows unbounded.
        if entries.count > Self.maxEntries {
            entries = Array(entries.suffix(Self.maxEntries))
        }

        try? persist(entries)
    }

    func loadEntries() throws -> [LogEntry] {
        try load()
    }

    func clearLog() throws {
        try persist([])
    }

    // MARK: - Private

    private func load() throws -> [LogEntry] {
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode([LogEntry].self, from: data)
    }

    private func persist(_ entries: [LogEntry]) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(entries)
        try data.write(to: fileURL, options: .atomic)
    }
}
