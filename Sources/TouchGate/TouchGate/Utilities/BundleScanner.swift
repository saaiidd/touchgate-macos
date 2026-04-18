import AppKit

enum BundleScanner {
    // Extracts all metadata needed to create a ProtectedApp entry from a .app bundle URL.
    static func scan(url: URL) -> ProtectedApp? {
        guard
            let bundle = Bundle(url: url),
            let bundleId = bundle.bundleIdentifier
        else { return nil }

        let name = (bundle.infoDictionary?["CFBundleDisplayName"] as? String)
            ?? (bundle.infoDictionary?["CFBundleName"] as? String)
            ?? url.deletingPathExtension().lastPathComponent

        let icon = NSWorkspace.shared.icon(forFile: url.path)
        // Store as TIFF so it round-trips through Codable without quality loss.
        let iconData = icon.tiffRepresentation

        return ProtectedApp(
            bundleIdentifier: bundleId,
            displayName: name,
            bundlePath: url.path,
            iconData: iconData
        )
    }
}
