import AppKit
import SwiftUI

// MARK: - ViewModel

/// Drives the intent prompt UI. All state is @MainActor; the countdown task runs there too.
@MainActor
final class IntentPromptViewModel: ObservableObject {
    @Published var reason: String = ""
    @Published var secondsRemaining: Int = 3
    @Published var timerPaused: Bool = false

    /// Nilled immediately after the first resume to prevent double-resume crashes.
    var continuation: CheckedContinuation<String?, Never>?
    private var countdownTask: Task<Void, Never>?

    /// Start the 3-second countdown. Each 100ms tick decrements the display every 10 ticks.
    /// Pauses permanently when `timerPaused` becomes true (user typed something).
    func startCountdown() {
        countdownTask = Task { @MainActor in
            var ticks = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 100_000_000) // 100 ms
                guard !Task.isCancelled else { break }
                guard !timerPaused else { continue }
                ticks += 1
                if ticks % 10 == 0 {
                    secondsRemaining -= 1
                    if secondsRemaining <= 0 {
                        submit(reason: "")  // timer elapsed — empty reason means "skipped"
                        break
                    }
                }
            }
        }
    }

    /// User pressed Continue or Return, or the timer elapsed.
    /// `reason: ""` → timer/skipped; non-empty → typed intent.
    func submit(reason: String) {
        countdownTask?.cancel()
        countdownTask = nil
        let c = continuation
        continuation = nil
        c?.resume(returning: reason)
    }

    /// User pressed "Don't Open" or Escape — no Touch ID, app stays closed.
    func cancel() {
        countdownTask?.cancel()
        countdownTask = nil
        let c = continuation
        continuation = nil
        c?.resume(returning: nil)
    }
}

// MARK: - Countdown Ring

struct CountdownRingView: View {
    let secondsRemaining: Int
    let totalSeconds: Int = 3
    let isHidden: Bool

    private var fraction: Double {
        guard totalSeconds > 0 else { return 0 }
        return max(0, Double(secondsRemaining) / Double(totalSeconds))
    }

    var body: some View {
        Group {
            if !isHidden {
                ZStack {
                    Circle()
                        .stroke(Color.secondary.opacity(0.25), lineWidth: 3)
                        .frame(width: 32, height: 32)
                    Circle()
                        .trim(from: 0, to: fraction)
                        .stroke(
                            Color.accentColor,
                            style: StrokeStyle(lineWidth: 3, lineCap: .round)
                        )
                        .frame(width: 32, height: 32)
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 0.1), value: fraction)
                    Text("\(secondsRemaining)")
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                        .foregroundStyle(.secondary)
                }
                .frame(width: 36, height: 36)
            } else {
                Color.clear.frame(width: 36, height: 36)
            }
        }
    }
}

// MARK: - Intent Prompt View

struct IntentPromptView: View {
    @ObservedObject var viewModel: IntentPromptViewModel
    let appName: String
    let appIcon: NSImage?
    @FocusState private var textFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header: app icon + app name + countdown ring
            HStack(spacing: 12) {
                if let icon = appIcon {
                    Image(nsImage: icon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 48, height: 48)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                } else {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(width: 48, height: 48)
                        .overlay(
                            Image(systemName: "app.fill")
                                .foregroundStyle(.tertiary)
                        )
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text("Opening \(appName)")
                        .font(.system(size: 14, weight: .semibold))
                        .lineLimit(1)
                    Text("Why are you opening this?")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                CountdownRingView(
                    secondsRemaining: viewModel.secondsRemaining,
                    isHidden: viewModel.timerPaused
                )
            }

            // Intent text field
            TextField("e.g. quick check, work task…", text: $viewModel.reason)
                .textFieldStyle(.roundedBorder)
                .focused($textFieldFocused)
                .onSubmit {
                    viewModel.submit(reason: viewModel.reason)
                }
                .onChange(of: viewModel.reason) { newValue in
                    // Pause timer permanently the moment the user starts typing.
                    if !newValue.isEmpty {
                        viewModel.timerPaused = true
                    }
                }

            // Action buttons
            HStack(spacing: 8) {
                Button("Don't Open") {
                    viewModel.cancel()
                }
                .keyboardShortcut(.escape, modifiers: [])

                Spacer()

                Button("Continue") {
                    viewModel.submit(reason: viewModel.reason)
                }
                .keyboardShortcut(.return, modifiers: [])
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 400)
        .onAppear {
            viewModel.startCountdown()
            // Delay focus slightly so the window is key before the field requests focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                textFieldFocused = true
            }
        }
    }
}

// MARK: - Intent Prompt Window

/// An NSPanel that hosts IntentPromptView. `@unchecked Sendable` because NSPanel is main-thread
/// only — callers must always use it from the main actor, which the code here guarantees.
final class IntentPromptWindow: NSPanel, NSWindowDelegate, @unchecked Sendable {

    let viewModel: IntentPromptViewModel

    init(appName: String, appIcon: NSImage?) {
        viewModel = IntentPromptViewModel()

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 160),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        level = .modalPanel
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        hidesOnDeactivate = false

        let hostingController = NSHostingController(
            rootView: IntentPromptView(
                viewModel: viewModel,
                appName: appName,
                appIcon: appIcon
            )
        )

        // Fit the window exactly to the SwiftUI content.
        let fittingSize = hostingController.sizeThatFits(in: CGSize(width: 400, height: 10_000))
        setContentSize(fittingSize)
        contentViewController = hostingController

        delegate = self
        center()
    }

    // Required for TextField to receive key events inside a .nonactivatingPanel.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    /// Show the window and suspend the caller until the user submits a reason, skips, or cancels.
    /// Returns the typed reason (`String`), an empty string if the timer elapsed / skipped,
    /// or `nil` if the user chose "Don't Open".
    @MainActor
    func promptAndWait() async -> String? {
        await withCheckedContinuation { continuation in
            viewModel.continuation = continuation
            makeKeyAndOrderFront(nil)
        }
    }

    // MARK: NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Red X or any external close — treat as "Don't Open".
        if viewModel.continuation != nil {
            viewModel.cancel()
        }
    }
}

// MARK: - Gate Blocked ViewModel

/// Drives the gate-blocked panel. Resolves `Void` — the user only needs to dismiss it.
@MainActor
final class GateBlockedViewModel: ObservableObject {
    var continuation: CheckedContinuation<Void, Never>?

    func dismiss() {
        let c = continuation
        continuation = nil
        c?.resume()
    }
}

// MARK: - Gate Blocked View

struct GateBlockedView: View {
    @ObservedObject var viewModel: GateBlockedViewModel
    let blockedAppName: String
    let requiredAppName: String
    let requiredMinutes: Int
    let doneMinutes: Int
    let blockedAppIcon: NSImage?

    private var progress: Double {
        guard requiredMinutes > 0 else { return 1 }
        return min(1, Double(doneMinutes) / Double(requiredMinutes))
    }

    private var remaining: Int { max(0, requiredMinutes - doneMinutes) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // Header
            HStack(spacing: 12) {
                Group {
                    if let icon = blockedAppIcon {
                        Image(nsImage: icon)
                            .resizable()
                            .interpolation(.high)
                            .frame(width: 48, height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    } else {
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.secondary.opacity(0.2))
                            .frame(width: 48, height: 48)
                    }
                }
                .opacity(0.55)  // dimmed — app is locked

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(blockedAppName) is locked")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Finish your prerequisite first")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }

            // Progress
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(requiredAppName)
                        .font(.system(size: 12, weight: .medium))
                    Spacer()
                    Text("\(doneMinutes) / \(requiredMinutes) min")
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(remaining == 0 ? .green : .secondary)
                }
                ProgressView(value: progress)
                    .tint(remaining == 0 ? .green : .accentColor)
                Text(footerMessage)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            // Dismiss
            HStack {
                Spacer()
                Button("Got It") { viewModel.dismiss() }
                    .keyboardShortcut(.return, modifiers: [])
                    .keyboardShortcut(.escape, modifiers: [])
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private var footerMessage: String {
        switch remaining {
        case 0:  return "Requirement met — try opening \(blockedAppName) again."
        case 1:  return "1 more minute of \(requiredAppName) needed today."
        default: return "\(remaining) more minutes of \(requiredAppName) needed today."
        }
    }
}

// MARK: - Gate Blocked Window

/// Floating panel that tells the user their prerequisite gate isn't met yet.
/// Suspends the caller until the user dismisses it.
final class GateBlockedWindow: NSPanel, NSWindowDelegate, @unchecked Sendable {

    let viewModel: GateBlockedViewModel

    init(
        blockedAppName: String,
        requiredAppName: String,
        requiredMinutes: Int,
        doneMinutes: Int,
        blockedAppIcon: NSImage?
    ) {
        viewModel = GateBlockedViewModel()
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 380, height: 180),
            styleMask: [.titled, .closable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        titlebarAppearsTransparent = true
        isMovableByWindowBackground = true
        isReleasedWhenClosed = false
        level = .modalPanel
        collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        hidesOnDeactivate = false

        let host = NSHostingController(
            rootView: GateBlockedView(
                viewModel: viewModel,
                blockedAppName: blockedAppName,
                requiredAppName: requiredAppName,
                requiredMinutes: requiredMinutes,
                doneMinutes: doneMinutes,
                blockedAppIcon: blockedAppIcon
            )
        )
        let sz = host.sizeThatFits(in: CGSize(width: 380, height: 10_000))
        setContentSize(sz)
        contentViewController = host
        delegate = self
        center()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    @MainActor
    func showAndWait() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            viewModel.continuation = c
            makeKeyAndOrderFront(nil)
        }
    }

    func windowWillClose(_ notification: Notification) {
        if viewModel.continuation != nil { viewModel.dismiss() }
    }
}
