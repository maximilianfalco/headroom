import Foundation
import UserNotifications

/// Fires threshold crossings on the way up and a reset notice when a window rolls over.
enum UsageNotifier {
    private static let stateKey = "notifiedThresholds"
    private static let previousKey = "previousSnapshot"
    private static let enabledKey = "notificationsEnabled"

    static var isEnabled: Bool {
        get { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    static func requestAuthorization() async {
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    /// macOS prompts once. After a denial the request returns immediately and every `add`
    /// fails silently, so the app has to say so itself or it just goes quiet forever.
    static func isDenied() async -> Bool {
        await UNUserNotificationCenter.current().notificationSettings()
            .authorizationStatus == .denied
    }

    static func evaluate(_ snapshot: UsageSnapshot) async {
        guard isEnabled else { return }
        let previous = loadPrevious()
        await notifyResets(snapshot, previous: previous)
        await notifyThresholds(snapshot)
        savePrevious(snapshot)
    }

    // MARK: - Resets

    private static func notifyResets(_ snapshot: UsageSnapshot, previous: UsageSnapshot?) async {
        guard let previous else { return }
        let display = snapshot.display ?? .used

        for bucket in snapshot.buckets {
            guard let old = previous.buckets.first(where: { $0.key == bucket.key }) else { continue }
            guard old.percent >= Config.resetNoticeFloor else { continue }

            // Usage only climbs within a window, so a meaningful drop is the reliable signal.
            // resets_at cannot be relied on: the API nulls it at the moment a window rolls.
            let dropped = old.percent - bucket.percent >= Config.resetDropMargin
            let rolled = if let o = old.resetsAt, let n = bucket.resetsAt {
                n > o.addingTimeInterval(60)
            } else { false }
            guard dropped || rolled else { continue }

            let content = UNMutableNotificationContent()
            content.title = "\(bucket.label) limit reset"
            var body = "Was \(old.shownText(display)), now \(bucket.shownText(display))."
            if let next = bucket.resetsIn { body += " Next reset in \(next)." }
            content.body = body
            if old.percent >= Config.soundAt { content.sound = .default }

            let id = "\(bucket.key)-reset-\(Int(snapshot.fetchedAt.timeIntervalSince1970))"
            try? await UNUserNotificationCenter.current()
                .add(UNNotificationRequest(identifier: id, content: content, trigger: nil))
        }
    }

    // MARK: - Thresholds

    private static func notifyThresholds(_ snapshot: UsageSnapshot) async {
        var state = UserDefaults.standard.dictionary(forKey: stateKey) as? [String: Int] ?? [:]

        for bucket in snapshot.buckets {
            let crossed = Config.notifyThresholds.filter { bucket.percent >= $0 }.max() ?? 0
            let previous = state[bucket.key] ?? 0
            if crossed > previous {
                await sendThreshold(bucket, threshold: crossed, display: snapshot.display ?? .used)
            }
            // Writing the lower value on reset is what rearms the next cycle.
            if crossed != previous { state[bucket.key] = crossed }
        }

        UserDefaults.standard.set(state, forKey: stateKey)
    }

    private static func sendThreshold(_ bucket: UsageBucket, threshold: Int,
                                      display: PercentDisplay) async {
        let content = UNMutableNotificationContent()
        content.title = threshold >= 100
            ? "\(bucket.label) limit reached"
            : "\(bucket.label) at \(bucket.shownText(display))"
        content.body = bucket.resetsIn.map { "Resets in \($0)." } ?? "Claude plan usage."
        if threshold >= Config.soundAt { content.sound = .default }

        let request = UNNotificationRequest(
            identifier: "\(bucket.key)-\(threshold)", content: content, trigger: nil)
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Previous snapshot

    private static func loadPrevious() -> UsageSnapshot? {
        guard let data = UserDefaults.standard.data(forKey: previousKey) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(UsageSnapshot.self, from: data)
    }

    private static func savePrevious(_ snapshot: UsageSnapshot) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(snapshot) else { return }
        UserDefaults.standard.set(data, forKey: previousKey)
    }
}
