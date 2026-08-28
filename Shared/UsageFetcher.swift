import Foundation

enum UsageError: LocalizedError, Equatable {
    case keychainUnavailable
    case tokenExpired
    case http(Int)

    var errorDescription: String? {
        switch self {
        case .keychainUnavailable: return "No Claude Code login, run claude to sign in"
        case .tokenExpired: return "Token expired, open Claude Code to refresh"
        case .http(let code): return "Request failed (HTTP \(code))"
        }
    }
}

struct StoredToken: Sendable {
    var accessToken: String
    var expiresAt: Date?

    /// Retired a little early so a poll does not spend a request finding out it just died.
    var isUsable: Bool {
        guard let expiresAt else { return true }
        return expiresAt > Date().addingTimeInterval(Config.tokenExpiryMargin)
    }
}

enum UsageFetcher {
    /// Holds the token until it expires. Every read spawns a tool, and on a keychain that is
    /// locked that tool asks for a password, so a poll is the wrong place to do it.
    private actor TokenCache {
        private var cached: StoredToken?

        func token() throws -> String {
            if let cached, cached.isUsable { return cached.accessToken }
            let fresh = try UsageFetcher.requireUsable(UsageFetcher.readClaudeToken())
            cached = fresh
            return fresh.accessToken
        }

        func invalidate() { cached = nil }
    }

    private static let tokenCache = TokenCache()

    static func fetch(session: URLSession = .shared) async throws -> UsageSnapshot {
        let token = try await tokenCache.token()
        do {
            return try await request(token: token, session: session)
        } catch UsageError.tokenExpired {
            // Claude Code rotated the token underneath us. Drop ours and re-read once so the
            // rotation is invisible, and only fail if the fresh one is rejected too.
            await tokenCache.invalidate()
            return try await request(token: try await tokenCache.token(), session: session)
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

    /// Rejects a token that is already past its margin. Claude Code has not rotated yet, so
    /// keeping it would spend a request, then a second keychain read, to learn it is dead.
    static func requireUsable(_ token: StoredToken) throws -> StoredToken {
        guard token.isUsable else { throw UsageError.tokenExpired }
        return token
    }

    /// Reads through `/usr/bin/security`, not the Security framework, on purpose. Claude Code
    /// writes the item with that same tool, so it is the only app on the item's access list.
    /// Asking through it makes us a trusted caller; asking as Headroom puts a dialog on screen.
    static func readClaudeToken() throws -> StoredToken {
        // Claude Code files the item under the login name, so ask for that one first: a stale
        // item from an earlier name shares the service and would otherwise win. Older items
        // carry no account at all, which the second pass is there to find.
        guard let output = securityRead(account: NSUserName()) ?? securityRead(account: nil),
              let token = credential(from: output)
        else { throw UsageError.keychainUnavailable }
        return token
    }

    private static func securityRead(account: String?) -> Data? {
        let match = account.map { ["-a", $0] } ?? []
        return run("/usr/bin/security",
                   ["find-generic-password"] + match + ["-s", Config.keychainService, "-w"],
                   timeout: Config.keychainReadTimeout)
    }

    /// Runs a tool and hands back what it printed, or nil if it fails or outstays the deadline.
    ///
    /// The wait is on the process rather than on end of output, because a child that will not
    /// die can leave a grandchild holding the pipe open, and reading to the end would then wait
    /// for that grandchild too. A locked keychain makes `security` sit on an unlock dialog, so
    /// this is the difference between a poll that gives up and one that never returns.
    static func run(_ executable: String, _ arguments: [String], timeout: TimeInterval) -> Data? {
        let task = Process()
        task.executableURL = URL(fileURLWithPath: executable)
        task.arguments = arguments
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice

        let exited = DispatchSemaphore(value: 0)
        task.terminationHandler = { _ in exited.signal() }
        guard (try? task.run()) != nil else { return nil }

        guard exited.wait(timeout: .now() + timeout) == .success else {
            kill(task.processIdentifier, SIGKILL)
            return nil
        }
        guard task.terminationStatus == 0 else { return nil }
        return try? pipe.fileHandleForReading.readToEnd()
    }

    /// Split from the keychain read so the credential blob can be parsed without one. Trims
    /// because `security` prints a newline after the password.
    static func credential(from data: Data) -> StoredToken? {
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard let creds = try? JSONDecoder().decode(Credentials.self, from: Data(text.utf8)) else { return nil }
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
