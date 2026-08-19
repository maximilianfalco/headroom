import Foundation
import Testing

private struct LogFixture {
    let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appending(path: "headroom-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func destroy() {
        try? FileManager.default.removeItem(at: root)
    }

    func write(_ lines: [String], to name: String = "session.jsonl", subdirectory: String = "project") throws {
        let dir = root.appending(path: subdirectory)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: dir.appending(path: name),
                                                atomically: true, encoding: .utf8)
    }

    static func assistant(at timestamp: String, id: String = "msg-1", request: String = "req-1",
                          model: String = "claude-opus-5", speed: String = "standard",
                          input: Int = 0, output: Int = 0, read: Int = 0,
                          write5m: Int = 0, write1h: Int = 0, splitTTL: Bool = true) -> String {
        let creation = splitTTL
            ? #","cache_creation":{"ephemeral_5m_input_tokens":\#(write5m),"ephemeral_1h_input_tokens":\#(write1h)}"#
            : ""
        return """
        {"type":"assistant","timestamp":"\(timestamp)","requestId":"\(request)","message":\
        {"id":"\(id)","model":"\(model)","usage":{"input_tokens":\(input),"output_tokens":\(output),\
        "cache_read_input_tokens":\(read),"cache_creation_input_tokens":\(write5m + write1h),\
        "speed":"\(speed)"\(creation)}}}
        """
    }
}

private let now = Date(timeIntervalSince1970: 1_787_000_000)
private func iso(_ offsetFromNow: TimeInterval) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    f.timeZone = TimeZone(secondsFromGMT: 0)
    return f.string(from: now.addingTimeInterval(offsetFromNow))
}

/// Reset is an hour out, so the session window opened four hours ago.
private let sessionEndsAt = now.addingTimeInterval(3_600)

struct LocalUsageReaderTests {
    private func read(_ fixture: LogFixture, endsAt: Date? = sessionEndsAt) async -> LocalUsage? {
        await LocalUsageReader().usage(sessionEndsAt: endsAt, now: now, projectsRoot: fixture.root)
    }

    @Test("no log directory at all reports nothing rather than zeroes")
    func missingRootReportsNothing() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        #expect(await read(fixture) == nil)
    }

    @Test("an assistant turn contributes its tokens and cost")
    func countsAnAssistantTurn() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        try fixture.write([LogFixture.assistant(at: iso(-600), output: 1_000_000)])

        let usage = try #require(await read(fixture))
        #expect(usage.sessionNew == 1_000_000)
        #expect(isClose(usage.sessionCost, 25.0))
        #expect(usage.todayNew == 1_000_000)
    }

    @Test("cache reads are counted apart from new tokens")
    func cacheReadsAreSeparate() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        try fixture.write([LogFixture.assistant(at: iso(-600), output: 100, read: 5_000)])

        let usage = try #require(await read(fixture))
        #expect(usage.sessionNew == 100)
        #expect(usage.sessionCached == 5_000)
    }

    @Test("content entering the cache counts as new, not as cached")
    func cacheWritesCountAsNew() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        try fixture.write([LogFixture.assistant(at: iso(-600), write5m: 500, write1h: 2_000)])

        let usage = try #require(await read(fixture))
        #expect(usage.sessionNew == 2_500)
        #expect(usage.sessionCached == 0)
    }

    @Test("the hour cache TTL is priced above the five minute one")
    func ttlSplitIsHonoured() async throws {
        let hourFixture = try LogFixture(); defer { hourFixture.destroy() }
        try hourFixture.write([LogFixture.assistant(at: iso(-600), write1h: 1_000_000)])
        let minuteFixture = try LogFixture(); defer { minuteFixture.destroy() }
        try minuteFixture.write([LogFixture.assistant(at: iso(-600), write5m: 1_000_000)])

        #expect(isClose(try #require(await read(hourFixture)).sessionCost, 10.0))
        #expect(isClose(try #require(await read(minuteFixture)).sessionCost, 6.25))
    }

    @Test("a line with only a cache creation total bills at the five minute rate")
    func totalWithoutTTLSplitUsesTheCheaperRate() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        try fixture.write([LogFixture.assistant(at: iso(-600), write5m: 1_000_000, splitTTL: false)])

        let usage = try #require(await read(fixture))
        #expect(usage.sessionNew == 1_000_000)
        #expect(isClose(usage.sessionCost, 6.25))
    }

    @Test("fast mode is billed at the premium rate")
    func fastModeIsPriced() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        try fixture.write([LogFixture.assistant(at: iso(-600), speed: "fast", output: 1_000_000)])

        #expect(isClose(try #require(await read(fixture)).sessionCost, 50.0))
    }

    @Test("a model with no published rate still contributes tokens")
    func unpricedModelStillCountsTokens() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        try fixture.write([LogFixture.assistant(at: iso(-600), model: "<synthetic>", output: 900)])

        let usage = try #require(await read(fixture))
        #expect(usage.sessionNew == 900)
        #expect(usage.sessionCost == 0)
    }

    @Test("a replayed message is counted once, however many files hold it")
    func deduplicatesReplayedMessages() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        let line = LogFixture.assistant(at: iso(-600), id: "same", request: "same", output: 1_000)
        try fixture.write([line], to: "a.jsonl", subdirectory: "one")
        try fixture.write([line, line], to: "b.jsonl", subdirectory: "two")

        #expect(try #require(await read(fixture)).sessionNew == 1_000)
    }

    @Test("the same message id from a different request is a different turn")
    func sameMessageIdDifferentRequestIsNotADuplicate() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        try fixture.write([
            LogFixture.assistant(at: iso(-600), id: "same", request: "one", output: 1_000),
            LogFixture.assistant(at: iso(-600), id: "same", request: "two", output: 1_000),
        ])

        #expect(try #require(await read(fixture)).sessionNew == 2_000)
    }

    @Test(arguments: [
        #"{"type":"user","timestamp":"2026-08-19T00:00:00.000Z","message":{"usage":{"output_tokens":9}}}"#,
        #"{"type":"assistant","timestamp":"2026-08-19T00:00:00.000Z","message":{"id":"a"}}"#,
        #"{"type":"assistant","message":{"id":"a","usage":{"output_tokens":9}}}"#,
        #"{"type":"assistant","timestamp":"nonsense","message":{"id":"a","usage":{"output_tokens":9}}}"#,
        #"{"type":"assistant","timestamp":"2026-08-19T00:00:00.000Z"}"#,
        #"{"assistant":"this line only mentions the word"}"#,
        "{ broken json with assistant in it",
        "",
    ])
    func linesThatAreNotUsableTurnsAreSkipped(line: String) async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        try fixture.write([line, LogFixture.assistant(at: iso(-600), output: 7)])

        #expect(try #require(await read(fixture)).sessionNew == 7)
    }

    @Test("turns before the session opened still count towards today")
    func earlierTurnsCountTowardsTodayOnly() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        try fixture.write([
            LogFixture.assistant(at: iso(-600), id: "inside", output: 100),
            LogFixture.assistant(at: iso(-5 * 3_600), id: "before", request: "r2", output: 900),
        ])

        let usage = try #require(await read(fixture))
        #expect(usage.sessionNew == 100)
        #expect(usage.todayNew == 1_000)
    }

    @Test("a reset already in the past falls back to a rolling five hour window")
    func elapsedResetFallsBackToRollingWindow() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        try fixture.write([LogFixture.assistant(at: iso(-4 * 3_600 - 600), output: 500)])

        let stale = await read(fixture, endsAt: now.addingTimeInterval(-3_600))
        #expect(try #require(stale).sessionNew == 500)
    }

    @Test("with no reset at all the window is the last five hours")
    func missingResetUsesRollingWindow() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        try fixture.write([
            LogFixture.assistant(at: iso(-4 * 3_600 - 600), id: "in", output: 500),
            LogFixture.assistant(at: iso(-6 * 3_600), id: "out", request: "r2", output: 900),
        ])

        let usage = try #require(await read(fixture, endsAt: nil))
        #expect(usage.sessionNew == 500)
    }

    @Test("burn rate is new tokens per minute of the window so far")
    func burnRateUsesNewTokensOnly() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        try fixture.write([LogFixture.assistant(at: iso(-600), output: 2_400, read: 999_999)])

        let usage = try #require(await read(fixture))
        #expect(isClose(usage.newPerMinute, 10.0))
    }

    @Test("a window that only just opened does not divide by a fraction of a minute")
    func burnRateClampsTheElapsedWindow() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        try fixture.write([LogFixture.assistant(at: iso(-10), output: 300)])

        let justOpened = await read(fixture, endsAt: now.addingTimeInterval(Config.sessionWindow - 30))
        #expect(isClose(try #require(justOpened).newPerMinute, 300.0))
    }

    @Test("logs nested any depth below the root are found")
    func walksNestedDirectories() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        try fixture.write([LogFixture.assistant(at: iso(-600), output: 42)],
                          subdirectory: "a/b/c/d")

        #expect(try #require(await read(fixture)).sessionNew == 42)
    }

    @Test("files that are not session logs are ignored")
    func ignoresNonLogFiles() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        try fixture.write([LogFixture.assistant(at: iso(-600), output: 5)])
        try fixture.write([LogFixture.assistant(at: iso(-600), id: "x", request: "x", output: 5_000)],
                          to: "notes.json")

        #expect(try #require(await read(fixture)).sessionNew == 5)
    }

    @Test("the default root is Claude Code's own projects folder")
    func defaultRootPointsAtClaudeCode() {
        #expect(LocalUsageReader.defaultProjectsRoot.path.hasSuffix("/.claude/projects"))
    }

    @Test("reading twice with nothing changed gives the same answer")
    func reusesParsedEntriesWhenNothingChanged() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        let reader = LocalUsageReader()
        try fixture.write([LogFixture.assistant(at: iso(-600), output: 100)])

        let first = await reader.usage(sessionEndsAt: sessionEndsAt, now: now, projectsRoot: fixture.root)
        let second = await reader.usage(sessionEndsAt: sessionEndsAt, now: now, projectsRoot: fixture.root)
        #expect(first == second)
        #expect(try #require(second).sessionNew == 100)
    }

    @Test("appending to a log is picked up on the next read")
    func rereadsAFileThatChanged() async throws {
        let fixture = try LogFixture(); defer { fixture.destroy() }
        let reader = LocalUsageReader()
        try fixture.write([LogFixture.assistant(at: iso(-600), output: 100)])

        let first = await reader.usage(sessionEndsAt: sessionEndsAt, now: now, projectsRoot: fixture.root)
        #expect(try #require(first).sessionNew == 100)

        try fixture.write([
            LogFixture.assistant(at: iso(-600), output: 100),
            LogFixture.assistant(at: iso(-300), id: "m2", request: "r2", output: 50),
        ])
        let second = await reader.usage(sessionEndsAt: sessionEndsAt, now: now, projectsRoot: fixture.root)
        #expect(try #require(second).sessionNew == 150)
    }
}
