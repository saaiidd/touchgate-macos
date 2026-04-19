import Foundation

// The single global authentication policy. One enum, three behaviors — all routed through
// AppState.requiresAuthentication(for:) so there is exactly one place where mode logic lives.
//
// Scope notes (surfaced to the user in Settings):
// - .relaxed  → process-lifetime scoped. Killing TouchGate wipes all unlocks.
// - .balanced → persistent across TouchGate restarts; re-locks on inactivity timeout.
// - .strict   → no grace period; every launch prompts.
enum SecurityMode: String, CaseIterable, Identifiable, Sendable {
    case relaxed
    case balanced
    case strict

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .relaxed:  return "Relaxed"
        case .balanced: return "Balanced"
        case .strict:   return "Strict"
        }
    }

    // Always-visible explanation shown below the mode picker in Settings.
    // Wording is deliberately explicit about re-lock scope — users should never be
    // surprised by when TouchGate re-prompts.
    var description: String {
        switch self {
        case .relaxed:
            return "Unlocks last until TouchGate quits or your Mac sleeps. "
                 + "If TouchGate is killed, every app locks again."
        case .balanced:
            return "Apps stay unlocked for the chosen inactivity window, "
                 + "even across TouchGate restarts."
        case .strict:
            return "Every launch requires Touch ID. No grace period."
        }
    }
}
