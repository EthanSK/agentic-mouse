import Foundation
import Security

/// Device-local storage for the optional Keys Mode password action.
///
/// The value never enters Agentic Mouse configuration, generated Karabiner
/// JSON, the clipboard, or logs. `WhenUnlockedThisDeviceOnly` also gives the
/// lock-screen boundary an independent Keychain enforcement layer.
enum StoredPasswordKeychain {
    enum StoreError: Error, Equatable {
        case invalidEncoding
        case keychain(OSStatus)
    }

    private static let service = "com.ethan.agentic-mouse.keys-mode-password"
    private static let account = "local-user"

    static var isConfigured: Bool { load() != nil }

    static func load() -> String? {
        var result: CFTypeRef?
        let status = SecItemCopyMatching(
            baseQuery.merging([
                kSecReturnData as String: true,
                kSecMatchLimit as String: kSecMatchLimitOne,
            ]) { _, new in new } as CFDictionary,
            &result
        )
        guard status == errSecSuccess,
              let data = result as? Data,
              let password = String(data: data, encoding: .utf8),
              !password.isEmpty
        else { return nil }
        return password
    }

    static func save(_ password: String) -> Result<Void, StoreError> {
        guard !password.isEmpty,
              let data = password.data(using: .utf8)
        else { return .failure(.invalidEncoding) }

        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )
        if updateStatus == errSecSuccess { return .success(()) }
        guard updateStatus == errSecItemNotFound else {
            return .failure(.keychain(updateStatus))
        }

        var addQuery = baseQuery
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        return addStatus == errSecSuccess
            ? .success(())
            : .failure(.keychain(addStatus))
    }

    static func clear() -> Result<Void, StoreError> {
        let status = SecItemDelete(baseQuery as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
            ? .success(())
            : .failure(.keychain(status))
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
