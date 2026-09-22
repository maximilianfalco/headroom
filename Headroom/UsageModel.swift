import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var notificationsDenied = false
    @Published var provider = UsageModel.stored(UsageSource.self, "usageProvider") ?? .claude {
        didSet {
            guard provider != oldValue else { return }
            UserDefaults.standard.set(provider.rawValue, forKey: "usageProvider")
            menuBarLimit = UserDefaults.standard.string(forKey: menuBarLimitKey) ?? ""
            snapshot = UsageStore.load(provider: provider)
                ?? UsageSnapshot(fetchedAt: .now, buckets: [], provider: provider)
            republish()
            Task { await refresh() }
        }
    }
    @Published var notificationsEnabled = UsageNotifier.isEnabled {
        didSet { UsageNotifier.isEnabled = notificationsEnabled }
    }
    @Published var percentDisplay = UsageModel.stored(PercentDisplay.self, "percentDisplay") ?? .used {
        didSet {
            UserDefaults.standard.set(percentDisplay.rawValue, forKey: "percentDisplay")
            republish()
        }
    }
    /// Key of the limit the menu bar shows. Empty means whichever is highest.
    @Published var menuBarLimit = UserDefaults.standard.string(forKey: "menuBarLimit") ?? "" {
        didSet { UserDefaults.standard.set(menuBarLimit, forKey: menuBarLimitKey) }
    }
    private var menuBarLimitKey: String { provider == .claude ? "menuBarLimit" : "codexMenuBarLimit" }
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
        snapshot = UsageStore.load(provider: provider)
        menuBarLimit = UserDefaults.standard.string(forKey: menuBarLimitKey) ?? ""
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
        let source = provider
        isRefreshing = true
        defer {
            isRefreshing = false
            if provider != source { Task { await refresh() } }
        }

        do {
            var fresh: UsageSnapshot
            switch source {
            case .claude: fresh = try await UsageFetcher.fetch()
            case .codex: fresh = try await CodexUsageFetcher.fetch()
            }
            fresh.display = percentDisplay
            fresh.local = await localUsage(for: fresh)
            guard provider == source else { return }
            let samples = Projection.apply(to: &fresh, history: UsageStore.loadSamples(provider: source), now: .now)
            // The marker is an extra, so a history that cannot be kept only costs the projection.
            try? UsageStore.saveSamples(samples, provider: source)
            // Surface store failures too, otherwise the widget silently shows nothing.
            do { try UsageStore.save(fresh) }
            catch { fresh.error = "Snapshot not saved: \(error.localizedDescription)" }
            snapshot = fresh
            await UsageNotifier.evaluate(fresh)
        } catch {
            guard provider == source else { return }
            // Keep the last good numbers on screen and annotate them rather than blanking out.
            let previous = snapshot ?? UsageSnapshot(fetchedAt: .now, buckets: [], provider: source)
            var annotated = UsageSnapshot(fetchedAt: previous.fetchedAt,
                                          buckets: previous.buckets,
                                          error: error.localizedDescription, provider: source)
            annotated.display = percentDisplay
            // The logs need no credentials, so these numbers survive a failed fetch.
            annotated.local = await localUsage(for: previous)
            guard provider == source else { return }
            snapshot = annotated
            try? UsageStore.save(annotated)
        }
        // Rechecked every poll so flipping the switch in System Settings clears the notice.
        notificationsDenied = notificationsEnabled ? await UsageNotifier.isDenied() : false
        WidgetCenter.shared.reloadAllTimelines()
    }

    private func localUsage(for snapshot: UsageSnapshot) async -> LocalUsage? {
        if snapshot.source == .codex {
            let resets = snapshot.buckets.first { $0.windowDuration == Config.sessionWindow }?.resetsAt
            return await CodexLocalUsageReader.shared.usage(sessionEndsAt: resets, now: .now)
        }
        let resets = snapshot.buckets.first { $0.key == UsageBucket.sessionKey }?.resetsAt
        return await LocalUsageReader.shared.usage(sessionEndsAt: resets, now: .now)
    }
}
