import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var notificationsDenied = false
    @Published var notificationsEnabled = UsageNotifier.isEnabled {
        didSet { UsageNotifier.isEnabled = notificationsEnabled }
    }
    @Published var percentDisplay = UsageModel.stored(PercentDisplay.self, "percentDisplay") ?? .used {
        didSet {
            UserDefaults.standard.set(percentDisplay.rawValue, forKey: "percentDisplay")
            republish()
        }
    }
    @Published var spriteKind = UsageModel.stored(SpriteKind.self, "spriteKind") ?? .plant {
        didSet { UserDefaults.standard.set(spriteKind.rawValue, forKey: "spriteKind") }
    }
    @Published var spriteMotion = UsageModel.stored(SpriteMotion.self, "spriteMotion") ?? .follow {
        didSet { UserDefaults.standard.set(spriteMotion.rawValue, forKey: "spriteMotion") }
    }

    private static func stored<T: RawRepresentable>(_ type: T.Type, _ key: String) -> T?
        where T.RawValue == String {
        UserDefaults.standard.string(forKey: key).flatMap(T.init(rawValue:))
    }

    /// What the sprite draws: the same number the panel is showing, whichever that is.
    var worstFill: Double {
        Double(snapshot?.worst?.shown(percentDisplay) ?? 0) / 100
    }

    /// What the sprite colours by, which stays tied to the cap however the number is shown.
    var worstDanger: Double {
        Double(snapshot?.worst?.percent ?? 0) / 100
    }

    /// The widget only ever sees the snapshot file, so a setting change has to be written
    /// back through it rather than waiting for the next poll.
    private func republish() {
        guard var current = snapshot else { return }
        current.display = percentDisplay
        snapshot = current
        try? UsageStore.save(current)
        WidgetCenter.shared.reloadAllTimelines()
    }

    private var poller: Task<Void, Never>?

    init() {
        snapshot = UsageStore.load()
        LegacyTokenMirror.remove()
        // Kept off the poll loop because the authorization prompt blocks until the user answers.
        Task { await UsageNotifier.requestAuthorization() }
        poller = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refresh()
                try? await Task.sleep(for: Config.pollInterval)
            }
        }
    }

    deinit { poller?.cancel() }

    func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            var fresh = try await UsageFetcher.fetch()
            fresh.display = percentDisplay
            fresh.local = await localUsage(for: fresh)
            // Surface store failures too, otherwise the widget silently shows nothing.
            do { try UsageStore.save(fresh) }
            catch { fresh.error = "Snapshot not saved: \(error.localizedDescription)" }
            snapshot = fresh
            await UsageNotifier.evaluate(fresh)
        } catch {
            // Keep the last good numbers on screen and annotate them rather than blanking out.
            let previous = snapshot ?? UsageSnapshot(fetchedAt: .now, buckets: [])
            var annotated = UsageSnapshot(fetchedAt: previous.fetchedAt,
                                          buckets: previous.buckets,
                                          error: error.localizedDescription)
            annotated.display = percentDisplay
            // The logs need no credentials, so these numbers survive a failed fetch.
            annotated.local = await localUsage(for: previous)
            snapshot = annotated
            try? UsageStore.save(annotated)
        }
        // Rechecked every poll so flipping the switch in System Settings clears the notice.
        notificationsDenied = notificationsEnabled ? await UsageNotifier.isDenied() : false
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func localUsage(for snapshot: UsageSnapshot) async -> LocalUsage? {
        let resets = snapshot.buckets.first { $0.key == "five_hour" }?.resetsAt
        return await LocalUsageReader.shared.usage(sessionEndsAt: resets, now: .now)
    }
}
