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

    @Test("the countdown reads as a sentence on screen")
    func resetsLabelPrefixes() {
        #expect(bucket(resetsIn: 1_801).resetsLabel == "Resets in 30m")
    }

    @Test("no reset date means no countdown to label")
    func resetsLabelAbsent() {
        #expect(bucket(resetsIn: nil).resetsLabel == nil)
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

    @Test("a bucket written before projections existed still decodes")
    func decodesWithoutProjection() throws {
        let json = #"{"key":"five_hour","label":"Session","percent":8}"#
        let bucket = try JSONDecoder().decode(UsageBucket.self, from: Data(json.utf8))
        #expect(bucket.projected == nil)
    }

    @Test("the projection survives a round trip")
    func projectionRoundTrips() throws {
        var bucket = UsageBucket(key: "k", label: "L", percent: 10, resetsAt: nil)
        bucket.projected = 42
        let decoded = try JSONDecoder().decode(UsageBucket.self, from: JSONEncoder().encode(bucket))
        #expect(decoded.projected == 42)
    }
}

struct ProjectionTextTests {
    private func bucket(percent: Int, projected: Int?, resetsIn: TimeInterval? = 3_601) -> UsageBucket {
        var bucket = UsageBucket(key: "k", label: "L", percent: percent,
                                 resetsAt: resetsIn.map { Date().addingTimeInterval($0) })
        bucket.projected = projected
        return bucket
    }

    @Test("no projection means no marker text")
    func noProjection() {
        #expect(bucket(percent: 10, projected: nil).projectionText(.used) == nil)
    }

    @Test(arguments: [10, 9, 0])
    func noHigherThanCurrentMeansNoMarker(projected: Int) {
        #expect(bucket(percent: 10, projected: projected).projectionText(.used) == nil)
    }

    @Test("one point above the current percent is enough for a marker")
    func onePointAbove() {
        #expect(bucket(percent: 10, projected: 11).projectionText(.used) == "~11% when this resets in 1h 0m")
    }

    @Test("reaching the limit reads as a warning, not a number")
    func reachingTheLimit() {
        #expect(bucket(percent: 10, projected: 100).projectionText(.used)
                == "Expected to hit the limit before it resets")
    }

    @Test("a projection past one hundred still reads as the limit warning")
    func pastTheLimit() {
        #expect(bucket(percent: 10, projected: 140).projectionText(.used)
                == "Expected to hit the limit before it resets")
    }

    @Test("a projection whose reset has already passed shows no marker")
    func pastResetShowsNoMarker() {
        #expect(bucket(percent: 10, projected: 50, resetsIn: -60).projectionText(.used) == nil)
        #expect(bucket(percent: 10, projected: 100, resetsIn: -60).projectionText(.used) == nil)
    }

    @Test("a projection with no reset time shows no marker")
    func noResetTimeShowsNoMarker() {
        #expect(bucket(percent: 10, projected: 50, resetsIn: nil).projectionText(.used) == nil)
    }

    @Test("remaining reads the projection as headroom left")
    func remainingFlipsTheText() {
        #expect(bucket(percent: 10, projected: 85).projectionText(.remaining)
                == "~15% left when this resets in 1h 0m")
    }

    @Test("the limit warning reads the same either way")
    func remainingKeepsTheLimitWarning() {
        #expect(bucket(percent: 10, projected: 100).projectionText(.remaining)
                == "Expected to hit the limit before it resets")
    }

    @Test("the marker sits on the same axis as the bar")
    func markerFollowsTheDisplay() {
        let b = bucket(percent: 10, projected: 85)
        #expect(b.shownProjection(.used) == 85)
        #expect(b.shownProjection(.remaining) == 15)
        #expect(bucket(percent: 10, projected: nil).shownProjection(.used) == nil)
        #expect(bucket(percent: 10, projected: 140).shownProjection(.remaining) == 0)
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
