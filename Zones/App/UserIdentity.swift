import Foundation
import Security

enum UserIdentity {
    private static let service = "com.zones.app.identity"
    private static let account = "defaultUser"

    static var userId: String {
        if let existing = Keychain.read(service: service, account: account) {
            return existing
        }
        let fresh = UUID().uuidString
        Keychain.save(service: service, account: account, value: fresh)
        return fresh
    }

    static var displayName: String {
        "Runner \(String(userId.prefix(6)))"
    }
}

private enum Keychain {
    static func save(service: String, account: String, value: String) {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        SecItemDelete(query as CFDictionary)
        var newQuery = query
        newQuery[kSecValueData as String] = data
        SecItemAdd(newQuery as CFDictionary, nil)
    }

    static func read(service: String, account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }
}
