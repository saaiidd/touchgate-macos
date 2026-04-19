import AppKit
import SwiftUI
import Combine

extension Notification.Name {
    /// Posted by MenuBarView when the user taps "Settings…".
    /// StatusBarController observes this and handles the full open-settings sequence.
    static let touchGateOpenSettings = Notification.Name("com.touchgate.openSettings")
}

// NSObject inheritance is required for the @objc selector used by NSStatusBarButton target/action.
@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        super.init()  // NSObject requires super.init() before any method calls on self
        setupStatusItem()
        setupPopover()
        observeIconState()
        observeOpenSettingsRequest()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        guard let button = statusItem?.button else { return }

        updateButtonImage(state: appState.menuBarIconState)
        button.action = #selector(togglePopover(_:))
        button.target = self
        button.toolTip = "TouchGate"
    }

    private func setupPopover() {
        let popover = NSPopover()
        // .transient closes automatically when the user clicks outside — standard menu bar behavior.
        popover.behavior = .transient
        popover.animates = true
        popover.contentViewController = NSHostingController(
            rootView: MenuBarView()
                .environmentObject(appState)
        )
        self.popover = popover
    }

    private func observeIconState() {
        // Re-evaluate on any change that can affect the icon: protected list, mode, timeout.
        // We merge three Publishers into a single trigger and then recompute via
        // appState.menuBarIconState — the canonical, mode-aware computation.
        //
        // NOTE: Relaxed-mode sleep/wake clearing does NOT flow through Combine (the session
        // set is not @Published). The icon will reconcile on the next launch notification
        // or mode change. Accepted gap — the popover UI reflects ground truth on open.
        let appsChanges = appState.$protectedApps.map { _ in () }
        let modeChanges = appState.$securityMode.map { _ in () }
        let timeoutChanges = appState.$balancedModeTimeout.map { _ in () }

        appsChanges
            .merge(with: modeChanges, timeoutChanges)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                guard let self else { return }
                self.updateButtonImage(state: self.appState.menuBarIconState)
            }
            .store(in: &cancellables)
    }

    // Observe the notification posted by MenuBarView when "Settings…" is tapped.
    // We handle it here because only StatusBarController has a reference to the popover —
    // it must close the popover BEFORE firing showSettingsWindow:, otherwise the transient
    // popover dismisses mid-flight and the action finds no key window to traverse.
    private func observeOpenSettingsRequest() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOpenSettings),
            name: .touchGateOpenSettings,
            object: nil
        )
    }

    @objc private func handleOpenSettings() {
        // 1. Close the popover cleanly.
        popover?.performClose(nil)
        // 2. Wait one run-loop pass for the popover to finish dismissing,
        //    then make the app key and show the settings window.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            _ = self  // retain self until block fires
            NSApp.activate(ignoringOtherApps: true)
            NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        }
    }

    @objc private func togglePopover(_ sender: NSStatusBarButton) {
        guard let popover, let button = statusItem?.button else { return }

        if popover.isShown {
            popover.performClose(sender)
        } else {
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            // Bring the app forward so the popover receives key events immediately.
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func updateButtonImage(state: AppState.MenuBarIconState) {
        let name: String
        switch state {
        case .neutral:  name = "shield"
        case .locked:   name = "lock.shield"
        case .unlocked: name = "lock.open.rotation"
        }
        if let image = NSImage(systemSymbolName: name, accessibilityDescription: "TouchGate") {
            // Template images automatically invert for dark menu bars.
            image.isTemplate = true
            statusItem?.button?.image = image
        }
    }
}
