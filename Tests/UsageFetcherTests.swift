import Foundation
import Testing

struct CredentialParsingTests {
    private func credential(_ json: String) -> StoredToken? {
        UsageFetcher.credential(from: Data(json.utf8))
    }

    @Test("a well formed credential yields the access token")
    func readsAccessToken() {
        let token = credential(#"{"claudeAiOauth":{"accessToken":"abc123","expiresAt":1787000000000}}"#)
        #expect(token?.accessToken == "abc123")
    }

    @Test("the newline security prints after the password does not break the parse")
    func trailingNewlineIsTolerated() {
        let token = credential("{\"claudeAiOauth\":{\"accessToken\":\"abc123\"}}\n")
        #expect(token?.accessToken == "abc123")
    }

    @Test("milliseconds since the epoch are read as milliseconds")
    func expiryInMilliseconds() {
        let token = credential(#"{"claudeAiOauth":{"accessToken":"a","expiresAt":1787000000000}}"#)
        #expect(token?.expiresAt == Date(timeIntervalSince1970: 1_787_000_000))
    }

    @Test("a seconds value is not mistaken for milliseconds, which would date it to 1970")
    func expiryInSeconds() {
        let token = credential(#"{"claudeAiOauth":{"accessToken":"a","expiresAt":1787000000}}"#)
        #expect(token?.expiresAt == Date(timeIntervalSince1970: 1_787_000_000))
    }

    @Test(arguments: [
        #"{"claudeAiOauth":{"accessToken":"a"}}"#,
        #"{"claudeAiOauth":{"accessToken":"a","expiresAt":null}}"#,
        #"{"claudeAiOauth":{"accessToken":"a","expiresAt":0}}"#,
        #"{"claudeAiOauth":{"accessToken":"a","expiresAt":"not-a-number"}}"#,
    ])
    func unusableExpiryLeavesTheTokenWithoutOne(json: String) {
        let token = credential(json)
        #expect(token?.accessToken == "a")
        #expect(token?.expiresAt == nil)
    }

    @Test(arguments: [
        #"{"mcpOAuth":{"server":"x"}}"#,
        #"{"claudeAiOauth":null}"#,
        #"{"claudeAiOauth":{}}"#,
        "not json at all",
        "",
    ])
    func unusableBlobsYieldNothing(json: String) {
        #expect(credential(json) == nil)
    }
}

struct UsageResponseDecodingTests {
    private func buckets(_ json: String) throws -> [UsageBucket] {
        try UsageFetcher.decode(Data(json.utf8))
    }

    @Test("the two top level windows become buckets")
    func topLevelWindows() throws {
        let result = try buckets("""
        {"five_hour":{"utilization":8.0,"resets_at":"2026-08-19T03:20:00.000Z"},
         "seven_day":{"utilization":4.0,"resets_at":"2026-08-25T14:00:00Z"}}
        """)
        #expect(result.map(\.key) == ["five_hour", "seven_day"])
        #expect(result.map(\.label) == ["Session", "Weekly"])
    }

    @Test(arguments: [(76.4, 76), (76.5, 77), (99.6, 100), (0.4, 0)])
    func utilizationRounds(utilization: Double, expected: Int) throws {
        let result = try buckets(#"{"five_hour":{"utilization":\#(utilization)}}"#)
        #expect(result.first?.percent == expected)
    }

    @Test(arguments: [
        #"{"five_hour":{"resets_at":"2026-08-19T03:20:00Z"}}"#,
        #"{"five_hour":{"utilization":null}}"#,
        "{}",
    ])
    func windowsWithoutUtilizationAreSkipped(json: String) throws {
        #expect(try buckets(json).isEmpty)
    }

    @Test("per model caps come only from the limits array")
    func weeklyScopedLimits() throws {
        let result = try buckets("""
        {"limits":[{"kind":"weekly_scoped","percent":4,"resets_at":"2026-08-25T14:00:00Z",
                    "scope":{"model":{"display_name":"Fable"}}}]}
        """)
        #expect(result.count == 1)
        #expect(result[0].key == "weekly_fable")
        #expect(result[0].label == "Fable")
        #expect(result[0].percent == 4)
    }

    @Test(arguments: [
        #"{"limits":[{"kind":"session","percent":9,"scope":{"model":{"display_name":"Fable"}}}]}"#,
        #"{"limits":[{"kind":"weekly_all","percent":9,"scope":{"model":{"display_name":"Fable"}}}]}"#,
        #"{"limits":[{"kind":"weekly_scoped","percent":9}]}"#,
        #"{"limits":[{"kind":"weekly_scoped","percent":9,"scope":{"model":{}}}]}"#,
        #"{"limits":[{"kind":"weekly_scoped","scope":{"model":{"display_name":"Fable"}}}]}"#,
        #"{"limits":[]}"#,
    ])
    func limitsThatAreNotUsablePerModelCapsAreSkipped(json: String) throws {
        #expect(try buckets(json).isEmpty)
    }

    @Test(arguments: [
        "2026-08-19T03:20:00.123Z",
        "2026-08-19T03:20:00Z",
    ])
    func resetDatesParseWithAndWithoutFractionalSeconds(raw: String) throws {
        let result = try buckets(#"{"five_hour":{"utilization":1,"resets_at":"\#(raw)"}}"#)
        #expect(result.first?.resetsAt != nil)
    }

    @Test(arguments: ["", "not-a-date", "19/08/2026"])
    func unparseableResetDatesLeaveNoCountdown(raw: String) throws {
        let result = try buckets(#"{"five_hour":{"utilization":1,"resets_at":"\#(raw)"}}"#)
        #expect(result.first?.resetsAt == nil)
    }

    @Test("a missing reset date leaves no countdown")
    func missingResetDate() throws {
        let result = try buckets(#"{"five_hour":{"utilization":1}}"#)
        #expect(result.first?.resetsAt == nil)
    }

    @Test("a malformed body is reported rather than silently returning nothing")
    func malformedBodyThrows() {
        #expect(throws: (any Error).self) { try buckets("not json") }
    }
}

struct UsageErrorTests {
    @Test(arguments: [
        (UsageError.keychainUnavailable, "No Claude Code login, run claude to sign in"),
        (.tokenExpired, "Token expired, open Claude Code to refresh"),
        (.http(503), "Request failed (HTTP 503)"),
    ])
    func messages(error: UsageError, expected: String) {
        #expect(error.errorDescription == expected)
    }

    @Test("errors compare by case so a dead token is told apart from a failed request")
    func equatableByCase() {
        #expect(UsageError.tokenExpired == .tokenExpired)
        #expect(UsageError.http(429) != .http(500))
    }
}

struct TokenUsabilityTests {
    @Test("a token with life left is handed back unchanged")
    func usableTokenPassesThrough() throws {
        let token = StoredToken(accessToken: "abc", expiresAt: Date().addingTimeInterval(3_600))
        #expect(try UsageFetcher.requireUsable(token).accessToken == "abc")
    }

    @Test("a token with no recorded expiry is handed back unchanged")
    func tokenWithoutExpiryPassesThrough() throws {
        let token = StoredToken(accessToken: "abc", expiresAt: nil)
        #expect(try UsageFetcher.requireUsable(token).accessToken == "abc")
    }

    @Test(arguments: [Config.tokenExpiryMargin - 10, 0, -3_600])
    func tokenInsideTheMarginIsRejected(offset: TimeInterval) {
        let token = StoredToken(accessToken: "abc", expiresAt: Date().addingTimeInterval(offset))
        #expect(throws: UsageError.tokenExpired) { try UsageFetcher.requireUsable(token) }
    }
}

struct ProcessRunTests {
    @Test("a tool that succeeds hands back what it printed")
    func capturesOutput() {
        let output = UsageFetcher.run("/bin/echo", ["hello"], timeout: 5)
        #expect(String(decoding: output ?? Data(), as: UTF8.self) == "hello\n")
    }

    @Test("a tool that exits nonzero hands back nothing")
    func nonZeroExitIsNil() {
        #expect(UsageFetcher.run("/usr/bin/false", [], timeout: 5) == nil)
    }

    @Test("a tool that is not there hands back nothing rather than crashing")
    func missingExecutableIsNil() {
        #expect(UsageFetcher.run("/nowhere/at/all", [], timeout: 5) == nil)
    }

    @Test("a tool that hangs is killed at the deadline instead of blocking the poll")
    func timeoutTerminates() {
        let started = Date()
        #expect(UsageFetcher.run("/bin/sleep", ["30"], timeout: 0.5) == nil)
        #expect(Date().timeIntervalSince(started) < 10)
    }

    @Test("a tool that ignores the polite signal is killed outright")
    func timeoutOutlastsAnIgnoredSignal() {
        let started = Date()
        #expect(UsageFetcher.run("/bin/sh", ["-c", "trap '' TERM; sleep 30"], timeout: 0.5) == nil)
        #expect(Date().timeIntervalSince(started) < 10)
    }
}
