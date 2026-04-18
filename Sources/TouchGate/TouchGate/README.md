# TouchGate

A macOS menu bar utility that gates user-selected applications behind Touch ID (or password fallback). When a protected app launches, TouchGate immediately terminates it, presents a biometric authentication prompt, and relaunches it only on success.

---

## Security Model & Honest Limitations

**What TouchGate does:**  
Detects app launches via `NSWorkspace` notifications, terminates the process, presents the macOS system authentication dialog, and relaunches the app if authentication succeeds.

**What TouchGate does NOT do:**  
- It cannot intercept or block an app launch before it starts executing. macOS does not expose a user-space pre-launch hook without kernel extensions.
- Protected apps will briefly flash on screen before termination. This is an unavoidable artifact of the terminate-and-relaunch model.
- It is not a substitute for full-disk encryption, FileVault, or enterprise MDM policies.

**Known limitations:**
- A determined local user can quit TouchGate via Activity Monitor or remove it from Login Items, bypassing protection entirely.
- Apps launched by scripts, Terminal, or Automator before TouchGate's monitor initialises may not be intercepted.
- Apps with multiple instances: all instances are terminated and a single auth prompt is shown.
- macOS Sandboxed App Store distribution is not possible — TouchGate requires direct distribution due to its use of process termination APIs.

**This app is a personal deterrent, not a security hardening tool for sensitive data.**

---

## Requirements

- **macOS 13.0 (Ventura) or later**
- Xcode 15 or later
- A Mac with Touch ID (or Apple Watch for authentication fallback)

---

## Xcode Project Setup

Since this repo ships Swift source files only (no `.xcodeproj`), follow these steps to create the project and wire everything in:

### Step 1 — Create the Xcode project

1. Open Xcode → File → New → Project
2. Choose **macOS → App**
3. Set:
   - **Product Name**: `TouchGate`
   - **Bundle Identifier**: `com.yourname.touchgate` (or any reverse-DNS identifier)
   - **Interface**: SwiftUI
   - **Language**: Swift
4. Save to this repository directory

### Step 2 — Replace the generated files

Delete the auto-generated `ContentView.swift` and `YourAppName.swift` (the default App entry point). Then add all `.swift` files from this repo by dragging them into Xcode, maintaining the folder group structure.

Folder structure to recreate in Xcode (all groups, not real filesystem folders):
```
TouchGate/
  App/           TouchGateApp.swift, AppDelegate.swift, AppState.swift
  MenuBar/       StatusBarController.swift, MenuBarView.swift, AppRowView.swift
  Protection/    AppMonitor.swift, AuthenticationManager.swift, InterceptionHandler.swift
  Storage/       ProtectedApp.swift, ProtectedAppStore.swift
  Settings/      SettingsView.swift, GeneralSettingsTab.swift, PermissionsView.swift, LogView.swift
  Utilities/     BundleScanner.swift, UnlockLogger.swift
  Resources/     Info.plist, TouchGate.entitlements
```

### Step 3 — Configure Info.plist

1. In your target's **Build Settings**, set **Info.plist File** to `TouchGate/Resources/Info.plist`
2. Or replace the default `Info.plist` with the one from `TouchGate/Resources/Info.plist`

Key entries required:
| Key | Value |
|-----|-------|
| `LSUIElement` | `YES` |
| `NSAccessibilityUsageDescription` | *(see Info.plist)* |
| `LSMinimumSystemVersion` | `13.0` |

### Step 4 — Configure Signing & Capabilities

1. Select the **TouchGate** target → **Signing & Capabilities**
2. Set your **Team** and ensure **Automatically manage signing** is checked
3. Under **Hardened Runtime**, enable it (click **+** → **Hardened Runtime** if not present)
4. Set the **Entitlements File** to `TouchGate/Resources/TouchGate.entitlements`
5. Confirm `com.apple.security.app-sandbox` is `false` in the entitlements

**Do NOT enable App Sandbox** — it will break process termination.

### Step 5 — Add frameworks

In **Build Phases → Link Binary With Libraries**, add:
- `LocalAuthentication.framework`
- `Security.framework`
- `ServiceManagement.framework`

(AppKit and SwiftUI are linked automatically.)

### Step 6 — Build & Run

- `Cmd+B` to build — should compile with zero errors
- `Cmd+R` to run — the TouchGate shield icon appears in the menu bar
- No Dock icon should appear (LSUIElement = YES)

---

## Granting Accessibility Permission

Accessibility permission is optional but improves reliability for terminating some apps.

1. Launch TouchGate
2. Click the shield icon in the menu bar
3. Click **Settings…** → **Permissions** tab
4. If status shows **Not Granted**, click **Open Accessibility Settings**
5. In System Settings → Privacy & Security → Accessibility:
   - Find `TouchGate` in the list (you may need to click `+` and navigate to the app)
   - Toggle it ON
6. Return to TouchGate's Permissions tab and click **Check Again**

The status badge should turn green.

---

## Adding Protected Apps

1. Click the shield icon in the menu bar
2. Click **Add App…**
3. Navigate to `/Applications` (default) and select one or more apps
4. Click **Protect**

The apps appear in the popover list. The next time you launch one, you'll be prompted for Touch ID.

---

## Unlock Grace Period

After authenticating, you can configure a grace period during which the app can relaunch without a new prompt:

1. Open **Settings… → General**
2. Set the **Default timeout** (5 / 15 / 30 min, 1 hour, or Always require)
3. Per-app overrides are listed below the global default

Set timeout to **Always require Touch ID** (0) for maximum friction.

## Lock All / Lock Now

- **Menu bar popover** → "Lock All Now" clears all grace periods immediately
- **Settings → General** → Per-app row → "Lock Now" clears that app's grace period

---

## Debug Mode

To enable verbose logging, add the following to your Xcode scheme's **Environment Variables**:
```
TOUCHGATE_DEBUG = 1
```

Log output appears in Xcode's console (or Console.app filtered by process "TouchGate").

Unlock attempt history is stored in:
```
~/Library/Application Support/TouchGate/unlock_log.json
```

---

## Architecture Notes

| Component | Type | Responsibility |
|-----------|------|----------------|
| `AppState` | `@MainActor` class | Single source of truth; owns all sub-components |
| `ProtectedAppStore` | `actor` | Keychain read/write for protected app list |
| `InterceptionHandler` | `actor` | Terminate → authenticate → return result pipeline |
| `AuthenticationManager` | `final class` | Stateless `LAContext` wrapper; new context per call |
| `AppMonitor` | `class` | `NSWorkspace` notification observer; debounces rapid relaunches |
| `UnlockLogger` | `actor` | JSON log file in Application Support |
| `StatusBarController` | `@MainActor` class | `NSStatusItem` + `NSPopover`; observes AppState via Combine |

All Swift concurrency rules are observed: `async/await` throughout, no `DispatchQueue.main.async` except at framework callback boundaries, and `Sendable` conformance where shared across actor boundaries.
