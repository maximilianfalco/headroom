import Foundation
import Testing

private let codexNow = Date(timeIntervalSince1970: 1_800_000_000)

private func codexData(_ body: String) -> Data { Data(body.utf8) }

struct CodexUsageTests {
    @Test("a weekly primary window does not invent a session or model limit")
    func weeklyOnly() throws {
        let snapshot = try CodexUsageFetcher.decode(codexData(#"""
        {"accountId":"example-account","rateLimitsByLimitId":{"codex":{
          "primary":{"usedPercent":23,"windowDurationMins":10080,"resetsAt":1800432000},
          "secondary":null
        }}}
        """#), now: codexNow)

        #expect(snapshot.source == .codex)
        #expect(snapshot.fetchedAt == codexNow)
        #expect(snapshot.buckets.count == 1)
        #expect(snapshot.buckets[0].label == "Codex Weekly")
        #expect(snapshot.buckets[0].percent == 23)
        #expect(snapshot.buckets[0].windowDuration == TimeInterval(7 * 86_400))
        #expect(snapshot.buckets[0].resetsAt == codexNow.addingTimeInterval(5 * 86_400))
        #expect(snapshot.buckets[0].key.contains("example-account") == false)
        #expect(snapshot.local == nil)
    }

    @Test("the complete map wins over its duplicate legacy view")
    func namedModelLimits() throws {
        let snapshot = try CodexUsageFetcher.decode(codexData(#"""
        {
          "rateLimits":{"primary":{"usedPercent":99,"windowDurationMins":300}},
          "rateLimitsByLimitId":{
            "astra-limit":{"normalModelSlug":"gpt-6-astra",
              "primary":{"usedPercent":31,"windowDurationMins":10080}},
            "codex":{"primary":{"usedPercent":12,"windowDurationMins":300},
              "secondary":{"usedPercent":18,"windowDurationMins":10080}}
          }
        }
        """#))

        #expect(snapshot.buckets.map(\.label) == ["Codex Session", "Codex Weekly", "Codex Astra Weekly"])
        #expect(snapshot.buckets.map(\.percent) == [12, 18, 31])
        #expect(Set(snapshot.buckets.map(\.key)).count == 3)
    }

    @Test("an older response can use the single-limit view")
    func legacyResponse() throws {
        let snapshot = try CodexUsageFetcher.decode(codexData(#"""
        {"rateLimits":{"primary":{"usedPercent":12.6,"windowDurationMins":60,"resetsAt":null}}}
        """#))
        #expect(snapshot.buckets.first?.label == "Codex 1-hour")
        #expect(snapshot.buckets.first?.percent == 13)
        #expect(snapshot.buckets.first?.resetsAt == nil)
    }

    @Test("a missing duration stays unknown rather than becoming weekly")
    func unknownDuration() throws {
        let snapshot = try CodexUsageFetcher.decode(codexData(#"""
        {"rateLimits":{"secondary":{"usedPercent":20,"resetsAt":1800003600}}}
        """#), now: codexNow)
        let bucket = try #require(snapshot.buckets.first)
        #expect(bucket.label == "Codex Secondary")
        #expect(bucket.windowDuration == nil)
        #expect(Projection.project(bucket, samples: [], cost: nil, now: codexNow) == nil)
    }

    @Test("missing windows do not mean zero-percent windows")
    func absentWindows() throws {
        let snapshot = try CodexUsageFetcher.decode(codexData(#"{"rateLimits":{"primary":null,"secondary":null}}"#))
        #expect(snapshot.buckets.isEmpty)
    }

    @Test("out-of-range times cannot overflow the countdown or saved snapshot")
    func invalidTimes() throws {
        let snapshot = try CodexUsageFetcher.decode(codexData(#"""
        {"rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":1e100,"resetsAt":1e100}}}
        """#))
        let bucket = try #require(snapshot.buckets.first)
        #expect(bucket.percent == 20)
        #expect(bucket.windowDuration == nil)
        #expect(bucket.resetsIn == nil)
        #expect(throws: Never.self) { try JSONEncoder().encode(snapshot) }
    }

    @Test("account switches cannot reuse limit history or notification identity")
    func accountIdentity() throws {
        func snapshot(_ account: String) throws -> UsageSnapshot {
            try CodexUsageFetcher.decode(codexData("""
            {"accountId":"\(account)","rateLimits":{"primary":{"usedPercent":20,"windowDurationMins":300}}}
            """))
        }
        let first = try snapshot("example-one")
        let second = try snapshot("example-two")
        #expect(first.buckets[0].key != second.buckets[0].key)
        #expect(try first.buckets[0].key == snapshot("example-one").buckets[0].key)
    }

    @Test(arguments: [
        "{}", "not json",
        #"{"rateLimits":{"primary":{"usedPercent":-1}}}"#,
        #"{"rateLimits":{"primary":{"usedPercent":1e100}}}"#,
        #"{"rateLimits":{"primary":{"usedPercent":"unknown"}}}"#,
    ])
    func invalidResponses(body: String) {
        #expect(throws: CodexUsageError.invalidResponse) {
            try CodexUsageFetcher.decode(codexData(body))
        }
    }

    @Test("Codex projections use the returned duration")
    func dailyProjection() {
        let bucket = UsageBucket(key: "codex:example:daily:primary", label: "Codex Daily", percent: 10,
                                 resetsAt: codexNow.addingTimeInterval(18 * 3600),
                                 windowDuration: 24 * 3600, provider: .codex)
        #expect(Projection.project(bucket, samples: [], cost: nil, now: codexNow) == 40)
    }

    @Test("Codex session projections use only that limit's percentage history")
    func sessionProjectionIgnoresClaudeSpend() {
        let reset = codexNow.addingTimeInterval(3600)
        let bucket = UsageBucket(key: "codex:example:codex:primary", label: "Codex Session", percent: 20,
                                 resetsAt: reset, windowDuration: 5 * 3600, provider: .codex)
        let samples = [
            UsageSample(key: bucket.key, at: codexNow.addingTimeInterval(-1800), percent: 10, resetsAt: reset),
            UsageSample(key: "five_hour", at: codexNow.addingTimeInterval(-1800), percent: 0,
                        resetsAt: reset, cost: 0),
            UsageSample(key: "five_hour", at: codexNow, percent: 10, resetsAt: reset, cost: 10),
        ]
        #expect(Projection.project(bucket, samples: samples, cost: 1_000, now: codexNow) == 40)
    }

    @Test("Codex weekly projections wait for the same share of the window as Claude")
    func weeklyWarmup() {
        func bucket(elapsed: TimeInterval) -> UsageBucket {
            UsageBucket(key: "codex:example:codex:primary", label: "Codex Weekly", percent: 10,
                        resetsAt: codexNow + Config.weeklyWindow - elapsed,
                        windowDuration: Config.weeklyWindow, provider: .codex)
        }
        let warmup = Config.weeklyWindow * Config.projectionWarmup
        #expect(Projection.project(bucket(elapsed: warmup - 1), samples: [], cost: nil, now: codexNow) == nil)
        #expect(Projection.project(bucket(elapsed: warmup), samples: [], cost: nil, now: codexNow) == 100)
    }
}

struct ProviderStorageTests {
    @Test("switching providers preserves each snapshot and publishes the selected one")
    func separateSnapshots() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let claude = UsageSnapshot(fetchedAt: codexNow, buckets: [
            UsageBucket(key: "five_hour", label: "Session", percent: 32),
        ])
        let codex = UsageSnapshot(fetchedAt: codexNow, buckets: [
            UsageBucket(key: "codex:example:codex:primary", label: "Codex Weekly", percent: 17),
        ], provider: .codex)
        try UsageStore.save(claude, to: directory)
        try UsageStore.save(codex, to: directory)

        #expect(UsageStore.load(from: directory) == codex)
        #expect(UsageStore.load(provider: .claude, from: directory) == claude)
        #expect(UsageStore.load(provider: .codex, from: directory) == codex)
    }

    @Test("projection samples stay separate for each provider")
    func separateSamples() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let claude = [UsageSample(key: "five_hour", at: codexNow, percent: 32)]
        let codex = [UsageSample(key: "codex:example:codex:primary", at: codexNow, percent: 17)]
        try UsageStore.saveSamples(claude, to: directory)
        try UsageStore.saveSamples(codex, provider: .codex, to: directory)

        #expect(UsageStore.loadSamples(from: directory) == claude)
        #expect(UsageStore.loadSamples(provider: .codex, from: directory) == codex)
    }

    @Test("an existing untagged snapshot remains a Claude snapshot")
    func legacySnapshot() throws {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        try codexData(#"{"fetchedAt":"2026-08-19T00:00:00Z","buckets":[]}"#)
            .write(to: directory.appending(path: "usage.json"))

        #expect(UsageStore.load(provider: .claude, from: directory)?.source == .claude)
        #expect(UsageStore.load(provider: .codex, from: directory) == nil)
    }
}

private struct FakeCodex {
    let directory: URL
    var executable: URL { directory.appending(path: "codex") }

    init(_ script: String) throws {
        directory = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try ("#!/bin/sh\n" + script).write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: executable.path)
    }

    func remove() { try? FileManager.default.removeItem(at: directory) }
}

struct CodexConnectionTests {
    @Test("the client completes the handshake and ignores unrelated notifications")
    func handshake() throws {
        let fake = try FakeCodex(#"""
        IFS= read -r request
        case "$request" in *'"initialize"'*) ;; *) exit 1;; esac
        echo '{"method":"notification","params":{}}'
        echo '{"id":1,"result":{}}'
        IFS= read -r request
        case "$request" in *'"initialized"'*) ;; *) exit 1;; esac
        IFS= read -r request
        case "$request" in *'"account'*'rateLimits'*'read"'*) ;; *) exit 1;; esac
        case "$request" in *'"excludeResetCreditDetails":true'*) ;; *) exit 1;; esac
        echo '{"id":2,"result":{"rateLimits":{"primary":{"usedPercent":27,"windowDurationMins":10080}}}}'
        """#)
        defer { fake.remove() }
        let snapshot = try CodexUsageFetcher.read(executable: fake.executable, timeout: 2)
        #expect(snapshot.buckets.first?.label == "Codex Weekly")
        #expect(snapshot.buckets.first?.percent == 27)
    }

    @Test("authentication errors ask for a ChatGPT login without exposing the response")
    func authenticationFailure() throws {
        let fake = try FakeCodex(#"""
        IFS= read -r request
        echo '{"id":1,"error":{"code":-32600,"message":"chatgpt authentication required to read rate limits"}}'
        """#)
        defer { fake.remove() }
        #expect(throws: CodexUsageError.signIn) {
            try CodexUsageFetcher.read(executable: fake.executable, timeout: 2)
        }
    }

    @Test("a stalled child cannot hang a refresh")
    func timeout() throws {
        let fake = try FakeCodex("exec /bin/sleep 5\n")
        defer { fake.remove() }
        #expect(throws: CodexUsageError.timedOut) {
            try CodexUsageFetcher.read(executable: fake.executable, timeout: 0.1)
        }
    }

    @Test("a child that exits early reports an error")
    func earlyExit() throws {
        let fake = try FakeCodex("exit 1\n")
        defer { fake.remove() }
        #expect(throws: (any Error).self) {
            try CodexUsageFetcher.read(executable: fake.executable, timeout: 2)
        }
    }
}
