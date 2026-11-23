import Foundation
import Security

/// Items kept in the Keychain (PLAN.md section 5: the JWT and the password verifier).
enum SecretKey: String, CaseIterable {
    case authToken = "auth.token"
    case passwordVerifier = "password.verifier"
}

protocol SecretStoring: AnyObject {
    func data(for key: SecretKey) throws -> Data?
    func set(_ data: Data, for key: SecretKey) throws
    func remove(_ key: SecretKey) throws
}

struct KeychainError: Error, LocalizedError, Equatable {
    let status: OSStatus

    var errorDescription: String? {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "unknown error"
        return "Keychain error \(status): \(message)"
    }
}

/// Generic-password items, readable after the first unlock and never synced or backed
/// up to another device.
final class KeychainSecretStore: SecretStoring {
    let service: String

    init(service: String = (Bundle.main.bundleIdentifier ?? "ConcentrationMaxx") + ".secrets") {
        self.service = service
    }

    func data(for key: SecretKey) throws -> Data? {
        var query = baseQuery(key)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            return result as? Data
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError(status: status)
        }
    }

    func set(_ data: Data, for key: SecretKey) throws {
        let update: [String: Any] = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery(key) as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var item = baseQuery(key)
            item[kSecValueData as String] = data
            item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        default:
            throw KeychainError(status: status)
        }
    }

    func remove(_ key: SecretKey) throws {
        let status = SecItemDelete(baseQuery(key) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }

    private func baseQuery(_ key: SecretKey) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword,
         kSecAttrService as String: service,
         kSecAttrAccount as String: key.rawValue]
    }
}

final class InMemorySecretStore: SecretStoring {
    private(set) var items: [SecretKey: Data] = [:]

    func data(for key: SecretKey) throws -> Data? { items[key] }
    func set(_ data: Data, for key: SecretKey) throws { items[key] = data }
    func remove(_ key: SecretKey) throws { items[key] = nil }
}
