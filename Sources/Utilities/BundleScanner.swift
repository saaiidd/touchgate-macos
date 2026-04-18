import AppKit

enum BundleScanner {
    // Extracts all metadata needed to create a ProtectedApp entry from a .app bundle URL.
    // BUG-02 FIX: Accept caller-supplied defaultTimeout so user's preference is applied immediately.
    // BUG-08 FIX: Use url.path(percentEncoded: false) — url.path is deprecated in Swift 5.7+.
    static func scan(url: URL, defaultTimeout: TimeInterval = 0) -> ProtectedApp? {
        guard
            let bundle = Bundle(url: url),
            let bundleId = bundle.bundleIdentifier
        else { return nil }

        let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        // BUG-08 FIX: url.path(percentEncoded: false) replaces deprecated url.path.
        let fsPath = url.path(percentEncoded: false)
        let icon = NSWorkspace.shared.icon(forFile: fsPath)
        // BUG-05 FIX: Downscale to 64×64 before storing. Raw TIFF from NSWorkspace can be
        // 200–500 KB per icon; multiplied across several apps this exceeds Keychain's ~1 MB
        // per-item limit. 64×64 produces ~25 KB TIFF — well within safe margins.
        let iconData = resizedIcon(icon)

        return ProtectedApp(
            bundleIdentifier: bundleId,
            displayName: name,
            bundlePath: fsPath,
            iconData: iconData,
            unlockTimeout: defaultTimeout
        )
    }

    // MARK: - Private

    // Renders `image` into a new 64×64 NSImage and returns its TIFF data.
    private static func resizedIcon(
        _ image: NSImage,
        size: CGSize = CGSize(width: 64, height: 64)
    ) -> Data? {
        let result = NSImage(size: size)
        result.lockFocus()
        image.draw(
            in: NSRect(origin: .zero, size: size),
            from: .zero,
            operation: .copy,
            fraction: 1
        )
        result.unlockFocus()
        return result.tiffRepresentation
    }
}
