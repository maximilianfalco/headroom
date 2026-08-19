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
        (UsageError.needsReconnect, "Keychain access needed"),
        (.keychainUnavailable, "Cannot read Claude Code credentials"),
        (.tokenExpired, "Token expired, open Claude Code to refresh"),
        (.http(503), "Request failed (HTTP 503)"),
    ])
    func messages(error: UsageError, expected: String) {
        #expect(error.errorDescription == expected)
    }

    @Test("errors compare by case so the panel can single out a reconnect")
    func equatableByCase() {
        #expect(UsageError.needsReconnect == .needsReconnect)
        #expect(UsageError.http(429) != .http(500))
    }
}

struct KeychainQueryTests {
    @Test("a denied query carries both the modern context and the legacy UI policy")
    func deniesInteraction() {
        var query: [String: Any] = [:]
        KeychainQuery.denyInteraction(&query)
        #expect(query[kSecUseAuthenticationContext as String] != nil)
        #expect(query[kSecUseAuthenticationUI as String] as? String == kSecUseAuthenticationUIFail as String)
    }

    @Test("existing query keys are left alone")
    func preservesExistingKeys() {
        var query: [String: Any] = [kSecAttrService as String: "svc"]
        KeychainQuery.denyInteraction(&query)
        #expect(query[kSecAttrService as String] as? String == "svc")
    }
}
