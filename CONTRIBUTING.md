# Contributing to TouchGate

Thanks for your interest in contributing! Whether it's bug reports, feature requests, or code contributions, all help is appreciated.

## Getting Started

### Prerequisites
- macOS 13.0 or later
- Xcode 15+ or Swift 5.9 command-line tools
- Git
- Accessibility permission granted to Xcode/Terminal

### Local Development Setup

```bash
git clone https://github.com/yourusername/TouchGate.git
cd TouchGate

# Build the app
make build

# Run for testing
make run

# Or build and install to Applications folder
make install
```

## How to Report Bugs

### Before Submitting a Bug Report
- Check the [README troubleshooting section](./README.md#troubleshooting)
- Search existing issues to avoid duplicates
- Confirm you have granted Accessibility permission

### Submitting a Bug Report

Include:
1. **macOS version** (e.g., "macOS 14.2.1")
2. **Mac model** (e.g., "M2 MacBook Pro")
3. **TouchGate version** (from app about/settings)
4. **Steps to reproduce** the issue
5. **Actual behavior** vs. **expected behavior**
6. **Relevant logs** from **Settings → Log** (if applicable)
7. **Screenshots** if visually relevant

**Example:**
```
Title: Touch ID prompt stuck on timeout = 5 minutes

macOS: 14.2.1
Mac: M1 Mac mini
TouchGate: 1.0.0

Steps to reproduce:
1. Add Safari to protected apps
2. Set default timeout to 5 minutes
3. Authenticate Safari
4. Wait 4 minutes and try launching again (works ✓)
5. Wait 2 more minutes (now past 5 min) and try launching

Expected: Touch ID prompt appears
Actual: App launches silently without prompt

Log: [attached screenshot of last unlock in Settings → Log]
```

## How to Suggest Features

### Before Suggesting
- Check if the feature already exists in **Settings**
- Search existing issues (it may be under discussion)
- Consider the project scope — TouchGate is intentionally lightweight

### Suggesting a Feature

Describe:
1. **The use case** — why do you need this?
2. **Current workaround** (if any)
3. **Proposed solution** (or ideas if you're not sure)
4. **Alternatives considered**

**Example:**
```
Title: Global hotkey to lock all apps (e.g., Cmd+Shift+L)

Use case: I want to quickly re-lock all apps when I step away from my desk

Current workaround: Open menu bar, click "Lock All Now"

Proposed solution: Add keyboard shortcut (user-configurable) to trigger lock all

Alternatives: Use Automator/Scripts to call a CLI flag like `TouchGate --lock-all`
```

## Code Contribution Workflow

### 1. Fork and Branch

```bash
# Fork on GitHub, then:
git clone https://github.com/your-username/TouchGate.git
cd TouchGate
git checkout -b feature/my-feature
```

### 2. Make Your Changes

**Style Guide:**
- Follow existing code style (Swift conventions)
- Use meaningful variable names
- Comment complex logic with `// SECURITY:` or `// LIMITATION:` prefixes where relevant
- Add `@MainActor` to UI-related classes
- Use `actor` for concurrent components
- Prefer async/await over completion handlers

**Example:**
```swift
// GOOD: Clear, documented
@MainActor
final class MyNewFeature {
    private let logger: UnlockLogger
    
    func performAction() async throws {
        // LIMITATION: This only works on macOS 13+
        try await logger.log(event: "action")
    }
}

// AVOID: Unclear
func doThing(_ x: Any, _ y: Any) {
    // update y with x
}
```

### 3. Test Your Changes

```bash
# Build release binary
make build

# Run with your changes
make run

# Test the feature thoroughly:
# - Add/remove protected apps
# - Test with different timeout settings
# - Check Settings tabs load properly
# - Verify Accessibility permission checks work
# - Check Settings → Log shows your actions
# - Try "Lock All Now"
```

### 4. Commit with Clear Messages

```bash
git add .
git commit -m "Fix: prevent infinite loop when timeout is 0

- Added justAuthenticated set to track post-auth relaunches
- Allow exactly one relaunch regardless of timeout setting
- Fixes #42"
```

**Commit message format:**
- Type: `Fix:`, `Feature:`, `Refactor:`, `Docs:`, `Test:`, `Perf:`
- Summary (50 chars max)
- Blank line
- Details (explain *why*, not just *what*)
- Reference issues: `Fixes #123`, `Relates to #456`

### 5. Push and Create Pull Request

```bash
git push origin feature/my-feature
```

Then open a PR on GitHub. Fill in the template:
- **Description**: What does this change do?
- **Motivation**: Why is this needed?
- **Testing**: How did you test it?
- **Checklist**: Did you update docs? Run tests?

## Code Review Process

Maintainers will review your PR within 7 days. Be prepared to:
- Explain your approach
- Discuss alternatives
- Make revisions if requested
- Handle edge cases (e.g., what if Keychain is unavailable?)

## Project Architecture

### Key Components

**Data Layer** (`Storage/`)
- `ProtectedApp.swift` — Core model with computed `isCurrentlyUnlocked`
- `ProtectedAppStore.swift` — Actor-isolated Keychain persistence

**Security** (`Protection/`)
- `AppMonitor.swift` — NSWorkspace notifications, debouncing, post-auth handling
- `AuthenticationManager.swift` — Touch ID/password prompt, LAError handling
- `InterceptionHandler.swift` — Terminate → authenticate → relaunch pipeline

**UI** (`MenuBar/` + `Settings/`)
- `StatusBarController.swift` — NSStatusItem + NSPopover
- `MenuBarView.swift` — Popover contents
- `SettingsView.swift` — TabView container
- `GeneralSettingsTab.swift`, `PermissionsView.swift`, `LogView.swift` — Tab contents

**Utilities** (`Utilities/`)
- `UnlockLogger.swift` — JSON log file persistence
- `BundleScanner.swift` — Extract app metadata

### Design Principles

1. **Security by default**: No plaintext, all Keychain + encryption
2. **Honest limitations**: Document what we can't do (brief flash, not kernel-level)
3. **Minimal permissions**: Only request Accessibility (not Full Disk Access)
4. **Swift concurrency**: async/await, @MainActor, actors (not DispatchQueue)
5. **Fail gracefully**: Missing icon → system icon, Keychain unavailable → empty list

## Testing Guidelines

### Manual Testing Checklist

- [ ] Add an app (verify icon displays, app appears in list)
- [ ] Launch protected app (verify brief flash → Touch ID prompt)
- [ ] Authenticate (verify app relaunches, Settings → Log shows success)
- [ ] Change timeout (verify grace period respected)
- [ ] "Lock All Now" (verify next launch prompts for auth)
- [ ] Revoke Accessibility (verify graceful degradation, helpful message)
- [ ] Quit and relaunch TouchGate (verify protected apps persist)
- [ ] Open in dark/light mode (verify icons render correctly)

### Automated Tests

Currently, most testing is manual. If you'd like to add automated tests:
- Use XCTest for unit tests
- Place in a new `Tests/` directory
- PR can include test infrastructure setup

## Documentation

Updates needed for:
- **README.md** — User-facing docs, feature descriptions
- **CONTRIBUTING.md** — Developer docs (this file)
- **Code comments** — Complex logic, security decisions, limitations
- **Architecture notes** — Design decisions in code/comments

## Release Process

(Maintainer-only, but good to know)

1. Update version in Package.swift and Info.plist
2. Update CHANGELOG (if exists)
3. Tag release: `git tag -a v1.0.0 -m "Version 1.0.0"`
4. Push tag: `git push origin v1.0.0`
5. Create GitHub Release with binary + notes

## Community Guidelines

- **Be respectful** — Code review feedback is never personal
- **Assume good intent** — Questions are for understanding, not criticism
- **Help others** — Answer questions in issues/discussions
- **Give credit** — Acknowledge prior art, reference relevant issues

## Stuck? Need Help?

- Check [README troubleshooting](./README.md#troubleshooting)
- Search existing issues and discussions
- Open a discussion if your question doesn't fit a bug/feature request

---

**Thank you for contributing!** 🛡️
