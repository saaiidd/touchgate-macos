# TouchGate

A lightweight macOS menu bar utility that gates app launches behind Touch ID authentication. Protect your most sensitive applications with biometric security in seconds.

![License](https://img.shields.io/badge/license-MIT-green)
![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9+-orange)

## Features

- **One-Click Protection**: Add any macOS application to your protected list
- **Biometric Lock**: Requires Touch ID or password on every launch (configurable)
- **Grace Period**: Option to allow launches within N minutes without re-authentication
- **Menu Bar Integration**: Unobtrusive shield icon shows lock status at a glance
- **Launch at Login**: Automatically start TouchGate when you sign in
- **Audit Log**: View all unlock attempts with timestamps
- **Per-App Timeouts**: Set different grace periods for different apps
- **Lock All**: Instantly reset all grace periods with one click

## System Requirements

- **macOS 13.0** (Ventura) or later
- **M1/M2/Intel** processors supported
- **Touch ID or password** (any authentication method supported by System Settings)
- **Accessibility permission** (required to monitor app launches)

## Quick Start

```bash
git clone https://github.com/yourusername/TouchGate.git
cd TouchGate
make run
```

That's it! The shield icon will appear in your menu bar.

## Installation Options

### Option 1: Run from Build (Simplest for Testing)
```bash
make run
```
Builds and launches TouchGate in the background. Quit anytime from the menu bar.

### Option 2: Install to Applications Folder (Persistent)
```bash
make install
```
Creates `~/Applications/TouchGate.app`. You can:
- Open it from Spotlight (`Cmd+Space` → type "TouchGate")
- Add it to System Settings → General → Login Items for startup launch
- Access it from Finder at `~/Applications/`

### Option 3: Manual Build
```bash
swift build -c release
.build/debug/TouchGate &
```

## Usage

### Adding Protected Apps

1. Click the **shield icon** in your menu bar
2. Click **"Add App..."**
3. Navigate to `/Applications` and select any app
4. Click **Open**
5. The app now appears in your list and is protected

### Protecting an App

Once added, the next time you launch that app:
1. The app will briefly appear then close
2. You'll see a **Touch ID prompt**
3. Complete authentication
4. The app will automatically relaunch

### Grace Period

Set a timeout in **Settings → General** to allow relaunches without re-auth:

- **Always require Touch ID** (0 minutes) — authenticate every single launch
- **5 minutes** — no prompt for 5 minutes after successful auth
- **15 minutes** — no prompt for 15 minutes
- **30 minutes** — no prompt for 30 minutes  
- **1 hour** — no prompt for 1 hour

You can override the default for individual apps in the per-app settings.

### Unlock History

View all unlock attempts in **Settings → Log**:
- Timestamp of each authentication
- App name
- Success or failure (with reason)
- Clear log anytime

### Lock All Now

Click **"Lock All Now"** in the menu to instantly:
- Clear all grace periods
- Reset all "last unlocked" timers
- Force re-authentication on next launch for all protected apps

## Granting Accessibility Permission

TouchGate requires Accessibility permission to monitor app launches. Here's how to grant it:

1. Open the **Settings** tab in TouchGate
2. Go to **Permissions**
3. Click **"Open Accessibility Settings"** (or manually navigate to System Settings → Privacy → Accessibility)
4. Look for **TouchGate** in the list
5. Toggle the switch **ON**
6. You may need to restart TouchGate for the change to take effect

**Why?** Accessibility APIs are the only user-space way to monitor app launches in macOS. This is the same permission that accessibility apps, screen readers, and automation tools require.

## Development

### Building from Source

**Requirements:**
- Xcode 15+ or Swift 5.9 command-line tools
- macOS 13.0 SDK

**Build commands:**
```bash
make build      # Compile release binary
make run        # Build and launch
make install    # Install to ~/Applications/TouchGate.app
make uninstall  # Remove from ~/Applications
make stop       # Kill running process
make clean      # Remove build artifacts
make help       # Show all commands
```

### Project Structure

```
TouchGate/
├── TouchGate/
│   ├── App/                   # Entry point & app state
│   ├── MenuBar/               # Status bar & popover UI
│   ├── Protection/            # Core security logic
│   ├── Storage/               # Keychain persistence
│   ├── Settings/              # Settings UI
│   ├── Utilities/             # Logging & helpers
│   └── Resources/             # Info.plist, entitlements
├── Makefile                   # Build automation
├── Package.swift              # Swift Package manifest
└── README.md                  # This file
```

### Architecture Highlights

- **Swift Concurrency**: async/await throughout, @MainActor for thread safety
- **Keychain Storage**: Secure, encrypted storage of protected app list
- **Terminate & Relaunch**: Practical interception model (see limitations below)
- **Closure-based Notifications**: Modern NSWorkspace observer (not selectors)
- **Actor Isolation**: ProtectedAppStore, InterceptionHandler for concurrent safety

For detailed architecture notes, see [CONTRIBUTING.md](./CONTRIBUTING.md).

## Security & Limitations

### How It Works

TouchGate uses the **terminate-and-relaunch** model:

1. You try to launch a protected app
2. TouchGate detects the launch and immediately terminates the app
3. A Touch ID prompt appears
4. On success, TouchGate relaunches the app
5. On failure, the app stays closed

### Honest Limitations

⚠️ **Brief App Flash**: You will see the app briefly appear and close. This is unavoidable in user-space macOS. Kernel extensions could block pre-launch, but they require elevated system access and are beyond the scope of this tool.

⚠️ **Not a Complete Security Solution**: TouchGate is a **convenience and deterrent**, not military-grade protection. It:
- Only prevents casual unauthorized launches
- Does not encrypt your data
- Cannot prevent someone with physical access from using native macOS tools to disable it
- Should be combined with full-disk encryption (FileVault) for real security

⚠️ **Requires Accessibility Permission**: TouchGate must monitor app launches, which requires the Accessibility permission. Grant it only if you trust the source.

### What It's Good For

✅ Keeping your finances app / email from unauthorized quick access  
✅ Protecting work apps on a shared computer  
✅ Training family members to respect app boundaries  
✅ Adding friction to impulsive app launches  

### What It's NOT Good For

❌ Protecting against determined attackers with physical access  
❌ Preventing data exfiltration if someone gains OS access  
❌ Bypassing macOS security checks (it uses native APIs only)  

## Troubleshooting

### App isn't showing in menu bar
- Check System Settings → Privacy → Accessibility — is TouchGate enabled?
- Restart TouchGate: `make stop && make run`

### Permission errors when adding apps
- Grant Accessibility permission (see above)
- Quit TouchGate and restart: `make stop && make run`

### Protected app still launches without prompt
- Check **Settings → General** — is a grace period set?
- Check **Settings → Log** — confirm auth actually succeeded

### Touch ID/password prompt doesn't appear
- Ensure Accessibility permission is granted
- Check System Settings → Touch ID & Password — is Touch ID available?
- Try entering your Mac password as fallback

## FAQ

**Q: Does TouchGate work with Face ID on a Mac Studio?**  
A: No. Face ID is only available on iPhone/iPad. You'll use your password as fallback.

**Q: Can I export the list of protected apps?**  
A: Files are stored encrypted in Keychain. You can view unlock history in **Settings → Log**.

**Q: Does it work with sandboxed apps?**  
A: Yes. It works with all apps that can be launched via NSWorkspace.

**Q: What if I forget my password?**  
A: Your Mac's password reset process applies (Apple ID recovery, Recovery Mode, etc.).

**Q: Does this slow down my Mac?**  
A: No. TouchGate only runs when you try to launch a protected app. Zero overhead otherwise.

## Contributing

Found a bug? Have a feature idea? See [CONTRIBUTING.md](./CONTRIBUTING.md) for how to help.

## License

MIT License. See [LICENSE](./LICENSE) file for details.

---

**Questions?** Open an issue on GitHub or check the troubleshooting section above.
