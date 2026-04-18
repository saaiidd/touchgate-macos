import Foundation
import Security

// SECURITY: All protected app data lives in Keychain, never in UserDefaults or plain files.
actor ProtectedAppStore {
    private let service = "com.touchgate.protectedapps"
    private let account = "protected-apps-list"

    func load() throws -> [ProtectedApp] {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        switch status {
        case errSecSuccess:
            guard let data = result as? Data else {
                throw KeychainError.unexpectedData
            }
            return try JSONDecoder().decode([ProtectedApp].self, from: data)

        // Not finding an item is valid — first launch has no saved list.
        case errSecItemNotFound:
            return []

        default:
            throw KeychainError.unexpectedStatus(status)
        }
    }

    func save(_ apps: [ProtectedApp]) throws {
        let data = try JSONEncoder().encode(apps)

        let searchQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]

        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(searchQuery as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecItemNotFound {
            // First save — create the item.
            var addQuery = searchQuery
            addQuery[kSecValueData as String] = data
            // SECURITY: Only accessible when device is unlocked, non-migratable.
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if updateStatus != errSecSuccess {
            throw KeychainError.unexpectedStatus(updateStatus)
        }
    }

    enum KeychainError: Error, LocalizedError {
        case unexpectedData
        case unexpectedStatus(OSStatus)

        var errorDescription: String? {
            switch self {
            case .unexpectedData:
                return "Keychain contained data in an unexpected format."
            case .unexpectedStatus(let status):
                return "Keychain operation failed (OSStatus \(status))."
            }
        }
    }
}
