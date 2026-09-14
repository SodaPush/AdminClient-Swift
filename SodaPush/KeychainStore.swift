import Foundation
import Security

enum KeychainError: Error, LocalizedError {
    case unexpectedStatus(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .unexpectedStatus(status):
            String(format: String(localized: "Keychain operation failed (%d)."), status)
        }
    }
}

enum KeychainStore {
    private static let service = "zone.phg.SodaPush"

    static func set(_ value: String, account: String) throws {
        let query = baseQuery(account: account)
        SecItemDelete(query as CFDictionary)
        var item = query
        item[kSecValueData] = Data(value.utf8)
        let status = SecItemAdd(item as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
    }

    static func get(account: String) throws -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData] = true
        query[kSecMatchLimit] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError.unexpectedStatus(status)
        }
        return String(data: data, encoding: .utf8)
    }

    static func remove(account: String) throws {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    private static func baseQuery(account: String) -> [CFString: Any] {
        [
            kSecClass: kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: account,
        ]
    }
}
