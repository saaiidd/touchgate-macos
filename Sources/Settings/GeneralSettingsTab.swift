import SwiftUI
import AppKit
import ServiceManagement

struct GeneralSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @AppStorage("defaultUnlockTimeout") private var defaultUnlockTimeout: Double = 0
    @State private var launchAtLoginEnabled: Bool = false

    private let timeoutOptions: [(label: String, seconds: Double)] = [
        ("Always require Touch ID", 0),
        ("5 minutes", 300),
        ("15 minutes", 900),
        ("30 minutes", 1800),
        ("1 hour", 3600)
    ]

    var body: some View {
        Form {
            Section("Startup") {
                // Two-argument onChange closure is macOS 14+; use perform: form for macOS 13 compat.
                Toggle("Launch at login", isOn: $launchAtLoginEnabled)
                    .onChange(of: launchAtLoginEnabled, perform: setLaunchAtLogin)
            }

            Section("Unlock Timeout") {
                Picker("Default timeout", selection: $defaultUnlockTimeout) {
                    ForEach(timeoutOptions, id: \.seconds) { opt in
                        Text(opt.label).tag(opt.seconds)
                    }
                }
                .pickerStyle(.menu)

                Text("After authenticating, the app can relaunch without a new prompt for this long.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !appState.protectedApps.isEmpty {
                Section("Per-App Overrides") {
                    ForEach(appState.protectedApps) { app in
                        AppTimeoutRow(app: app, defaultTimeout: defaultUnlockTimeout, timeoutOptions: timeoutOptions)
                            .environmentObject(appState)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if #available(macOS 13.0, *) {
                launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            }
        }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        if #available(macOS 13.0, *) {
            do {
                if enabled {
                    try SMAppService.mainApp.register()
                } else {
                    try SMAppService.mainApp.unregister()
                }
            } catch {
                print("[TouchGate] Launch at login toggle failed: \(error.localizedDescription)")
            }
        }
    }
}

// MARK: - Per-App Row

struct AppTimeoutRow: View {
    @EnvironmentObject private var appState: AppState
    let app: ProtectedApp
    let defaultTimeout: Double
    let timeoutOptions: [(label: String, seconds: Double)]

    var body: some View {
        HStack {
            appIcon

            Text(app.displayName)
                .lineLimit(1)

            Spacer()

            Picker("", selection: timeoutBinding) {
                ForEach(timeoutOptions, id: \.seconds) { opt in
                    Text(opt.label).tag(opt.seconds)
                }
            }
            .labelsHidden()
            .frame(width: 180)

            Button("Lock Now") {
                Task { await appState.lockApp(id: app.id) }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!app.isCurrentlyUnlocked)
        }
    }

    private var timeoutBinding: Binding<Double> {
        Binding(
            get: { app.unlockTimeout },
            set: { newValue in
                Task { await appState.updateTimeout(for: app.id, timeout: newValue) }
            }
        )
    }

    private var appIcon: some View {
        Group {
            if let iconData = app.iconData, let nsImage = NSImage(data: iconData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.fill")
                    .frame(width: 20, height: 20)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
