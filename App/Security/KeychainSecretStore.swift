import Foundation
import Security

/// Stores secrets in the login Keychain as generic passwords, one account per provider. Values are never written
/// to settings.json, logs or exports. New items are readable only while this Mac is unlocked and never sync.
struct KeychainSecretStore: SecretStore {
    static let defaultService = "app.captai.captAI.providers"

    let service: String

    init(service: String = KeychainSecretStore.defaultService) {
        self.service = service
    }

    func read(account: String) throws(AppError) -> String? {
        var query = baseQuery(account: account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
                throw AppError.keychainFailed
            }
            return value
        case errSecItemNotFound:
            return nil
        default:
            throw AppError.keychainFailed
        }
    }

    func write(_ value: String, account: String) throws(AppError) {
        let data = Data(value.utf8)
        let query = baseQuery(account: account)
        let updateStatus = SecItemUpdate(query as CFDictionary, [kSecValueData as String: data] as CFDictionary)
        if updateStatus == errSecSuccess { return }
        guard updateStatus == errSecItemNotFound else { throw AppError.keychainFailed }

        var add = query
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        guard SecItemAdd(add as CFDictionary, nil) == errSecSuccess else { throw AppError.keychainFailed }
    }

    func delete(account: String) throws(AppError) {
        let status = SecItemDelete(baseQuery(account: account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw AppError.keychainFailed }
    }

    private func baseQuery(account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
