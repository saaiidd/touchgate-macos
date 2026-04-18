import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MenuBarView: View {
    @EnvironmentObject private var appState: AppState
    // BUG-02 FIX: Read the user's default timeout so newly-added apps inherit it.
    @AppStorage("defaultUnlockTimeout") private var defaultUnlockTimeout: Double = 0

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            appListSection
            Divider()
            footerActions
        }
        .frame(width: 300)
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: headerIcon)
                .foregroundStyle(headerColor)
                .imageScale(.medium)

            Text("TouchGate")
                .font(.system(size: 14, weight: .semibold))

            Spacer()

            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 11)
    }

    private var headerIcon: String {
        switch appState.menuBarIconState {
        case .neutral:  return "shield"
        // BUG-07 FIX: Use "lock.shield" to match StatusBarController — "lock.shield.fill" was inconsistent.
        case .locked:   return "lock.shield"
        case .unlocked: return "lock.open.rotation"
        }
    }

    private var headerColor: Color {
        switch appState.menuBarIconState {
        case .neutral:  return .secondary
        case .locked:   return .primary
        case .unlocked: return .green
        }
    }

    private var statusText: String {
        switch appState.menuBarIconState {
        case .neutral:  return "No apps protected"
        case .locked:   return "\(appState.protectedApps.count) protected"
        case .unlocked: return "Grace period active"
        }
    }

    // MARK: - App List

    @ViewBuilder
    private var appListSection: some View {
        if appState.protectedApps.isEmpty {
            emptyState
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(appState.protectedApps) { app in
                        AppRowView(app: app)
                        if app.id != appState.protectedApps.last?.id {
                            Divider().padding(.leading, 54)
                        }
                    }
                }
            }
            .frame(maxHeight: 220)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "shield.slash")
                .font(.system(size: 28))
                .foregroundStyle(.tertiary)
            Text("No protected apps")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
            Text("Click Add App to protect an app with Touch ID")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .padding(.horizontal, 16)
    }

    // MARK: - Footer

    private var footerActions: some View {
        VStack(spacing: 0) {
            menuButton("Add App…", icon: "plus.circle") {
                addApps()
            }

            if !appState.protectedApps.isEmpty {
                menuButton("Lock All Now", icon: "lock.fill") {
                    Task { await appState.lockAll() }
                }
            }

            Divider()

            menuButton("Settings…", icon: "gear") {
                openSettings()
            }

            menuButton("Quit TouchGate", icon: "power", role: .destructive) {
                NSApp.terminate(nil)
            }
        }
    }

    private func menuButton(
        _ title: String,
        icon: String,
        role: ButtonRole? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .foregroundStyle(role == .destructive ? Color.red : Color.primary)
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    // MARK: - Actions

    private func addApps() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.applicationBundle]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        panel.message = "Select apps to protect with Touch ID"
        panel.prompt = "Protect"

        panel.begin { response in
            guard response == .OK else { return }
            for url in panel.urls {
                // BUG-02 FIX: Pass defaultTimeout so the app's unlockTimeout matches user preference.
                if let app = BundleScanner.scan(url: url, defaultTimeout: defaultUnlockTimeout) {
                    Task { await self.appState.addApp(app) }
                }
            }
        }
    }

    private func openSettings() {
        // showSettingsWindow: was introduced in macOS 13 (renaming showPreferencesWindow:).
        // Our deployment floor is 13.0, so no availability check is needed.
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
