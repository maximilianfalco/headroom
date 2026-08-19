import Foundation
import Testing

struct SeverityTests {
    @Test(arguments: [
        (0, Severity.normal), (79, .normal),
        (80, .warning), (94, .warning),
        (95, .critical), (100, .critical), (140, .critical),
    ])
    func thresholds(percent: Int, expected: Severity) {
        #expect(Severity(percent: percent) == expected)
    }
}

struct UsageBucketTests {
    private func bucket(resetsIn seconds: TimeInterval?) -> UsageBucket {
        UsageBucket(key: "k", label: "L", percent: 10,
                    resetsAt: seconds.map { Date().addingTimeInterval($0) })
    }

    @Test("a bucket with no reset date shows no countdown")
    func noResetDate() {
        #expect(bucket(resetsIn: nil).resetsIn == nil)
    }

    static let countdowns: [(TimeInterval, String)] = [
        (1_800, "30m"),
        (5_400, "1h 30m"),
        (3_600, "1h 0m"),
        (90_000, "1d 1h"),
        (86_400, "1d 0h"),
    ]

    @Test(arguments: countdowns)
    func countdownFormatting(seconds: TimeInterval, expected: String) {
        #expect(bucket(resetsIn: seconds + 1).resetsIn == expected)
    }

    @Test("a reset already in the past clamps to zero rather than going negative")
    func pastResetClampsToZero() {
        #expect(bucket(resetsIn: -9_999).resetsIn == "0m")
    }

    @Test("a bucket identifies itself by its key, so lists stay stable across refreshes")
    func identifiedByKey() {
        #expect(UsageBucket(key: "seven_day", label: "Weekly", percent: 1, resetsAt: nil).id == "seven_day")
    }

    @Test("severity is derived from the percentage")
    func severityDerived() {
        #expect(UsageBucket(key: "k", label: "L", percent: 96, resetsAt: nil).severity == .critical)
    }
}

struct UsageSnapshotTests {
    private func bucket(_ percent: Int) -> UsageBucket {
        UsageBucket(key: "k\(percent)", label: "L", percent: percent, resetsAt: nil)
    }

    @Test("an empty snapshot has no worst limit")
    func emptyHasNoWorst() {
        #expect(UsageSnapshot(fetchedAt: .now, buckets: []).worst == nil)
    }

    @Test("worst picks the highest percentage")
    func worstPicksHighest() {
        let snapshot = UsageSnapshot(fetchedAt: .now, buckets: [bucket(4), bucket(91), bucket(60)])
        #expect(snapshot.worst?.percent == 91)
    }

    @Test("a snapshot written before local usage existed still decodes")
    func decodesSnapshotWithoutLocalUsage() throws {
        let json = """
        {"fetchedAt":"2026-08-19T02:00:00Z","buckets":[{"key":"five_hour","label":"Session","percent":8}]}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let snapshot = try decoder.decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(snapshot.local == nil)
        #expect(snapshot.buckets.count == 1)
    }

    @Test("local usage survives a round trip through the snapshot file")
    func localUsageRoundTrips() throws {
        let local = LocalUsage(todayNew: 1, todayCached: 2, todayCost: 3.5,
                               sessionNew: 4, sessionCached: 5, sessionCost: 6.5,
                               newPerMinute: 7.5)
        var snapshot = UsageSnapshot(fetchedAt: .now, buckets: [bucket(10)])
        snapshot.local = local

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(UsageSnapshot.self, from: encoder.encode(snapshot))

        #expect(decoded.local == local)
    }
}

struct StoredTokenTests {
    @Test("a token with no recorded expiry is treated as usable")
    func noExpiryIsUsable() {
        #expect(StoredToken(accessToken: "t", expiresAt: nil).isUsable)
    }

    static let expiries: [(TimeInterval, Bool)] = [
        (3_600, true),
        (Config.tokenExpiryMargin + 30, true),
        (Config.tokenExpiryMargin - 10, false),
        (0, false),
        (-3_600, false),
    ]

    @Test(arguments: expiries)
    func expiryMargin(offset: TimeInterval, usable: Bool) {
        let token = StoredToken(accessToken: "t", expiresAt: Date().addingTimeInterval(offset))
        #expect(token.isUsable == usable)
    }
}
