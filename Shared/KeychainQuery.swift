import Foundation
import LocalAuthentication
import Security

enum KeychainQuery {
    /// Makes a lookup fail with `errSecInteractionNotAllowed` instead of showing a dialog.
    ///
    /// The `LAContext` is the supported route, but it only covers biometric and passcode
    /// prompts. The "allow access" dialog on a file keychain ACL, which is the one this app
    /// hits, still needs the deprecated UI policy, so both go on the query. Swift has no way
    /// to silence the deprecation locally, hence the warning on the line below.
    static func denyInteraction(_ query: inout [String: Any]) {
        let context = LAContext()
        context.interactionNotAllowed = true
        query[kSecUseAuthenticationContext as String] = context
        query[kSecUseAuthenticationUI as String] = kSecUseAuthenticationUIFail
    }
}
