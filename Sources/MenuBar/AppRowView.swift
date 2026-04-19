import SwiftUI
import AppKit

struct AppRowView: View {
    @EnvironmentObject private var appState: AppState
    let app: ProtectedApp

    var body: some View {
        HStack(spacing: 10) {
            appIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(app.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text(statusLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                Task { await appState.removeApp(id: app.id) }
            } label: {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.red)
                    .imageScale(.medium)
            }
            .buttonStyle(.plain)
            .help("Remove from protected apps")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .contentShape(Rectangle())
    }

    private var appIcon: some View {
        Group {
            if let iconData = app.iconData, let nsImage = NSImage(data: iconData) {
                Image(nsImage: nsImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 30, height: 30)
            } else {
                Image(systemName: "app.fill")
                    .frame(width: 30, height: 30)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // Mode-aware status label. Reads from AppState rather than the (legacy) per-app
    // unlockTimeout field — that field is retained in storage for a future per-app
    // override feature but is not consulted by the current auth decision.
    private var statusLabel: String {
        let locked = appState.requiresAuthentication(for: app.bundleIdentifier)
        switch appState.securityMode {
        case .strict:
            return "Always requires Touch ID"
        case .relaxed:
            return locked ? "Locked until Touch ID" : "Unlocked this session"
        case .balanced:
            return locked
                ? "Locked · \(appState.balancedModeTimeout)m inactivity window"
                : "Unlocked · \(appState.balancedModeTimeout)m window"
        }
    }
}
