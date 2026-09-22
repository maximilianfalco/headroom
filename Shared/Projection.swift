import Foundation

/// One reading of a limit's percent, taken on one poll. The session sample also carries what
/// Claude Code had spent in that window so far, which is what pairs spend with points.
struct UsageSample: Codable, Equatable {
    var key: String
    var at: Date
    var percent: Int
    var resetsAt: Date?
    var cost: Double?
}

/// Projects each limit to the percent it should reach at its reset.
///
/// The session limit blends two paces: the percent trend over the last half hour, and the
/// local spend over the same span turned into points through a learned ratio. Spend is used
/// rather than raw tokens because it already weights by model and prices cache reads at
/// their reduced rate, which is how Anthropic says usage is counted. The weekly limits scale
/// their average pace, since an hour of trend says little about a week.
enum Projection {
    private static let sessionKey = UsageBucket.sessionKey

    /// Records this poll into the history, trims what is past retention, and writes a
    /// projection onto every bucket. One call, so a bucket never carries a projection its
    /// own sample did not feed.
    static func apply(to snapshot: inout UsageSnapshot, history: [UsageSample], now: Date) -> [UsageSample] {
        var samples = history.filter { $0.at >= now - Config.sampleRetention }
        let cost = snapshot.local?.sessionCost
        samples += snapshot.buckets.map {
            UsageSample(key: $0.key, at: now, percent: $0.percent, resetsAt: $0.resetsAt,
                        cost: $0.key == sessionKey ? cost : nil)
        }
        for i in snapshot.buckets.indices {
            snapshot.buckets[i].projected = project(snapshot.buckets[i], samples: samples,
                                                    cost: cost, now: now)
        }
        return samples
    }

    static func window(for key: String) -> TimeInterval {
        key == sessionKey ? Config.sessionWindow : Config.weeklyWindow
    }

    /// Percent at reset, capped at 100. Nil without a horizon, or so early in the window
    /// that no pace means anything yet.
    static func project(_ bucket: UsageBucket, samples: [UsageSample], cost: Double?, now: Date) -> Int? {
        guard let resetsAt = bucket.resetsAt, resetsAt > now else { return nil }
        guard let window = bucket.windowDuration ?? (bucket.provider == .codex ? nil : window(for: bucket.key)),
              window.isFinite, window > 0 else { return nil }
        let remaining = resetsAt.timeIntervalSince(now)
        let elapsed = window - remaining
        guard elapsed >= window * Config.projectionWarmup else { return nil }

        var rate = Double(bucket.percent) / elapsed
        if bucket.key == sessionKey || (bucket.provider == .codex && window <= Config.sessionWindow) {
            let trailing = samples.filter {
                $0.key == bucket.key && sameWindow($0.resetsAt, resetsAt)
                    && now.timeIntervalSince($0.at) <= Config.projectionTrailing
            }
            let trend = pace(trailing, current: bucket.percent, now: now) ?? rate
            if bucket.key == sessionKey, let burn = burn(trailing, cost: cost, ratio: ratio(samples), now: now) {
                rate = (trend + burn) / 2
            } else {
                rate = trend
            }
        }
        let projected = Double(bucket.percent) + rate * remaining
        // The panel reads 100 as a warning, so only a pace that truly reaches the cap gets there.
        return projected >= 100 ? 100 : min(99, Int(projected.rounded()))
    }

    /// Local spend per percentage point. Each window is scored on its own and the highest
    /// score wins: points spent on claude.ai or Desktop come with no local spend, so a window
    /// that saw them scores low, and the cleanest window is the truest.
    static func ratio(_ samples: [UsageSample]) -> Double? {
        let paired = samples
            .filter { $0.key == sessionKey }
            .compactMap { s in s.cost.map { (at: s.at, percent: s.percent, resetsAt: s.resetsAt, cost: $0) } }
            .sorted { $0.at < $1.at }
        var scores: [Double] = []
        var cost = 0.0, points = 0
        func score() {
            if points >= Config.ratioMinimumPoints { scores.append(cost / Double(points)) }
            cost = 0
            points = 0
        }
        for (from, to) in zip(paired, paired.dropFirst()) {
            // A new window, a percent that fell (a reset that kept its reset time), or a cost
            // that fell (the reader's midnight) all end one score and start the next.
            guard sameWindow(from.resetsAt, to.resetsAt), to.percent >= from.percent,
                  to.cost >= from.cost
            else {
                score()
                continue
            }
            cost += to.cost - from.cost
            points += to.percent - from.percent
        }
        score()
        return scores.max()
    }

    /// Percent per second, anchored on the oldest trailing sample. Nil when that sample is
    /// too young for the pace to mean anything.
    private static func pace(_ trailing: [UsageSample], current: Int, now: Date) -> Double? {
        guard let oldest = trailing.min(by: { $0.at < $1.at }) else { return nil }
        let age = now.timeIntervalSince(oldest.at)
        guard age >= Config.projectionTrailingMinimum else { return nil }
        return max(0, Double(current - oldest.percent) / age)
    }

    /// The spend pace over the same span, in percent per second through the ratio.
    private static func burn(_ trailing: [UsageSample], cost: Double?, ratio: Double?, now: Date) -> Double? {
        let anchors = trailing.compactMap { sample in sample.cost.map { (at: sample.at, cost: $0) } }
            .sorted { $0.at < $1.at }
        guard let cost, let ratio, let oldest = anchors.first else { return nil }
        let age = now.timeIntervalSince(oldest.at)
        guard age >= Config.projectionTrailingMinimum else { return nil }
        // The reader counts from midnight, so a counter that fell anywhere in the span is a
        // new day, not a refund. No burn beats a burn missing most of its span.
        let costs = anchors.map(\.cost) + [cost]
        guard zip(costs, costs.dropFirst()).allSatisfy({ $0 <= $1 }) else { return nil }
        return (cost - oldest.cost) / age / ratio
    }

    /// The API nudges `resets_at` by seconds between polls, so equality is too strict.
    private static func sameWindow(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return false }
        return abs(a.timeIntervalSince(b)) <= Config.resetMatchTolerance
    }
}
