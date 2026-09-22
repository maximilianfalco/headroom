import Foundation
import Testing

private let localNow = Date(timeIntervalSince1970: 1_800_000_000)

private struct CodexLogFixture {
    let root: URL

    init() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func remove() { try? FileManager.default.removeItem(at: root) }

    func write(_ lines: [String], name: String = "session.jsonl", archived: Bool = false) throws {
        let directory = root.appending(path: archived ? "archived_sessions" : "sessions/2026/09/22")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try lines.joined(separator: "\n").write(to: directory.appending(path: name),
                                                atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.modificationDate: localNow + 86_400],
                                              ofItemAtPath: directory.appending(path: name).path)
    }

    static func meta(thread: String = "example-thread") -> String {
        #"{"type":"session_meta","payload":{"id":"\#(thread)"}}"#
    }

    static func context(turn: String = "example-turn", model: String = "gpt-6-astra") -> String {
        #"{"type":"turn_context","payload":{"turn_id":"\#(turn)","model":"\#(model)"}}"#
    }

    static func usage(at: Date = localNow - 60, response: String = "example-response",
                      thread: String = "example-thread", turn: String = "example-turn",
                      input: Int = 1_000, cached: Int = 800, write: Int = 0,
                      output: Int = 100, reasoning: Int = 50) -> String {
        let timestamp = ISO8601DateFormatter().string(from: at)
        return """
        {"type":"token_usage_record","timestamp":"\(timestamp)","payload":{
        "thread_id":"\(thread)","turn_id":"\(turn)","response_id":"\(response)",
        "usage":{"input_tokens":\(input),"cached_input_tokens":\(cached),
        "cache_write_input_tokens":\(write),"output_tokens":\(output),"reasoning_output_tokens":\(reasoning)},
        "turn_token_usage":{"input_tokens":999999},"thread_token_usage":{"input_tokens":999999}}}
        """.replacingOccurrences(of: "\n", with: "")
    }

    func read(reset: Date? = nil, now: Date = localNow) async -> LocalUsage? {
        await CodexLocalUsageReader().usage(sessionEndsAt: reset, now: now, root: root)
    }
}

struct CodexLocalUsageTests {
    @Test("new tokens exclude cache reads and count reasoning only once")
    func tokenSplit() async throws {
        let fixture = try CodexLogFixture(); defer { fixture.remove() }
        try fixture.write([CodexLogFixture.meta(), CodexLogFixture.context(), CodexLogFixture.usage()])
        let usage = try #require(await fixture.read())
        #expect(usage.sessionNew == 300)
        #expect(usage.sessionCached == 800)
        #expect(isClose(usage.sessionCost, 0.0078))
        #expect(usage.sessionLabel == "Last 5h")
        #expect(isClose(usage.newPerMinute, 1))
    }

    @Test("a real five-hour window determines the session and burn rate")
    func alignedSession() async throws {
        let fixture = try CodexLogFixture(); defer { fixture.remove() }
        try fixture.write([CodexLogFixture.meta(), CodexLogFixture.context(),
                           CodexLogFixture.usage(at: localNow - 3_600, response: "before"),
                           CodexLogFixture.usage()])
        let usage = try #require(await fixture.read(reset: localNow + Config.sessionWindow - 1_800))
        #expect(usage.sessionNew == 300)
        #expect(usage.sessionLabel == "Session")
        #expect(isClose(usage.newPerMinute, 10))
    }

    @Test("the local window can cross midnight without losing yesterday's tokens")
    func midnight() async throws {
        let fixture = try CodexLogFixture(); defer { fixture.remove() }
        let dayStart = Calendar.current.startOfDay(for: localNow)
        try fixture.write([CodexLogFixture.meta(), CodexLogFixture.context(),
                           CodexLogFixture.usage(at: dayStart - 900, response: "yesterday"),
                           CodexLogFixture.usage(at: dayStart + 600, response: "today")])
        let usage = try #require(await fixture.read(now: dayStart + 3_600))
        #expect(usage.todayNew == 300)
        #expect(usage.sessionNew == 600)
    }

    @Test("today includes work before the local window and excludes future records")
    func todayAndFuture() async throws {
        let fixture = try CodexLogFixture(); defer { fixture.remove() }
        let now = Calendar.current.startOfDay(for: localNow) + 12 * 3_600
        try fixture.write([CodexLogFixture.meta(), CodexLogFixture.context(),
                           CodexLogFixture.usage(at: now - 6 * 3_600, response: "morning"),
                           CodexLogFixture.usage(at: now - 60, response: "current"),
                           CodexLogFixture.usage(at: now + 60, response: "future")])
        let usage = try #require(await fixture.read(now: now))
        #expect(usage.todayNew == 600)
        #expect(usage.sessionNew == 300)
    }

    @Test("replayed responses are counted once across active and archived logs")
    func repeatedRecords() async throws {
        let fixture = try CodexLogFixture(); defer { fixture.remove() }
        let lines = [CodexLogFixture.meta(), CodexLogFixture.context(), CodexLogFixture.usage()]
        try fixture.write(lines + [CodexLogFixture.usage()])
        try fixture.write(lines, archived: true)
        #expect(try #require(await fixture.read()).sessionNew == 300)
    }

    @Test("a fork's fresh timestamp does not turn inherited history into new work")
    func forkedHistory() async throws {
        let fixture = try CodexLogFixture(); defer { fixture.remove() }
        try fixture.write([CodexLogFixture.meta(thread: "child"), CodexLogFixture.context(),
                           CodexLogFixture.usage(thread: "parent"),
                           CodexLogFixture.usage(response: "child-work", thread: "child")])
        #expect(try #require(await fixture.read()).sessionNew == 300)
    }

    @Test("subagents keep their own model prices")
    func modelPerTurn() async throws {
        let fixture = try CodexLogFixture(); defer { fixture.remove() }
        try fixture.write([CodexLogFixture.meta(), CodexLogFixture.context(), CodexLogFixture.usage(),
                           CodexLogFixture.context(turn: "second", model: "gpt-5.6-sol"),
                           CodexLogFixture.usage(response: "second-response", turn: "second")])
        let usage = try #require(await fixture.read())
        #expect(isClose(usage.sessionCost, 0.0078 + 0.00312))
    }

    @Test("a model without prices keeps its tokens and marks the dollar total unavailable")
    func unknownModel() async throws {
        let fixture = try CodexLogFixture(); defer { fixture.remove() }
        try fixture.write([CodexLogFixture.meta(), CodexLogFixture.context(model: "synthetic-model"),
                           CodexLogFixture.usage()])
        let usage = try #require(await fixture.read())
        #expect(usage.sessionNew == 300)
        #expect(usage.sessionCostComplete == false)
    }

    @Test("cached reads pick up appended records on the next poll")
    func changedFile() async throws {
        let fixture = try CodexLogFixture(); defer { fixture.remove() }
        let reader = CodexLocalUsageReader()
        let lines = [CodexLogFixture.meta(), CodexLogFixture.context(), CodexLogFixture.usage()]
        try fixture.write(lines)
        let first = await reader.usage(sessionEndsAt: nil, now: localNow, root: fixture.root)
        let same = await reader.usage(sessionEndsAt: nil, now: localNow, root: fixture.root)
        #expect(first == same)
        try fixture.write(lines + [CodexLogFixture.usage(response: "new-response")])
        let changed = try #require(await reader.usage(sessionEndsAt: nil, now: localNow, root: fixture.root))
        #expect(changed.sessionNew == 600)
    }

    @Test("legacy snapshots are not added on top of response records")
    func ignoresLegacyTotals() async throws {
        let fixture = try CodexLogFixture(); defer { fixture.remove() }
        try fixture.write([CodexLogFixture.meta(), CodexLogFixture.context(), CodexLogFixture.usage(),
                           #"{"type":"event_msg","payload":{"type":"token_count","info":{"last_token_usage":{"input_tokens":999999}}}}"#])
        #expect(try #require(await fixture.read()).sessionNew == 300)
    }

    @Test("malformed and partial records do not hide valid usage")
    func invalidRecords() async throws {
        let fixture = try CodexLogFixture(); defer { fixture.remove() }
        try fixture.write([CodexLogFixture.meta(), CodexLogFixture.context(), "{token_usage_record",
                           CodexLogFixture.usage(input: -1), CodexLogFixture.usage(cached: 1_001),
                           CodexLogFixture.usage(write: 900), CodexLogFixture.usage()])
        #expect(try #require(await fixture.read()).sessionNew == 300)
    }

    @Test("missing logs are unavailable rather than zero usage")
    func noLogs() async throws {
        let fixture = try CodexLogFixture(); defer { fixture.remove() }
        #expect(await fixture.read() == nil)
    }
}

struct CodexModelPricingTests {
    @Test("cache writes have their own price and are not also billed as plain input")
    func cacheWritePrice() {
        let cost = CodexModelPricing.cost(model: "gpt-6-astra", input: 1_000, cached: 500,
                                         cacheWrite: 300, output: 100)
        #expect(isClose(cost ?? -1, 0.01125))
    }

    @Test("the long-context rate starts above 272000 input tokens")
    func longContextBoundary() {
        let short = CodexModelPricing.cost(model: "gpt-6-astra", input: 272_000, cached: 0,
                                          cacheWrite: 0, output: 100)
        let long = CodexModelPricing.cost(model: "gpt-6-astra", input: 272_001, cached: 0,
                                         cacheWrite: 0, output: 100)
        #expect(isClose(short ?? -1, 2.725))
        #expect(isClose(long ?? -1, 5.44752))
    }

    @Test("dated models match their price but unknown variants do not")
    func modelNames() {
        #expect(isClose(CodexModelPricing.cost(model: "gpt-5.5-2026-04-23", input: 0, cached: 0,
                                              cacheWrite: 0, output: 1_000) ?? -1, 0.03))
        #expect(CodexModelPricing.cost(model: "gpt-5.5-unknown", input: 0, cached: 0,
                                      cacheWrite: 0, output: 1_000) == nil)
    }
}
