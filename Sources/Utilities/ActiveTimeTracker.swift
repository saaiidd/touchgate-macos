import AppKit
import Foundation
import OSLog

/// Tracks how long each app has been frontmost, per calendar day, across TouchGate restarts.
///
/// Data is stored in `active_time.json` as `{ "bundleId|YYYY-MM-DD": seconds }`.
/// Entries older than 7 days are pruned on `start()`. If the current session isn't flushed
/// before quit (e.g. force-kill), at most one session's worth of time is lost — acceptable.
actor ActiveTimeTracker {

    private var accumulated: [String: TimeInterval] = [:]
    private var currentBundleId: String?
    private var currentSessionStart: Date?
    private let fileURL: URL

    private var activationToken: Any?
    private var deactivationToken: Any?
    private var sleepToken: Any?

    private static let log = Logger(subsystem: "com.touchgate.app", category: "ActiveTimeTracker")

    init() {
        let supportDir = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? URL(fileURLWithPath: NSHomeDirectory() + "/Library/Application Support")
        let appDir = supportDir.appendingPathComponent("TouchGate")
        try? FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        fileURL = appDir.appendingPathComponent("active_time.json")
    }

    // MARK: - Lifecycle

    func start() async {
        loadFromDisk()
        pruneOldEntries()

        // Capture whatever is frontmost right now so we don't miss the current session.
        let frontId = await MainActor.run {
            NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        }
        if let id = frontId {
            currentBundleId = id
            currentSessionStart = Date()
            Self.log.info("ActiveTimeTracker: initial frontmost = \(id, privacy: .public)")
        }

        activationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] notification in
            guard let self,
                  let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
                  let bundleId = app.bundleIdentifier
            else { return }
            Task { await self.handleActivation(bundleId: bundleId) }
        }

        deactivationToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didDeactivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.flushCurrentSession() }
        }

        // Flush on sleep so we don't accrue "dead" time overnight.
        sleepToken = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.willSleepNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { await self.flushCurrentSession() }
        }

        Self.log.info("ActiveTimeTracker started. \(self.accumulated.count, privacy: .public) entries loaded.")
    }

    func stop() {
        flushCurrentSession()
        for token in [activationToken, deactivationToken, sleepToken].compactMap({ $0 }) {
            NSWorkspace.shared.notificationCenter.removeObserver(token)
        }
        activationToken = nil; deactivationToken = nil; sleepToken = nil
        Self.log.info("ActiveTimeTracker stopped.")
    }

    // MARK: - Queries

    /// Total seconds `bundleId` was frontmost on the calendar day of `date`.
    /// Includes the currently-running session if this is the active app.
    func activeSeconds(for bundleId: String, on date: Date = Date()) -> TimeInterval {
        let key = Self.storageKey(bundleId: bundleId, date: date)
        var total = accumulated[key] ?? 0
        if bundleId == currentBundleId, let start = currentSessionStart {
            total += max(0, date.timeIntervalSince(start))
        }
        return total
    }

    // MARK: - Private

    private func handleActivation(bundleId: String) {
        flushCurrentSession()           // close the previous app's session first
        currentBundleId = bundleId
        currentSessionStart = Date()
    }

    private func flushCurrentSession() {
        guard let bundleId = currentBundleId, let start = currentSessionStart else { return }
        let duration = max(0, Date().timeIntervalSince(start))
        let key = Self.storageKey(bundleId: bundleId, date: start)
        accumulated[key, default: 0] += duration
        currentBundleId = nil
        currentSessionStart = nil
        try? saveToDisk()
        Self.log.debug("Flushed \(String(format: "%.0f", duration), privacy: .public)s for \(bundleId, privacy: .public)")
    }

    private static func storageKey(bundleId: String, date: Date) -> String {
        // ISO 8601 date-only: "2025-04-19"
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        return "\(bundleId)|\(fmt.string(from: date))"
    }

    private func pruneOldEntries() {
        guard let cutoff = Calendar.current.date(byAdding: .day, value: -7, to: Date()) else { return }
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        accumulated = accumulated.filter { key, _ in
            // Key format: "bundleId|YYYY-MM-DD" — split on first "|"
            guard let pipeIdx = key.firstIndex(of: "|") else { return false }
            let dateStr = String(key[key.index(after: pipeIdx)...])
            guard let date = fmt.date(from: dateStr) else { return false }
            return date >= cutoff
        }
        Self.log.info("Pruned old entries; \(self.accumulated.count, privacy: .public) remain.")
    }

    private func loadFromDisk() {
        guard let data = try? Data(contentsOf: fileURL),
              let dict = try? JSONDecoder().decode([String: TimeInterval].self, from: data)
        else { return }
        accumulated = dict
    }

    private func saveToDisk() throws {
        let data = try JSONEncoder().encode(accumulated)
        try data.write(to: fileURL, options: .atomic)
    }
}
