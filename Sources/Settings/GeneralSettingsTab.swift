import SwiftUI
import AppKit
import ServiceManagement

// General settings: Security Mode (the whole auth policy) + Launch at login.
//
// DESIGN NOTE: Per-app timeout overrides were intentionally removed in favor of a single
// global mode. The underlying ProtectedApp.unlockTimeout field is retained so a future
// release can re-expose per-app overrides via a `usesGlobalMode: Bool` flag on ProtectedApp
// without any Keychain migration.
struct GeneralSettingsTab: View {
    @EnvironmentObject private var appState: AppState
    @State private var launchAtLoginEnabled: Bool = false

    // Inactivity timeout options for Balanced mode, in minutes.
    private let balancedTimeoutOptions: [Int] = [1, 5, 10, 15, 30, 60]

    var body: some View {
        Form {
            Section("Security Mode") {
                Picker("Mode", selection: modeBinding) {
                    ForEach(SecurityMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                // Always-visible explanation. Users must never be surprised by re-lock behavior.
                Text(appState.securityMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if appState.securityMode == .balanced {
                    Picker("Re-lock after", selection: timeoutBinding) {
                        ForEach(balancedTimeoutOptions, id: \.self) { minutes in
                            Text(label(forMinutes: minutes)).tag(minutes)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }

            Section("Startup") {
                // Two-argument onChange closure is macOS 14+; use perform: form for macOS 13 compat.
                Toggle("Launch at login", isOn: $launchAtLoginEnabled)
                    .onChange(of: launchAtLoginEnabled, perform: setLaunchAtLogin)
            }
        }
        .formStyle(.grouped)
        .onAppear {
            if #available(macOS 13.0, *) {
                launchAtLoginEnabled = SMAppService.mainApp.status == .enabled
            }
        }
    }

    // MARK: - Bindings
    //
    // The picker's setter is synchronous, but our state mutations are async (they write
    // through the Keychain before flipping the @Published value). We dispatch into a
    // Task so the Binding's set closure stays sync-compatible.

    private var modeBinding: Binding<SecurityMode> {
        Binding(
            get: { appState.securityMode },
            set: { newMode in
                Task { await appState.setSecurityMode(newMode) }
            }
        )
    }

    private var timeoutBinding: Binding<Int> {
        Binding(
            get: { appState.balancedModeTimeout },
            set: { newValue in
                Task { await appState.setBalancedModeTimeout(newValue) }
            }
        )
    }

    // MARK: - Helpers

    private func label(forMinutes minutes: Int) -> String {
        switch minutes {
        case 1:  return "1 minute"
        case 60: return "1 hour"
        default: return "\(minutes) minutes"
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
