import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        TabView {
            GeneralSettingsTab()
                .environmentObject(appState)
                .tabItem { Label("General", systemImage: "gear") }

            PermissionsView()
                .environmentObject(appState)
                .tabItem { Label("Permissions", systemImage: "lock.shield") }

            LogView()
                .environmentObject(appState)
                .tabItem { Label("Log", systemImage: "list.bullet.clipboard") }
        }
        .frame(width: 560, height: 540)
        .padding(20)
    }
}
