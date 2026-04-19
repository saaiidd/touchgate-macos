// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TouchGate",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "TouchGate",
            path: "Sources",
            exclude: [
                "TouchGate",   // Xcode project folder — not part of SPM build
                "Resources"    // Info.plist + entitlements — not compiled sources
            ],
            sources: [
                "App/TouchGateApp.swift",
                "App/AppDelegate.swift",
                "App/AppState.swift",
                "App/SecurityMode.swift",
                "MenuBar/StatusBarController.swift",
                "MenuBar/MenuBarView.swift",
                "MenuBar/AppRowView.swift",
                "Protection/AppMonitor.swift",
                "Protection/AuthenticationManager.swift",
                "Protection/InterceptionHandler.swift",
                "Protection/IntentPromptWindow.swift",
                "Storage/ProtectedApp.swift",
                "Storage/ProtectedAppStore.swift",
                "Settings/SettingsView.swift",
                "Settings/GeneralSettingsTab.swift",
                "Settings/PermissionsView.swift",
                "Settings/LogView.swift",
                "Settings/GatesSettingsTab.swift",
                "Utilities/BundleScanner.swift",
                "Utilities/UnlockLogger.swift",
                "Utilities/ActiveTimeTracker.swift"
            ],
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
