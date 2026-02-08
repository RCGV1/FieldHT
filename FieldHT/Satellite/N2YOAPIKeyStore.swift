import Foundation
import Security

enum N2YOAPIKeyStore {
    private static let defaultsKey = "N2YO_API_KEY"

    // Keep identifiers stable so users keep their key across updates.
    private static let service = "com.fieldht.n2yo"
    private static let account = "apiKey"

    static func get() -> String? {
        // Migrate any legacy UserDefaults value into Keychain once.
        if let legacy = UserDefaults.standard.string(forKey: defaultsKey)?.trimmingCharacters(in: .whitespacesAndNewlines), !legacy.isEmpty {
            set(legacy)
            UserDefaults.standard.removeObject(forKey: defaultsKey)
            return legacy
        }

        guard let data = readKeychainData(service: service, account: account) else { return nil }
        guard let s = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else { return nil }
        return s
    }

    static func set(_ key: String) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clear()
            return
        }

        let data = Data(trimmed.utf8)
        writeKeychainData(data, service: service, account: account)
    }

    static func clear() {
        deleteKeychainItem(service: service, account: account)
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

private func readKeychainData(service: String, account: String) -> Data? {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne
    ]

    var item: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &item)
    guard status == errSecSuccess else { return nil }
    return item as? Data
}

private func writeKeychainData(_ data: Data, service: String, account: String) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account
    ]

    let attributes: [String: Any] = [
        kSecValueData as String: data,
        kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
    ]

    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecItemNotFound {
        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        _ = SecItemAdd(add as CFDictionary, nil)
    }
}

private func deleteKeychainItem(service: String, account: String) {
    let query: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account
    ]
    _ = SecItemDelete(query as CFDictionary)
}
