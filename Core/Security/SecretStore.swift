import Foundation

/// Keeps secrets such as provider API keys out of settings, logs and exports. The Keychain implementation
/// lives in `App/Security`; tests use an in-memory store.
protocol SecretStore: Sendable {
    /// The stored value for `account`, or nil when none is stored.
    func read(account: String) throws(AppError) -> String?
    /// Stores or replaces the value for `account`.
    func write(_ value: String, account: String) throws(AppError)
    /// Removes the value for `account`. Removing a missing value is not an error.
    func delete(account: String) throws(AppError)
}
