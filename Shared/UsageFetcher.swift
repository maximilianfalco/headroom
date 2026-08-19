import Foundation
import Security

enum UsageError: LocalizedError, Equatable {
    case needsReconnect
    case keychainUnavailable
    case tokenExpired
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .needsReconnect: return "Keychain access needed"
        case .keychainUnavailable: return "Cannot read Claude Code credentials"
        case .tokenExpired: return "Token expired, open Claude Code to refresh"
        case .http(let code): return "Request failed (HTTP \(code))"
        }
    }
}

enum UsageFetcher {
    /// Reading Claude Code's keychain item can prompt, so the token is sourced from our own
    /// item first and only re-read when it expires. `allowPrompt` is true for user-driven
    /// refreshes; the poll loop passes false and reports `.needsReconnect` instead of
    /// interrupting.
    private actor TokenCache {
        private var cached: StoredToken?

        func token(allowPrompt: Bool) throws -> String {
            if let cached, cached.isUsable { return cached.accessToken }
            if let stored = TokenStore.load(), stored.isUsable {
                cached = stored
                return stored.accessToken
            }
            let fresh = try UsageFetcher.readClaudeToken(allowPrompt: allowPrompt)
            cached = fresh
            TokenStore.save(fresh)
            return fresh.accessToken
        }

        func invalidate() {
            cached = nil
            TokenStore.clear()
        }
    }

    private static let tokenCache = TokenCache()

    static func fetch(allowPrompt: Bool = false,
                      session: URLSession = .shared) async throws -> UsageSnapshot {
        do {
            return try await request(token: tokenCache.token(allowPrompt: allowPrompt), session: session)
        } catch UsageError.tokenExpired {
            // Claude Code rotated the token underneath us. Re-source once so the rotation is
            // invisible, and only surface the failure if the second attempt is rejected too.
            await tokenCache.invalidate()
            return try await request(token: tokenCache.token(allowPrompt: allowPrompt), session: session)
        }
    }

    static func request(token: String, session: URLSession) async throws -> UsageSnapshot {
        var request = URLRequest(url: Config.usageEndpoint)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue(Config.oauthBetaHeader, forHTTPHeaderField: "anthropic-beta")
        request.timeoutInterval = Config.requestTimeout

        let (data, response) = try await session.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code != 401 else { throw UsageError.tokenExpired }
        guard code == 200 else { throw UsageError.http(code) }

        return UsageSnapshot(fetchedAt: .now, buckets: try decode(data))
    }

    // MARK: - Keychain

    fileprivate static func readClaudeToken(allowPrompt: Bool) throws -> StoredToken {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Config.keychainService,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if !allowPrompt { KeychainQuery.denyInteraction(&query) }

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status != errSecInteractionNotAllowed else { throw UsageError.needsReconnect }
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = credential(from: data)
        else { throw UsageError.keychainUnavailable }
        return token
    }

    /// Split from the keychain read so the credential blob can be parsed without one.
    static func credential(from data: Data) -> StoredToken? {
        guard let creds = try? JSONDecoder().decode(Credentials.self, from: data) else { return nil }
        return StoredToken(accessToken: creds.claudeAiOauth.accessToken,
                           expiresAt: creds.claudeAiOauth.expiresAt)
    }

    private struct Credentials: Decodable {
        struct OAuth: Decodable {
            let accessToken: String
            let expiresAt: Date?

            private enum CodingKeys: String, CodingKey { case accessToken, expiresAt }

            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                accessToken = try container.decode(String.self, forKey: .accessToken)
                // Never fatal: with no expiry we just fall back to letting a 401 retire the token.
                // Claude Code writes milliseconds, but reading a seconds value as milliseconds
                // would date every token to 1970 and re-read the keychain on every poll.
                let epoch = try? container.decode(Double.self, forKey: .expiresAt)
                expiresAt = epoch.flatMap {
                    $0 > 0 ? Date(timeIntervalSince1970: $0 > 10_000_000_000 ? $0 / 1000 : $0) : nil
                }
            }
        }
        let claudeAiOauth: OAuth
    }

    // MARK: - Response

    private struct Response: Decodable {
        struct Bucket: Decodable {
            let utilization: Double?
            let resetsAt: String?
        }
        struct Limit: Decodable {
            struct Scope: Decodable {
                struct Model: Decodable { let displayName: String? }
                let model: Model?
            }
            let kind: String?
            let percent: Int?
            let resetsAt: String?
            let scope: Scope?
        }
        let fiveHour: Bucket?
        let sevenDay: Bucket?
        let limits: [Limit]?
    }

    private static let isoParser: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static func date(_ raw: String?) -> Date? {
        guard let raw else { return nil }
        return isoParser.date(from: raw) ?? ISO8601DateFormatter().date(from: raw)
    }

    static func decode(_ data: Data) throws -> [UsageBucket] {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let response = try decoder.decode(Response.self, from: data)

        var buckets: [UsageBucket] = []
        if let b = response.fiveHour, let pct = b.utilization {
            buckets.append(UsageBucket(key: "five_hour", label: "Session",
                                       percent: Int(pct.rounded()), resetsAt: date(b.resetsAt)))
        }
        if let b = response.sevenDay, let pct = b.utilization {
            buckets.append(UsageBucket(key: "seven_day", label: "Weekly",
                                       percent: Int(pct.rounded()), resetsAt: date(b.resetsAt)))
        }
        // Per-model caps appear only in limits[], never as top level buckets.
        for limit in response.limits ?? [] where limit.kind == "weekly_scoped" {
            guard let name = limit.scope?.model?.displayName, let pct = limit.percent else { continue }
            buckets.append(UsageBucket(key: "weekly_\(name.lowercased())", label: name,
                                       percent: pct, resetsAt: date(limit.resetsAt)))
        }
        return buckets
    }
}
