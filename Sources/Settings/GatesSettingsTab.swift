import SwiftUI
import AppKit
import UniformTypeIdentifiers

// MARK: - Gates Tab

struct GatesSettingsTab: View {
    @EnvironmentObject private var appState: AppState

    // Single sheet for both add and edit; editingApp == nil means add mode.
    @State private var showSheet = false
    @State private var editingApp: ProtectedApp? = nil

    // Cache of prerequisite-app active minutes for the progress bars.
    // Key = requiredBundleId; updated on appear and on "Refresh".
    @State private var progressCache: [String: Int] = [:]

    private var gatedApps: [ProtectedApp] {
        appState.protectedApps.filter { $0.gateRule != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            if appState.protectedApps.isEmpty {
                noAppsState
            } else if gatedApps.isEmpty {
                emptyState
            } else {
                gateList
            }

            Divider()

            footer
        }
        .task { await refreshProgress() }
        .sheet(isPresented: $showSheet) {
            GateRuleEditorSheet(editingApp: editingApp) { appId, rule in
                Task { await appState.setGateRule(rule, for: appId) }
            }
            .environmentObject(appState)
        }
    }

    // MARK: - States

    private var noAppsState: some View {
        VStack(spacing: 8) {
            Image(systemName: "lock.slash")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No protected apps")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Add apps via the menu bar first, then define prerequisite gates here.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.triangle.branch")
                .font(.system(size: 32))
                .foregroundStyle(.tertiary)
            Text("No prerequisite gates")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Text("Define rules like \u{201C}Telegram only unlocks after 45 min of Xcode today.\u{201D}")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Gate List

    private var gateList: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(gatedApps) { app in
                    GateRuleRow(
                        app: app,
                        doneMinutes: progressCache[app.gateRule?.requiredBundleId ?? ""] ?? 0,
                        onEdit: {
                            editingApp = app
                            showSheet = true
                        },
                        onRemove: {
                            Task { await appState.setGateRule(nil, for: app.id) }
                        }
                    )
                    if app.id != gatedApps.last?.id {
                        Divider().padding(.leading, 54)
                    }
                }
            }
        }
    }

    // MARK: - Footer

    private var footer: some View {
        HStack {
            Button {
                Task { await refreshProgress() }
            } label: {
                Label("Refresh", systemImage: "arrow.clockwise")
                    .font(.caption)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)

            Spacer()

            Button("Add Rule…") {
                editingApp = nil
                showSheet = true
            }
            .buttonStyle(.bordered)
            // Disable when every protected app already has a gate.
            .disabled(appState.protectedApps.allSatisfy { $0.gateRule != nil })
        }
        .padding(.horizontal, 4)
        .padding(.top, 8)
    }

    // MARK: - Progress

    private func refreshProgress() async {
        var cache: [String: Int] = [:]
        let bundleIds = Set(gatedApps.compactMap { $0.gateRule?.requiredBundleId })
        for id in bundleIds {
            cache[id] = await appState.activeMinutesToday(for: id)
        }
        progressCache = cache
    }
}

// MARK: - Gate Rule Row

private struct GateRuleRow: View {
    let app: ProtectedApp
    let doneMinutes: Int
    let onEdit: () -> Void
    let onRemove: () -> Void

    private var rule: GateRule { app.gateRule! }   // guaranteed non-nil by caller filter

    private var progress: Double {
        guard rule.requiredMinutes > 0 else { return 1 }
        return min(1, Double(doneMinutes) / Double(rule.requiredMinutes))
    }

    private var met: Bool { doneMinutes >= rule.requiredMinutes }

    var body: some View {
        HStack(spacing: 10) {
            appIcon

            VStack(alignment: .leading, spacing: 4) {
                // Rule description line
                HStack(spacing: 4) {
                    Text(app.displayName)
                        .font(.system(size: 13, weight: .medium))
                    Image(systemName: "arrow.right")
                        .font(.system(size: 9))
                        .foregroundStyle(.tertiary)
                    Text(rule.requiredDisplayName)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                    Text("· \(rule.requiredMinutes) min")
                        .font(.system(size: 12))
                        .foregroundStyle(.tertiary)
                }
                .lineLimit(1)

                // Today's progress
                HStack(spacing: 6) {
                    ProgressView(value: progress)
                        .frame(width: 110)
                        .tint(met ? .green : .accentColor)

                    Text(met
                        ? "✓ Gate met today"
                        : "\(doneMinutes)/\(rule.requiredMinutes) min today"
                    )
                    .font(.caption)
                    .foregroundStyle(met ? .green : .secondary)
                }
            }

            Spacer()

            Button(action: onEdit) {
                Image(systemName: "pencil.circle")
                    .foregroundStyle(.secondary)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help("Edit rule")

            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help("Remove gate")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var appIcon: some View {
        Group {
            if let data = app.iconData, let img = NSImage(data: data) {
                Image(nsImage: img)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: "app.fill")
                    .frame(width: 32, height: 32)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Gate Rule Editor Sheet

/// Handles both "Add" (editingApp == nil) and "Edit" (editingApp != nil) in one sheet.
struct GateRuleEditorSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// nil → add mode (show app picker); non-nil → edit mode (fixed app)
    let editingApp: ProtectedApp?
    let onSave: (UUID, GateRule) -> Void

    @State private var selectedAppId: UUID? = nil
    @State private var prereqBundleId: String = ""
    @State private var prereqDisplayName: String = ""
    @State private var requiredMinutes: Int = 45

    private var isAddMode: Bool { editingApp == nil }

    /// Protected apps that don't yet have a gate (available to gate in add mode).
    private var ungatedApps: [ProtectedApp] {
        appState.protectedApps.filter { $0.gateRule == nil }
    }

    /// The app that will be gated — either from picker (add) or fixed (edit).
    private var targetApp: ProtectedApp? {
        if let editingApp { return editingApp }
        return appState.protectedApps.first { $0.id == selectedAppId }
    }

    private var canSave: Bool {
        selectedAppId != nil && !prereqBundleId.isEmpty && requiredMinutes > 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // Title
            Text(isAddMode ? "New Prerequisite Gate" : "Edit Prerequisite Gate")
                .font(.system(size: 16, weight: .semibold))

            // Step 1 — which protected app to gate (add mode only)
            if isAddMode {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Gate this app", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Picker("", selection: $selectedAppId) {
                        Text("Choose…").tag(UUID?.none)
                        ForEach(ungatedApps) { app in
                            Text(app.displayName).tag(UUID?.some(app.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else if let app = editingApp {
                // Edit mode — show fixed app
                VStack(alignment: .leading, spacing: 6) {
                    Label("Gated app", systemImage: "lock.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(app.displayName)
                        .font(.system(size: 13, weight: .medium))
                }
            }

            // Step 2 — prerequisite app
            VStack(alignment: .leading, spacing: 6) {
                Label("Requires this app to be active", systemImage: "clock")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                HStack {
                    if prereqDisplayName.isEmpty {
                        Text("No app selected")
                            .foregroundStyle(.tertiary)
                    } else {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                                .imageScale(.small)
                            Text(prereqDisplayName)
                        }
                    }
                    Spacer()
                    Button("Choose App…") { pickPrereqApp() }
                        .buttonStyle(.bordered)
                }
            }

            // Step 3 — minutes
            VStack(alignment: .leading, spacing: 6) {
                Label("Minutes required today", systemImage: "timer")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Stepper(
                    minuteLabel,
                    value: $requiredMinutes,
                    in: 5...480,
                    step: 5
                )
            }

            // Live preview sentence
            if let target = targetApp, !prereqDisplayName.isEmpty {
                Text(
                    "\u{201C}\(target.displayName) unlocks only after \(minuteLabel) of \(prereqDisplayName) today.\u{201D}"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.secondary.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            Spacer(minLength: 0)

            // Buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Spacer()
                Button(isAddMode ? "Add Rule" : "Save") {
                    guard let id = selectedAppId else { return }
                    let rule = GateRule(
                        requiredBundleId: prereqBundleId,
                        requiredDisplayName: prereqDisplayName,
                        requiredMinutes: requiredMinutes
                    )
                    onSave(id, rule)
                    dismiss()
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(24)
        .frame(width: 420, alignment: .leading)
        .onAppear { prefill() }
    }

    // MARK: - Helpers

    private var minuteLabel: String {
        requiredMinutes == 60 ? "1 hour" : "\(requiredMinutes) min"
    }

    private func prefill() {
        if let app = editingApp {
            selectedAppId = app.id
            if let rule = app.gateRule {
                prereqBundleId = rule.requiredBundleId
                prereqDisplayName = rule.requiredDisplayName
                requiredMinutes = rule.requiredMinutes
            }
        } else {
            // Pre-select first available app
            selectedAppId = ungatedApps.first?.id
        }
    }

    private func pickPrereqApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Select the app that must be used as a prerequisite"
        panel.prompt = "Select"

        panel.begin { response in
            guard response == .OK, let url = panel.urls.first else { return }
            if let bundle = Bundle(url: url), let bid = bundle.bundleIdentifier {
                prereqBundleId = bid
            } else {
                // Fallback: derive from folder name if bundle info is missing
                prereqBundleId = "app.\(url.deletingPathExtension().lastPathComponent.lowercased())"
            }
            prereqDisplayName = url.deletingPathExtension().lastPathComponent
        }
    }
}
