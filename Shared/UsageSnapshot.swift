import Foundation

enum Severity: String, Codable {
    case normal, warning, critical

    init(percent: Int) {
        self = percent >= Config.criticalAt ? .critical
            : percent >= Config.warningAt ? .warning : .normal
    }
}

enum PercentDisplay: String, Codable, CaseIterable, Identifiable {
    case used, remaining

    var id: String { rawValue }
    var label: String { self == .used ? "Used" : "Remaining" }
}

struct UsageBucket: Codable, Identifiable, Equatable {
    var key: String
    var label: String
    var percent: Int
    var resetsAt: Date?

    var id: String { key }
    /// Deliberately not routed through `shown`: colour says how close the cap is, so a panel
    /// reading "93% left" still shows green.
    var severity: Severity { Severity(percent: percent) }

    /// The number to put on screen. A limit can report over 100, so headroom floors at zero.
    func shown(_ display: PercentDisplay) -> Int {
        display == .used ? percent : max(0, 100 - percent)
    }

    /// Only remaining says which it is, because a bare percentage already reads as used.
    func shownText(_ display: PercentDisplay) -> String {
        display == .used ? "\(percent)%" : "\(shown(.remaining))% left"
    }

    /// The countdown as it appears on screen. Notifications word it their own way and use
    /// `resetsIn` directly.
    var resetsLabel: String? { resetsIn.map { "Resets in \($0)" } }

    var resetsIn: String? {
        guard let resetsAt else { return nil }
        let mins = max(0, Int(resetsAt.timeIntervalSinceNow / 60))
        if mins >= 1440 { return "\(mins / 1440)d \((mins % 1440) / 60)h" }
        if mins >= 60 { return "\(mins / 60)h \(mins % 60)m" }
        return "\(mins)m"
    }
}

/// Token counts and cost derived from the local session logs. Lives beside the snapshot
/// rather than with the reader, so the widget can render it without carrying the parser.
///
/// New and cached are kept apart because a long session is ~97% cache reads: the same prefix
/// read back once per turn. Summing them produces a headline number that says nothing about
/// how much work was done, and looks absurd next to a single digit limit percentage.
struct LocalUsage: Codable, Equatable {
    var todayNew: Int
    var todayCached: Int
    var todayCost: Double
    var sessionNew: Int
    var sessionCached: Int
    var sessionCost: Double
    var newPerMinute: Double
}

struct UsageSnapshot: Codable, Equatable {
    var fetchedAt: Date
    var buckets: [UsageBucket]
    var error: String?
    /// Token counts and cost from the local logs. Optional so a snapshot written before this
    /// existed still decodes.
    var local: LocalUsage?
    /// The widget cannot see the app's settings, so the choice travels with the data it draws.
    /// Optional so a snapshot written before this existed still decodes.
    var display: PercentDisplay?

    var worst: UsageBucket? {
        buckets.max { $0.percent < $1.percent }
    }

    static let placeholder = UsageSnapshot(
        fetchedAt: .now,
        buckets: [
            UsageBucket(key: "five_hour", label: "Session", percent: 72,
                        resetsAt: .now.addingTimeInterval(5100)),
            UsageBucket(key: "seven_day", label: "Weekly", percent: 84,
                        resetsAt: .now.addingTimeInterval(41100)),
        ]
    )
}
