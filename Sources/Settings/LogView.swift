import SwiftUI

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
                logTable
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
        }
    }

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
