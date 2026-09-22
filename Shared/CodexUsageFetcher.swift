import CryptoKit
import Darwin
import Foundation

enum CodexUsageError: LocalizedError, Equatable {
    case notInstalled
    case unavailable
    case signIn
    case timedOut
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notInstalled: return "Install Codex CLI to read your usage"
        case .unavailable: return "Could not read Codex usage. Open Codex and try again."
        case .signIn: return "Sign in to Codex with your ChatGPT account"
        case .timedOut: return "Codex usage took too long. Try again."
        case .invalidResponse: return "Codex returned unreadable usage. Try updating Codex CLI."
        }
    }
}

enum CodexUsageFetcher {
    static func fetch() async throws -> UsageSnapshot {
        try await Task.detached(priority: .utility) {
            guard let executable = executable() else { throw CodexUsageError.notInstalled }
            return try read(executable: executable)
        }.value
    }

    static func executable(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL? {
        let directories = (environment["PATH"] ?? "").split(separator: ":").map(String.init)
            + ["/opt/homebrew/bin", "/usr/local/bin", "/Applications/Codex.app/Contents/Resources"]
        return directories.lazy.map { URL(fileURLWithPath: $0).appending(path: "codex") }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }

    static func read(executable: URL, timeout: TimeInterval = Config.requestTimeout) throws -> UsageSnapshot {
        let server = CodexUsageConnection(executable: executable, timeout: timeout)
        defer { server.close() }
        try server.start()
        try server.send([
            "id": 1, "method": "initialize",
            "params": ["clientInfo": ["name": "headroom", "title": "Headroom", "version": "1.0"]],
        ])
        _ = try server.result(id: 1)
        try server.send(["method": "initialized", "params": [:]])
        try server.send([
            "id": 2, "method": "account/rateLimits/read",
            "params": ["excludeResetCreditDetails": true],
        ])
        return try decode(server.result(id: 2))
    }

    private struct Response: Decodable {
        struct Window: Decodable {
            let usedPercent: Double
            let windowDurationMins: Double?
            let resetsAt: Double?
        }

        struct Limit: Decodable {
            let limitId: String?
            let limitName: String?
            let normalModelSlug: String?
            let primary: Window?
            let secondary: Window?
        }

        let accountId: String?
        let rateLimits: Limit?
        let rateLimitsByLimitId: [String: Limit]?
    }

    static func decode(_ data: Data, now: Date = .now) throws -> UsageSnapshot {
        let response: Response
        do { response = try JSONDecoder().decode(Response.self, from: data) }
        catch { throw CodexUsageError.invalidResponse }
        let limits: [String: Response.Limit]
        if let all = response.rateLimitsByLimitId, !all.isEmpty {
            limits = all
        } else if let limit = response.rateLimits {
            limits = [limit.limitId ?? "codex": limit]
        } else {
            throw CodexUsageError.invalidResponse
        }
        let account = response.accountId.map {
            SHA256.hash(data: Data($0.utf8)).map { String(format: "%02x", $0) }.joined()
        } ?? "unknown"
        let ids = limits.keys.sorted { lhs, rhs in
            if lhs == "codex" { return rhs != "codex" }
            if rhs == "codex" { return false }
            return lhs < rhs
        }
        var buckets: [UsageBucket] = []
        for id in ids {
            guard let limit = limits[id] else { continue }
            let name = id == "codex" ? "Codex" : "Codex \(modelLabel(limit.normalModelSlug ?? limit.limitName ?? id))"
            for (kind, window) in [("primary", limit.primary), ("secondary", limit.secondary)] {
                guard let window else { continue }
                guard window.usedPercent.isFinite, window.usedPercent >= 0,
                      window.usedPercent < Double(Int.max) else { throw CodexUsageError.invalidResponse }
                let minutes = window.windowDurationMins.flatMap {
                    $0 > 0 && $0 < Double(Int.max) / 60 ? $0 : nil
                }
                let reset = window.resetsAt.flatMap {
                    $0 > 0 && $0 < Double(Int.max) ? Date(timeIntervalSince1970: $0) : nil
                }
                buckets.append(UsageBucket(
                    key: "codex:\(account):\(id):\(kind)",
                    label: "\(name) \(windowLabel(minutes: minutes, kind: kind))",
                    percent: Int(window.usedPercent.rounded()), resetsAt: reset,
                    windowDuration: minutes.map { $0 * 60 }, provider: .codex
                ))
            }
        }
        return UsageSnapshot(fetchedAt: now, buckets: buckets, provider: .codex)
    }

    private static func modelLabel(_ name: String) -> String {
        switch name {
        case "gpt-6-astra": return "Astra"
        case "gpt-5.6-sol": return "Sol"
        case "gpt-5.6-terra": return "Terra"
        case "gpt-5.6-luna": return "Luna"
        default: return name
        }
    }

    private static func windowLabel(minutes: Double?, kind: String) -> String {
        switch minutes {
        case 300: return "Session"
        case 10_080: return "Weekly"
        case 1_440: return "Daily"
        case let value? where value < Double(Int.max) && value.truncatingRemainder(dividingBy: 60) == 0:
            return "\(Int(value / 60))-hour"
        case let value? where value < Double(Int.max): return "\(Int(value))-minute"
        default: return kind.capitalized
        }
    }
}

private final class CodexUsageConnection {
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let deadline: TimeInterval
    private var pending = Data()

    init(executable: URL, timeout: TimeInterval) {
        process.executableURL = executable
        process.arguments = ["app-server", "--listen", "stdio://"]
        process.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
        process.standardInput = input
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        deadline = ProcessInfo.processInfo.systemUptime + timeout
    }

    func start() throws {
        _ = fcntl(input.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
        do { try process.run() }
        catch { throw CodexUsageError.unavailable }
    }

    func send(_ message: [String: Any]) throws {
        var data = try JSONSerialization.data(withJSONObject: message)
        data.append(0x0a)
        try input.fileHandleForWriting.write(contentsOf: data)
    }

    func result(id: Int) throws -> Data {
        while ProcessInfo.processInfo.systemUptime < deadline {
            if let newline = pending.firstIndex(of: 0x0a) {
                let line = Data(pending[..<newline])
                pending.removeSubrange(...newline)
                guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                      object["id"] as? Int == id else { continue }
                if let error = object["error"] as? [String: Any] {
                    let message = (error["message"] as? String ?? "").lowercased()
                    throw message.contains("authentication required") ? CodexUsageError.signIn : .unavailable
                }
                guard let result = object["result"] as? [String: Any] else {
                    throw CodexUsageError.invalidResponse
                }
                return try JSONSerialization.data(withJSONObject: result)
            }
            var descriptor = pollfd(fd: output.fileHandleForReading.fileDescriptor, events: Int16(POLLIN), revents: 0)
            let ready = poll(&descriptor, 1, 100)
            if ready < 0 {
                if errno == EINTR { continue }
                throw CodexUsageError.unavailable
            }
            guard ready > 0 else { continue }
            var bytes = [UInt8](repeating: 0, count: 16_384)
            let count = Darwin.read(descriptor.fd, &bytes, bytes.count)
            guard count > 0 else { throw CodexUsageError.unavailable }
            pending.append(contentsOf: bytes.prefix(count))
            guard pending.count <= 1_048_576 else { throw CodexUsageError.invalidResponse }
        }
        throw CodexUsageError.timedOut
    }

    func close() {
        try? input.fileHandleForWriting.close()
        if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        try? output.fileHandleForReading.close()
    }
}
