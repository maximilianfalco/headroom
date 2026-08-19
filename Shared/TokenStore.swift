import Foundation
import Security

struct StoredToken: Codable, Sendable {
    var accessToken: String
    var expiresAt: Date?

    /// Retired a little early so a poll does not spend a request finding out it just died.
    var isUsable: Bool {
        guard let expiresAt else { return true }
        return expiresAt > Date().addingTimeInterval(Config.tokenExpiryMargin)
    }
}

/// Headroom's own keychain item, holding a copy of the Claude Code token.
///
/// Claude Code rewrites the access list on its item every time it refreshes, so every read of
/// that item is another chance to be prompted. An item we created trusts only us, so reading
/// it never prompts. This copy is a cache: losing it costs one prompted read, nothing more.
enum TokenStore {
    private static var service: String { (Bundle.main.bundleIdentifier ?? "Headroom") + ".token" }
    private static let account = "claude-oauth"

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    static func load() -> StoredToken? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        KeychainQuery.denyInteraction(&query)

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(StoredToken.self, from: data)
    }

    static func save(_ token: StoredToken) {
        guard let data = try? JSONEncoder().encode(token) else { return }
        var query = baseQuery
        KeychainQuery.denyInteraction(&query)
        let update = [kSecValueData as String: data] as CFDictionary
        guard SecItemUpdate(query as CFDictionary, update) != errSecSuccess else { return }

        // Covers both "no item yet" and an item left by an older signing cert, which we can
        // no longer open and so cannot update either.
        SecItemDelete(query as CFDictionary)
        var add = baseQuery
        add[kSecValueData as String] = data
        _ = SecItemAdd(add as CFDictionary, nil)
    }

    static func clear() {
        var query = baseQuery
        KeychainQuery.denyInteraction(&query)
        SecItemDelete(query as CFDictionary)
    }
}
