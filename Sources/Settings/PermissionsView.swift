import SwiftUI
import AppKit

struct PermissionsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            accessibilityRow
            explanationText
            Spacer()
            refreshButton
        }
        .padding(4)
        .onAppear {
            appState.checkAccessibilityPermission()
        }
    }

    // MARK: - Accessibility Row

    private var accessibilityRow: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 14) {
                statusIcon
                    .font(.title2)
                    .frame(width: 28)

                VStack(alignment: .leading, spacing: 6) {
                    HStack {
                        Text("Accessibility")
                            .font(.headline)
                        Spacer()
                        statusBadge
                    }

                    Text(accessibilityDescription)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if !appState.hasAccessibilityPermission {
                        Button("Open Accessibility Settings") {
                            openAccessibilitySettings()
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .padding(.top, 2)
                    }
                }
            }
            .padding(6)
        }
    }

    private var statusIcon: some View {
        Group {
            if appState.hasAccessibilityPermission {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            }
        }
    }

    private var statusBadge: some View {
        Text(appState.hasAccessibilityPermission ? "Granted" : "Not Granted")
            .font(.caption)
            .fontWeight(.medium)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(appState.hasAccessibilityPermission ? Color.green.opacity(0.15) : Color.orange.opacity(0.15))
            .foregroundStyle(appState.hasAccessibilityPermission ? .green : .orange)
            .clipShape(Capsule())
    }

    private var accessibilityDescription: String {
        appState.hasAccessibilityPermission
            ? "TouchGate can reliably terminate protected apps before they fully initialise."
            : "Without Accessibility, app termination may be less reliable on some sandboxed apps. Basic protection still works via NSWorkspace monitoring."
    }

    // MARK: - Explanation

    private var explanationText: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Why Accessibility is needed")
                .font(.subheadline)
                .fontWeight(.medium)

            // LIMITATION: Describe the honest protection model to the user.
            Text("TouchGate cannot intercept app launches before they occur — macOS doesn't permit this at the user-space level. Instead, it detects a launch via workspace notifications, immediately terminates the app, and relaunches it after authentication. Accessibility permission makes the termination step more reliable.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var refreshButton: some View {
        HStack {
            Spacer()
            Button("Check Again") {
                appState.checkAccessibilityPermission()
            }
            .buttonStyle(.bordered)
        }
    }

    // MARK: - Actions

    private func openAccessibilitySettings() {
        // Deep-links directly to the Accessibility pane in System Settings.
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") else { return }
        NSWorkspace.shared.open(url)
    }
}
