import Foundation
import Security

/// One time cleanup for builds that mirrored the token into a keychain item of their own.
///
/// Reading Claude Code's item no longer prompts, so the mirror is gone and the copy it left
/// behind goes with it. Delete this file once nobody upgrades from 1.0 any more.
enum LegacyTokenMirror {
    static let service = (Bundle.main.bundleIdentifier ?? "Headroom") + ".token"
    private static let account = "claude-oauth"

    /// Matches the retired item's full identity, not just its service, because `SecItemDelete`
    /// takes everything that matches and anything else under that service is not ours to drop.
    static func remove(service: String = service) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            // A build signed by a different cert cannot open the item, and asking would raise
            // the very dialog this release removes. Leaving it beats prompting for it.
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
