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

    private var statusLabel: String {
        if app.isCurrentlyUnlocked {
            return "Unlocked (grace period active)"
        } else if app.unlockTimeout == 0 {
            return "Always requires Touch ID"
        } else {
            let minutes = Int(app.unlockTimeout / 60)
            return "Locked · \(minutes)m grace period"
        }
    }
}
