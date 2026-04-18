import AppKit
import SwiftUI
import Combine

// NSObject inheritance is required for the @objc selector used by NSStatusBarButton target/action.
@MainActor
final class StatusBarController: NSObject {
    private var statusItem: NSStatusItem?
    private var popover: NSPopover?
    private let appState: AppState
    private var cancellables = Set<AnyCancellable>()

    init(appState: AppState) {
        self.appState = appState
        setupStatusItem()
        setupPopover()
        observeIconState()
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
        // $protectedApps fires with the NEW array already set, so computing icon state here is safe.
        appState.$protectedApps
            .receive(on: RunLoop.main)
            .sink { [weak self] apps in
                guard let self else { return }
                let state: AppState.MenuBarIconState
                if apps.isEmpty {
                    state = .neutral
                } else if apps.contains(where: { $0.isCurrentlyUnlocked }) {
                    state = .unlocked
                } else {
                    state = .locked
                }
                self.updateButtonImage(state: state)
            }
            .store(in: &cancellables)
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
