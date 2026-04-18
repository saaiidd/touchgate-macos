import Foundation

struct LogEntry: Codable, Identifiable {
    let id: UUID
    let timestamp: Date
    let appName: String
    let success: Bool
}

actor UnlockLogger {
    private let fileURL: URL
    private static let maxEntries = 1000

    init() {
        let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let appDir = supportDir.appendingPathComponent("TouchGate")
        // createDirectory is idempotent with withIntermediateDirectories: true.
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        fileURL = appDir.appendingPathComponent("unlock_log.json")
    }

    func log(appName: String, success: Bool) {
        var entries = (try? load()) ?? []
        entries.append(LogEntry(id: UUID(), timestamp: Date(), appName: appName, success: success))

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
