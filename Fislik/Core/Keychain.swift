import Foundation
import LocalAuthentication
import Security

/// Stores the auth token. When biometrics are enabled the item is protected
/// with `.biometryCurrentSet`, so reading it triggers Face ID.
enum Keychain {
    private static let service = "dev.selamet.fislik"
    private static let tokenAccount = "access_token"
    private static let biometricAccount = "access_token.biometric"

    static func saveToken(_ token: String) {
        save(token, account: tokenAccount, accessControl: nil)
    }

    static func token() -> String? {
        read(account: tokenAccount, context: nil)
    }

    static func saveBiometricToken(_ token: String) -> Bool {
        guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenPasscodeSetThisDeviceOnly, .biometryCurrentSet, nil) else {
            return false
        }
        return save(token, account: biometricAccount, accessControl: access)
    }

    /// Prompts Face ID. Returns nil if cancelled or unavailable.
    static func biometricToken(reason: String) async -> String? {
        let context = LAContext()
        context.localizedReason = reason
        return await Task.detached { read(account: biometricAccount, context: context) }.value
    }

    static var hasBiometricToken: Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        var query = baseQuery(account: biometricAccount)
        query[kSecUseAuthenticationContext as String] = context
        let status = SecItemCopyMatching(query as CFDictionary, nil)
        return status == errSecSuccess || status == errSecInteractionNotAllowed
    }

    static func deleteBiometricToken() { delete(account: biometricAccount) }

    static func clear() {
        delete(account: tokenAccount)
        delete(account: biometricAccount)
    }

    // MARK: Private

    private static func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    @discardableResult
    private static func save(_ value: String, account: String, accessControl: SecAccessControl?) -> Bool {
        delete(account: account)
        var query = baseQuery(account: account)
        query[kSecValueData as String] = Data(value.utf8)
        if let accessControl {
            query[kSecAttrAccessControl as String] = accessControl
        } else {
            query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        }
        return SecItemAdd(query as CFDictionary, nil) == errSecSuccess
    }

    private static func read(account: String, context: LAContext?) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        if let context { query[kSecUseAuthenticationContext as String] = context }
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private static func delete(account: String) {
        SecItemDelete(baseQuery(account: account) as CFDictionary)
    }
}
