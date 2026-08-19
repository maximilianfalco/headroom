import AppIntents
import SwiftUI
import WidgetKit

struct UsageEntry: TimelineEntry {
    let date: Date
    let snapshot: UsageSnapshot?
    let selectedLabel: String?
}

struct UsageProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: .now, snapshot: UsageStore.load() ?? .placeholder, selectedLabel: nil)
    }

    func snapshot(for configuration: SelectLimitIntent, in context: Context) async -> UsageEntry {
        UsageEntry(date: .now, snapshot: UsageStore.load() ?? .placeholder,
                   selectedLabel: configuration.limit)
    }

    func timeline(for configuration: SelectLimitIntent, in context: Context) async -> Timeline<UsageEntry> {
        let entry = UsageEntry(date: .now, snapshot: UsageStore.load(),
                               selectedLabel: configuration.limit)
        // The app pushes reloads after each fetch, so this is only a safety net.
        return Timeline(entries: [entry], policy: .after(.now.addingTimeInterval(Config.widgetFallbackRefresh)))
    }
}

struct HeadroomWidgetView: View {
    @Environment(\.widgetFamily) private var family
    let entry: UsageEntry

    var body: some View {
        if let snapshot = entry.snapshot, !snapshot.buckets.isEmpty {
            switch family {
            case .systemSmall: small(snapshot)
            case .systemLarge: large(snapshot)
            default: medium(snapshot)
            }
        } else {
            UsageUnavailable(message: entry.snapshot?.error ?? "Open Headroom to sign in")
        }
    }

    /// Falls back to the highest limit when nothing is configured or the choice has gone away.
    private func focused(_ snapshot: UsageSnapshot) -> UsageBucket? {
        snapshot.buckets.first { $0.label == entry.selectedLabel } ?? snapshot.worst
    }

    @ViewBuilder
    private func small(_ snapshot: UsageSnapshot) -> some View {
        if let bucket = focused(snapshot) {
            VStack(spacing: 8) {
                UsageRing(bucket: bucket)
                    .frame(width: 78, height: 78)
                VStack(spacing: 1) {
                    Text(bucket.label)
                        .font(.system(size: 11, weight: .medium))
                    if let resets = bucket.resetsIn {
                        Text("resets in \(resets)")
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func medium(_ snapshot: UsageSnapshot) -> some View {
        // Honour the selection here too by leading with it, rather than ignoring it.
        let selected = snapshot.buckets.first { $0.label == entry.selectedLabel }
        let ordered = selected.map { first in
            [first] + snapshot.buckets.filter { $0.label != first.label }
        } ?? snapshot.buckets

        VStack(alignment: .leading, spacing: 9) {
            Text(selected?.label.uppercased() ?? "HEADROOM")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.tertiary)
                .tracking(0.8)
            ForEach(ordered.prefix(4)) { UsageBar(bucket: $0) }
            Spacer(minLength: 0)
        }
    }

    /// Leads with the focused limit as a ring, then lists the others. The focused one is left
    /// out of the list rather than drawn twice.
    @ViewBuilder
    private func large(_ snapshot: UsageSnapshot) -> some View {
        let hero = focused(snapshot)
        let rest = snapshot.buckets.filter { $0.label != hero?.label }

        VStack(alignment: .leading, spacing: 14) {
            if let hero {
                HStack(spacing: 14) {
                    UsageRing(bucket: hero, lineWidth: 9)
                        .frame(width: 84, height: 84)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(hero.label)
                            .font(.system(size: 15, weight: .semibold))
                        if let resets = hero.resetsIn {
                            Text("resets in \(resets)")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer(minLength: 0)
                }
            }

            if !rest.isEmpty {
                Divider()
                VStack(spacing: 12) {
                    ForEach(rest) { UsageBar(bucket: $0) }
                }
            }

            Spacer(minLength: 0)
            UsageFooter(snapshot: snapshot)
        }
    }
}

struct HeadroomWidget: Widget {
    var body: some WidgetConfiguration {
        // Renamed from HeadroomWidget: instances placed under the old StaticConfiguration
        // cannot migrate to an intent config, so a new kind retires them cleanly.
        AppIntentConfiguration(kind: Config.widgetKind,
                               intent: SelectLimitIntent.self,
                               provider: UsageProvider()) { entry in
            HeadroomWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Headroom")
        .description("Current usage against your Claude plan limits.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

@main
struct HeadroomWidgetBundle: WidgetBundle {
    var body: some Widget { HeadroomWidget() }
}
