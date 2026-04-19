import SwiftUI

// MARK: - Pattern Model

private struct AppPattern: Identifiable {
    let id = UUID()
    let appName: String
    let countThisWeek: Int
    let mostCommonReason: String?  // nil if no typed reasons exist for this app
}

// MARK: - Log View

struct LogView: View {
    @EnvironmentObject private var appState: AppState
    @State private var entries: [LogEntry] = []
    @State private var isLoading = true
    @State private var showClearConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if entries.isEmpty {
                emptyState
            } else {
                VStack(spacing: 0) {
                    logTable
                    if !patterns.isEmpty {
                        Divider()
                        patternsSection
                    }
                }
            }

            Divider()

            HStack {
                Text("\(entries.count) entries")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Clear Log") {
                    showClearConfirmation = true
                }
                .buttonStyle(.bordered)
                .foregroundStyle(.red)
                .disabled(entries.isEmpty)
            }
            .padding(.horizontal, 4)
            .padding(.top, 8)
        }
        .task { await loadEntries() }
        .confirmationDialog(
            "Clear all log entries?",
            isPresented: $showClearConfirmation,
            titleVisibility: .visible
        ) {
            Button("Clear Log", role: .destructive) { clearLog() }
            Button("Cancel", role: .cancel) {}
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "list.bullet.clipboard")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No unlock attempts yet")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Log Table

    private var logTable: some View {
        Table(entries.reversed()) {
            TableColumn("Time") { entry in
                Text(entry.timestamp, format: .dateTime.hour().minute().second())
                    .font(.system(.caption, design: .monospaced))
                    .help(entry.timestamp.formatted())
            }
            .width(min: 80, ideal: 85)

            TableColumn("App") { entry in
                Text(entry.appName)
                    .lineLimit(1)
            }

            TableColumn("Result") { entry in
                Label(
                    entry.success ? "Unlocked" : "Denied",
                    systemImage: entry.success ? "checkmark.circle.fill" : "xmark.circle.fill"
                )
                .foregroundStyle(entry.success ? Color.green : Color.red)
                .labelStyle(.titleAndIcon)
            }
            .width(min: 80, ideal: 90)

            TableColumn("Reason") { entry in
                if let r = entry.reason {
                    Text(r.isEmpty ? "—" : r)
                        .lineLimit(1)
                        .foregroundStyle(r.isEmpty ? .tertiary : .primary)
                        .help(r.isEmpty ? "Timer elapsed or skipped" : r)
                } else {
                    Text("—")
                        .foregroundStyle(.tertiary)
                        .help("Recorded before Intent Journaling")
                }
            }
            .width(min: 80, ideal: 120)
        }
    }

    // MARK: - Patterns Section

    /// Per-app habit summary for the past 7 days. Only shows apps with ≥2 opens this week.
    private var patterns: [AppPattern] {
        let sevenDaysAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let recent = entries.filter { $0.timestamp >= sevenDaysAgo }
        guard !recent.isEmpty else { return [] }

        let grouped = Dictionary(grouping: recent) { $0.appName }
        return grouped.compactMap { (appName, appEntries) -> AppPattern? in
            guard appEntries.count >= 2 else { return nil }

            // Frequency-count non-empty typed reasons.
            var reasonCounts: [String: Int] = [:]
            for entry in appEntries {
                if let r = entry.reason, !r.isEmpty {
                    reasonCounts[r, default: 0] += 1
                }
            }
            let mostCommon = reasonCounts.max(by: { $0.value < $1.value })?.key

            return AppPattern(
                appName: appName,
                countThisWeek: appEntries.count,
                mostCommonReason: mostCommon
            )
        }
        .sorted { $0.countThisWeek > $1.countThisWeek }
    }

    private var patternsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: "chart.bar.xaxis")
                    .foregroundStyle(.secondary)
                    .imageScale(.small)
                Text("Patterns — last 7 days")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)

            ForEach(patterns) { pattern in
                HStack(spacing: 4) {
                    Text(pattern.appName)
                        .font(.caption)
                        .fontWeight(.medium)
                    Text("·")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Text("\(pattern.countThisWeek)× this week")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    if let reason = pattern.mostCommonReason {
                        Text("most common: \"\(reason)\"")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.05))
    }

    // MARK: - Actions

    private func loadEntries() async {
        isLoading = true
        entries = (try? await appState.logger.loadEntries()) ?? []
        isLoading = false
    }

    private func clearLog() {
        Task {
            try? await appState.logger.clearLog()
            entries = []
        }
    }
}
