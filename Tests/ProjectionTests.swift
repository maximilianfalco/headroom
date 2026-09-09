import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_787_000_000)
private let hour: TimeInterval = 3_600
private let day: TimeInterval = 86_400

private func session(percent: Int, elapsed: TimeInterval) -> UsageBucket {
    UsageBucket(key: "five_hour", label: "Session", percent: percent,
                resetsAt: now.addingTimeInterval(Config.sessionWindow - elapsed))
}

private func weekly(key: String = "seven_day", percent: Int, elapsed: TimeInterval) -> UsageBucket {
    UsageBucket(key: key, label: "Weekly", percent: percent,
                resetsAt: now.addingTimeInterval(Config.weeklyWindow - elapsed))
}

private func sample(key: String = "five_hour", age: TimeInterval, percent: Int,
                    resetsAt: Date?, cost: Double? = nil) -> UsageSample {
    UsageSample(key: key, at: now.addingTimeInterval(-age), percent: percent,
                resetsAt: resetsAt, cost: cost)
}

private func project(_ bucket: UsageBucket, samples: [UsageSample] = [], cost: Double? = nil) -> Int? {
    Projection.project(bucket, samples: samples, cost: cost, now: now)
}

struct ProjectionWindowTests {
    @Test("the session limit runs on the five hour window, everything else on the week")
    func windowByKey() {
        #expect(Projection.window(for: "five_hour") == Config.sessionWindow)
        #expect(Projection.window(for: "seven_day") == Config.weeklyWindow)
        #expect(Projection.window(for: "weekly_fable") == Config.weeklyWindow)
    }
}

struct ProjectionHorizonTests {
    @Test("no reset time means no horizon, so no projection")
    func noResetTime() {
        let bucket = UsageBucket(key: "five_hour", label: "Session", percent: 40, resetsAt: nil)
        #expect(project(bucket) == nil)
    }

    @Test("a reset already behind us means no projection")
    func resetInThePast() {
        let bucket = UsageBucket(key: "five_hour", label: "Session", percent: 40,
                                 resetsAt: now.addingTimeInterval(-60))
        #expect(project(bucket) == nil)
    }

    @Test("a reset exactly now means no projection")
    func resetExactlyNow() {
        let bucket = UsageBucket(key: "five_hour", label: "Session", percent: 40, resetsAt: now)
        #expect(project(bucket) == nil)
    }

    @Test("the session waits until three percent of its window has passed")
    func sessionWarmup() {
        let warmup = Config.sessionWindow * Config.projectionWarmup
        #expect(project(session(percent: 5, elapsed: warmup - 1)) == nil)
        #expect(project(session(percent: 5, elapsed: warmup)) != nil)
    }

    @Test("the week waits until three percent of its window has passed")
    func weeklyWarmup() {
        let warmup = Config.weeklyWindow * Config.projectionWarmup
        #expect(project(weekly(percent: 5, elapsed: warmup - 1)) == nil)
        #expect(project(weekly(percent: 5, elapsed: warmup)) != nil)
    }
}

struct ProjectionAveragePaceTests {
    @Test("with no history the session scales its average pace to the reset")
    func sessionAverage() {
        #expect(project(session(percent: 10, elapsed: hour)) == 50)
    }

    @Test("the week scales percent so far by days remaining")
    func weeklyScale() {
        #expect(project(weekly(percent: 20, elapsed: 2 * day)) == 70)
    }

    @Test("a per model weekly cap uses the weekly window")
    func perModelWeekly() {
        #expect(project(weekly(key: "weekly_fable", percent: 20, elapsed: 2 * day)) == 70)
    }

    @Test("the projection is capped at one hundred")
    func cappedAtHundred() {
        #expect(project(session(percent: 30, elapsed: hour)) == 100)
    }

    @Test("a pace that falls just short of the cap rounds to 99, never to the warning")
    func justShortOfCapStaysBelow() {
        #expect(project(session(percent: 20, elapsed: 3_615)) == 99)
    }

    @Test("a limit sitting at zero projects to zero")
    func zeroStaysZero() {
        #expect(project(session(percent: 0, elapsed: 2 * hour)) == 0)
    }

    @Test("the result is rounded, not truncated")
    func rounded() {
        #expect(project(weekly(percent: 2, elapsed: 3 * day)) == 5)
    }

    @Test("the week ignores session samples even when they are present")
    func weeklyIgnoresSamples() {
        let bucket = weekly(percent: 20, elapsed: 2 * day)
        let history = [sample(key: "seven_day", age: 30 * 60, percent: 20, resetsAt: bucket.resetsAt)]
        #expect(project(bucket, samples: history) == 70)
    }
}

struct ProjectionTrailingPaceTests {
    private let bucket = session(percent: 20, elapsed: 4 * hour)

    @Test("a flat last half hour projects no growth, where the average would")
    func flatTrendBeatsAverage() {
        let history = [sample(age: 30 * 60, percent: 20, resetsAt: bucket.resetsAt)]
        #expect(project(bucket, samples: history) == 20)
        #expect(project(bucket) == 25)
    }

    @Test("a rising last half hour is extended to the reset")
    func risingTrend() {
        let history = [sample(age: 30 * 60, percent: 10, resetsAt: bucket.resetsAt)]
        #expect(project(bucket, samples: history) == 40)
    }

    @Test("the oldest sample inside the trailing window anchors the pace")
    func oldestInWindowAnchors() {
        let history = [
            sample(age: 10 * 60, percent: 18, resetsAt: bucket.resetsAt),
            sample(age: 20 * 60, percent: 10, resetsAt: bucket.resetsAt),
        ]
        #expect(project(bucket, samples: history) == 50)
    }

    @Test("a sample older than the trailing window is ignored")
    func olderThanWindowIgnored() {
        let history = [sample(age: Config.projectionTrailing + 1, percent: 20, resetsAt: bucket.resetsAt)]
        #expect(project(bucket, samples: history) == 25)
    }

    @Test("a sample exactly at the trailing edge still counts")
    func exactlyAtWindowEdgeCounts() {
        let history = [sample(age: Config.projectionTrailing, percent: 20, resetsAt: bucket.resetsAt)]
        #expect(project(bucket, samples: history) == 20)
    }

    @Test("a sample too young to give a pace falls back to the average")
    func tooYoungFallsBack() {
        let history = [sample(age: Config.projectionTrailingMinimum - 1, percent: 20, resetsAt: bucket.resetsAt)]
        #expect(project(bucket, samples: history) == 25)
    }

    @Test("a sample exactly at the minimum age gives a pace")
    func exactlyMinimumAgeCounts() {
        let history = [sample(age: Config.projectionTrailingMinimum, percent: 20, resetsAt: bucket.resetsAt)]
        #expect(project(bucket, samples: history) == 20)
    }

    @Test("samples from the previous window are ignored")
    func previousWindowIgnored() {
        let previous = bucket.resetsAt!.addingTimeInterval(-Config.sessionWindow)
        let history = [sample(age: 30 * 60, percent: 20, resetsAt: previous)]
        #expect(project(bucket, samples: history) == 25)
    }

    @Test("a reset time that drifted by less than a minute is the same window")
    func driftedResetIsSameWindow() {
        let drifted = bucket.resetsAt!.addingTimeInterval(Config.resetMatchTolerance)
        let history = [sample(age: 30 * 60, percent: 20, resetsAt: drifted)]
        #expect(project(bucket, samples: history) == 20)
    }

    @Test("a reset time that drifted by more than a minute is another window")
    func driftedBeyondToleranceIsAnotherWindow() {
        let drifted = bucket.resetsAt!.addingTimeInterval(Config.resetMatchTolerance + 1)
        let history = [sample(age: 30 * 60, percent: 20, resetsAt: drifted)]
        #expect(project(bucket, samples: history) == 25)
    }

    @Test("a sample with no reset time belongs to no window")
    func nilResetIsNoWindow() {
        let history = [sample(age: 30 * 60, percent: 20, resetsAt: nil)]
        #expect(project(bucket, samples: history) == 25)
    }

    @Test("samples for another limit are ignored")
    func otherKeyIgnored() {
        let history = [sample(key: "seven_day", age: 30 * 60, percent: 20, resetsAt: bucket.resetsAt)]
        #expect(project(bucket, samples: history) == 25)
    }

    @Test("a falling percent never projects below the current value")
    func fallingClampsToCurrent() {
        let history = [sample(age: 30 * 60, percent: 30, resetsAt: bucket.resetsAt)]
        #expect(project(bucket, samples: history) == 20)
    }
}

struct ProjectionRatioTests {
    private let resetsAt = now.addingTimeInterval(hour)

    private func pair(_ from: (age: TimeInterval, percent: Int, cost: Double),
                      _ to: (age: TimeInterval, percent: Int, cost: Double),
                      resetsAt: Date? = nil) -> [UsageSample] {
        [
            sample(age: from.age, percent: from.percent, resetsAt: resetsAt ?? self.resetsAt, cost: from.cost),
            sample(age: to.age, percent: to.percent, resetsAt: resetsAt ?? self.resetsAt, cost: to.cost),
        ]
    }

    @Test("the ratio is spend per percentage point")
    func spendPerPoint() {
        let history = pair((age: 600, percent: 0, cost: 0), (age: 0, percent: 10, cost: 10))
        #expect(Projection.ratio(history) == 1.0)
    }

    @Test("too few points to trust gives no ratio")
    func belowMinimumPoints() {
        let history = pair((age: 600, percent: 0, cost: 0),
                           (age: 0, percent: Config.ratioMinimumPoints - 1, cost: 10))
        #expect(Projection.ratio(history) == nil)
    }

    @Test("exactly the minimum points is enough")
    func exactlyMinimumPoints() {
        let history = pair((age: 600, percent: 0, cost: 0),
                           (age: 0, percent: Config.ratioMinimumPoints, cost: 5))
        #expect(Projection.ratio(history) == 1.0)
    }

    @Test("points that moved with no local spend lower that window's score")
    func pointsWithoutSpendLowerTheScore() {
        let history = pair((age: 1_200, percent: 0, cost: 0), (age: 600, percent: 5, cost: 0))
            + [sample(age: 0, percent: 25, resetsAt: resetsAt, cost: 10)]
        #expect(Projection.ratio(history) == 0.4)
    }

    @Test("spend seen on one poll and its points on the next still pair up")
    func staggeredSpendAndPointsPairUp() {
        let history = pair((age: 1_200, percent: 10, cost: 10), (age: 600, percent: 10, cost: 15))
            + [sample(age: 0, percent: 15, resetsAt: resetsAt, cost: 15)]
        #expect(Projection.ratio(history) == 1.0)
    }

    @Test("a cost counter that fell inside a window closes that window's score")
    func fallingCostClosesTheScore() {
        let history = pair((age: 1_800, percent: 0, cost: 0), (age: 1_200, percent: 10, cost: 10))
            + pair((age: 600, percent: 10, cost: 1), (age: 0, percent: 20, cost: 3))
        #expect(Projection.ratio(history) == 1.0)
    }

    @Test("a new reset time separates scores even when percent and cost never fall")
    func resetTimeAloneSeparatesScores() {
        let previous = resetsAt.addingTimeInterval(-Config.sessionWindow)
        let history = pair((age: 7_200, percent: 0, cost: 0), (age: 6_000, percent: 10, cost: 10),
                           resetsAt: previous)
            + pair((age: 600, percent: 10, cost: 10), (age: 0, percent: 20, cost: 15))
        #expect(Projection.ratio(history) == 1.0)
    }

    @Test("a span where the percent fell is a reset, not a pair")
    func skipsFallingSpans() {
        let history = pair((age: 1_200, percent: 50, cost: 0), (age: 600, percent: 0, cost: 0.5))
            + [sample(age: 0, percent: 10, resetsAt: resetsAt, cost: 10.5)]
        #expect(Projection.ratio(history) == 1.0)
    }

    @Test("a percent that fell inside a window closes that window's score")
    func fallingPercentClosesTheScore() {
        let history = pair((age: 1_800, percent: 0, cost: 0), (age: 1_200, percent: 10, cost: 10))
            + pair((age: 600, percent: 0, cost: 10.5), (age: 0, percent: 10, cost: 15.5))
        #expect(Projection.ratio(history) == 1.0)
    }

    @Test("spans across two windows are not paired")
    func skipsSpansAcrossWindows() {
        let previous = resetsAt.addingTimeInterval(-Config.sessionWindow)
        let history = [sample(age: 1_200, percent: 90, resetsAt: previous, cost: 0)]
            + pair((age: 600, percent: 0, cost: 0.5), (age: 0, percent: 10, cost: 10.5))
        #expect(Projection.ratio(history) == 1.0)
    }

    @Test("samples without a spend figure are not paired")
    func skipsSamplesWithoutSpend() {
        let history = [sample(age: 1_200, percent: 0, resetsAt: resetsAt, cost: nil)]
            + pair((age: 600, percent: 0, cost: 0), (age: 0, percent: 10, cost: 10))
        #expect(Projection.ratio(history) == 1.0)
    }

    @Test("samples for another limit are not paired")
    func skipsOtherKeys() {
        let history = pair((age: 600, percent: 0, cost: 0), (age: 0, percent: 10, cost: 10))
            + [sample(key: "seven_day", age: 300, percent: 50, resetsAt: resetsAt, cost: 0.5)]
        #expect(Projection.ratio(history) == 1.0)
    }

    @Test("samples are paired in time order however they are stored")
    func pairsInTimeOrder() {
        let history = pair((age: 0, percent: 10, cost: 10), (age: 600, percent: 0, cost: 0))
        #expect(Projection.ratio(history) == 1.0)
    }

    @Test("each window is scored on its own and the cleanest one sets the ratio")
    func cleanestWindowWins() {
        let previous = resetsAt.addingTimeInterval(-Config.sessionWindow)
        let history = pair((age: 7_200, percent: 0, cost: 0), (age: 6_000, percent: 5, cost: 10),
                           resetsAt: previous)
            + pair((age: 600, percent: 0, cost: 0), (age: 0, percent: 10, cost: 5))
        #expect(Projection.ratio(history) == 2.0)
    }

    @Test("a window that also saw claude.ai use cannot drag the ratio down")
    func outsideUsageDoesNotDragTheRatioDown() {
        let previous = resetsAt.addingTimeInterval(-Config.sessionWindow)
        let clean = pair((age: 7_200, percent: 0, cost: 0), (age: 6_000, percent: 10, cost: 10),
                         resetsAt: previous)
        let mixed = pair((age: 600, percent: 0, cost: 0), (age: 0, percent: 10, cost: 1))
        #expect(Projection.ratio(clean + mixed) == 1.0)
        #expect(Projection.ratio(mixed) == 0.1)
    }

    @Test("a window below the minimum points is ignored even when another qualifies")
    func windowBelowMinimumIsIgnored() {
        let previous = resetsAt.addingTimeInterval(-Config.sessionWindow)
        let history = pair((age: 7_200, percent: 0, cost: 0), (age: 6_000, percent: 4, cost: 10),
                           resetsAt: previous)
            + pair((age: 600, percent: 0, cost: 0), (age: 0, percent: 10, cost: 5))
        #expect(Projection.ratio(history) == 0.5)
    }

    @Test("no samples gives no ratio")
    func empty() {
        #expect(Projection.ratio([]) == nil)
    }
}

struct ProjectionBlendTests {
    private let bucket = session(percent: 20, elapsed: 4 * hour)

    /// Ten points for ten dollars, learned in the previous window.
    private var learned: [UsageSample] {
        let previous = bucket.resetsAt!.addingTimeInterval(-Config.sessionWindow)
        return [
            sample(age: 6 * hour, percent: 0, resetsAt: previous, cost: 0),
            sample(age: 5 * hour, percent: 10, resetsAt: previous, cost: 10),
        ]
    }

    @Test("a flat percent with spend flowing is pulled up by the burn rate")
    func burnRaisesFlatTrend() {
        let history = learned
            + [sample(age: 30 * 60, percent: 20, resetsAt: bucket.resetsAt, cost: 10)]
        #expect(project(bucket, samples: history, cost: 16) == 26)
    }

    @Test("trend and burn rate are averaged")
    func averaged() {
        let history = learned
            + [sample(age: 30 * 60, percent: 10, resetsAt: bucket.resetsAt, cost: 10)]
        #expect(project(bucket, samples: history, cost: 10) == 30)
    }

    @Test("without a learned ratio the trend stands alone")
    func noRatioMeansTrendOnly() {
        let history = [sample(age: 30 * 60, percent: 20, resetsAt: bucket.resetsAt, cost: 10)]
        #expect(project(bucket, samples: history, cost: 16) == 20)
    }

    @Test("without a current spend figure the trend stands alone")
    func noCostMeansTrendOnly() {
        let history = learned
            + [sample(age: 30 * 60, percent: 20, resetsAt: bucket.resetsAt, cost: 10)]
        #expect(project(bucket, samples: history, cost: nil) == 20)
    }

    @Test("a trailing sample without spend gives no burn rate")
    func anchorWithoutCostMeansTrendOnly() {
        let history = learned
            + [sample(age: 30 * 60, percent: 20, resetsAt: bucket.resetsAt, cost: nil)]
        #expect(project(bucket, samples: history, cost: 16) == 20)
    }

    @Test("the burn rate anchors on the oldest trailing sample that has spend")
    func burnAnchorsOnOldestWithCost() {
        let history = learned + [
            sample(age: 30 * 60, percent: 20, resetsAt: bucket.resetsAt, cost: nil),
            sample(age: 15 * 60, percent: 20, resetsAt: bucket.resetsAt, cost: 13),
        ]
        #expect(project(bucket, samples: history, cost: 16) == 26)
    }

    @Test("with two spend samples in the span the older one anchors the burn rate")
    func burnAnchorsOnOlderOfTwo() {
        let history = learned + [
            sample(age: 30 * 60, percent: 20, resetsAt: bucket.resetsAt, cost: 10),
            sample(age: 15 * 60, percent: 20, resetsAt: bucket.resetsAt, cost: 15),
        ]
        #expect(Projection.ratio(history) == 1.0)
        #expect(project(bucket, samples: history, cost: 16) == 26)
    }

    @Test("a spend anchor too young to give a pace leaves the trend alone")
    func youngCostAnchorMeansTrendOnly() {
        let history = learned + [
            sample(age: 30 * 60, percent: 20, resetsAt: bucket.resetsAt, cost: nil),
            sample(age: Config.projectionTrailingMinimum - 1, percent: 20,
                   resetsAt: bucket.resetsAt, cost: 15),
        ]
        #expect(project(bucket, samples: history, cost: 16) == 20)
    }

    @Test("a spend counter that fell, as it does at midnight, leaves a rising trend alone")
    func fallingCostLeavesTheTrendAlone() {
        let history = learned
            + [sample(age: 30 * 60, percent: 10, resetsAt: bucket.resetsAt, cost: 20)]
        #expect(project(bucket, samples: history, cost: 10) == 40)
    }

    @Test("a spend counter that fell and then recovered inside the span still gives no burn")
    func fallThenRecoverLeavesTheTrendAlone() {
        let history = learned + [
            sample(age: 30 * 60, percent: 10, resetsAt: bucket.resetsAt, cost: 10),
            sample(age: 15 * 60, percent: 15, resetsAt: bucket.resetsAt, cost: 1),
        ]
        #expect(project(bucket, samples: history, cost: 12) == 40)
    }

    @Test("a blended result is still capped at one hundred")
    func blendCapped() {
        let history = learned
            + [sample(age: 30 * 60, percent: 20, resetsAt: bucket.resetsAt, cost: 0)]
        #expect(project(bucket, samples: history, cost: 1_000) == 100)
    }
}

struct ProjectionApplyTests {
    private var snapshot: UsageSnapshot {
        var snapshot = UsageSnapshot(fetchedAt: now, buckets: [
            session(percent: 10, elapsed: hour),
            weekly(percent: 20, elapsed: 2 * day),
        ])
        snapshot.local = LocalUsage(todayNew: 1, todayCached: 2, todayCost: 3,
                                    sessionNew: 4, sessionCached: 5, sessionCost: 4.5,
                                    newPerMinute: 7)
        return snapshot
    }

    @Test("every limit gets a sample, and only the session carries spend")
    func recordsOneSamplePerLimit() {
        var snapshot = snapshot
        let samples = Projection.apply(to: &snapshot, history: [], now: now)

        #expect(samples.map(\.key) == ["five_hour", "seven_day"])
        #expect(samples.map(\.at) == [now, now])
        #expect(samples.map(\.percent) == [10, 20])
        #expect(samples.map(\.resetsAt) == snapshot.buckets.map(\.resetsAt))
        #expect(samples.map(\.cost) == [4.5, nil])
    }

    @Test("without local usage the session sample has no spend")
    func noLocalUsageMeansNoCost() {
        var snapshot = snapshot
        snapshot.local = nil
        let samples = Projection.apply(to: &snapshot, history: [], now: now)
        #expect(samples.map(\.cost) == [nil, nil])
    }

    @Test("every limit gets its projection written back")
    func projectsEveryLimit() {
        var snapshot = snapshot
        _ = Projection.apply(to: &snapshot, history: [], now: now)
        #expect(snapshot.buckets.map(\.projected) == [50, 70])
    }

    @Test("history older than the retention window is dropped, the rest kept")
    func trimsOldHistory() {
        var snapshot = snapshot
        let old = sample(age: Config.sampleRetention + 1, percent: 1, resetsAt: nil)
        let kept = sample(age: Config.sampleRetention, percent: 2, resetsAt: nil)
        let samples = Projection.apply(to: &snapshot, history: [old, kept], now: now)

        #expect(samples.contains(kept))
        #expect(samples.contains(old) == false)
        #expect(samples.count == 3)
    }

    @Test("the sample recorded this poll feeds this poll's projection")
    func currentSampleFeedsProjection() {
        var snapshot = snapshot
        let previous = sample(age: 30 * 60, percent: 10, resetsAt: snapshot.buckets[0].resetsAt)
        _ = Projection.apply(to: &snapshot, history: [previous], now: now)
        #expect(snapshot.buckets[0].projected == 10)
    }

    @Test("the blend runs through the sample recorded this poll, which joins no window score on its own")
    func blendThroughApply() {
        var snapshot = UsageSnapshot(fetchedAt: now, buckets: [session(percent: 20, elapsed: 4 * hour)])
        snapshot.local = LocalUsage(todayNew: 0, todayCached: 0, todayCost: 0,
                                    sessionNew: 0, sessionCached: 0, sessionCost: 16,
                                    newPerMinute: 0)
        let previous = snapshot.buckets[0].resetsAt!.addingTimeInterval(-Config.sessionWindow)
        let history = [
            sample(age: 6 * hour, percent: 0, resetsAt: previous, cost: 0),
            sample(age: 5 * hour, percent: 10, resetsAt: previous, cost: 10),
            sample(age: 30 * 60, percent: 20, resetsAt: snapshot.buckets[0].resetsAt, cost: 10),
        ]
        _ = Projection.apply(to: &snapshot, history: history, now: now)
        #expect(snapshot.buckets[0].projected == 26)
    }

    @Test("an empty snapshot records nothing and projects nothing")
    func emptySnapshot() {
        var snapshot = UsageSnapshot(fetchedAt: now, buckets: [])
        #expect(Projection.apply(to: &snapshot, history: [], now: now).isEmpty)
        #expect(snapshot.buckets.isEmpty)
    }
}
