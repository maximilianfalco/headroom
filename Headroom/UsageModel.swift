import Foundation
import SwiftUI
import WidgetKit

@MainActor
final class UsageModel: ObservableObject {
    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var needsReconnect = false
    @Published private(set) var notificationsDenied = false
    @Published var notificationsEnabled = UsageNotifier.isEnabled {
        didSet { UsageNotifier.isEnabled = notificationsEnabled }
    }

    private var poller: Task<Void, Never>?

    init() {
        snapshot = UsageStore.load()
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

    /// `allowPrompt` is only ever true for a refresh the user asked for, since reading Claude
    /// Code's keychain item can put a dialog on screen.
    func refresh(allowPrompt: Bool = false) async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }

        do {
            var fresh = try await UsageFetcher.fetch(allowPrompt: allowPrompt)
            fresh.local = await localUsage(for: fresh)
            // Surface store failures too, otherwise the widget silently shows nothing.
            do { try UsageStore.save(fresh) }
            catch { fresh.error = "Snapshot not saved: \(error.localizedDescription)" }
            snapshot = fresh
            needsReconnect = false
            await UsageNotifier.evaluate(fresh)
        } catch {
            needsReconnect = (error as? UsageError) == .needsReconnect
            // Keep the last good numbers on screen and annotate them rather than blanking out.
            let previous = snapshot ?? UsageSnapshot(fetchedAt: .now, buckets: [])
            var annotated = UsageSnapshot(fetchedAt: previous.fetchedAt,
                                          buckets: previous.buckets,
                                          error: error.localizedDescription)
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
