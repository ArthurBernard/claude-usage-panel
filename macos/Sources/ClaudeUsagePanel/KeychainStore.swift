import Foundation
import Security

/// Login-Keychain storage for the one secret this app holds: the optional
/// Cursor Admin API key. UserDefaults is a cleartext plist any process can
/// read (CodeQL flags it, rightly), so the key lives in a generic-password
/// item instead - same protection class as the Claude Code token this app
/// already reads. Best-effort by design: a Keychain error degrades to "no key
/// stored", never a crash.
enum KeychainStore {
    private static let service = "io.github.fschmutz.claude-usage-panel"

    private static func query(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func read(_ account: String) -> String? {
        var q = query(account)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess,
            let data = out as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Writes (or deletes, when empty) the value. Delete-then-add keeps it a
    /// two-call upsert without racing SecItemUpdate's attribute rules.
    static func write(_ account: String, _ value: String) {
        SecItemDelete(query(account) as CFDictionary)
        guard !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var q = query(account)
        q[kSecValueData as String] = data
        SecItemAdd(q as CFDictionary, nil)
    }
}
