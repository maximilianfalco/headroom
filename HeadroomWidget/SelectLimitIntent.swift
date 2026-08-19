import AppIntents

/// A plain string parameter rather than an AppEntity: picking one of a few labels does not
/// need entity resolution, and the round trip through EntityQuery is a failure point.
struct LimitOptions: DynamicOptionsProvider {
    func results() async throws -> [String] {
        let buckets = UsageStore.load()?.buckets ?? UsageSnapshot.placeholder.buckets
        return buckets.map(\.label)
    }
}

struct SelectLimitIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Select Limit" }
    static var description: IntentDescription {
        IntentDescription("Choose which limit to show. Leave empty to track whichever is highest.")
    }

    @Parameter(title: "Limit", optionsProvider: LimitOptions())
    var limit: String?
}
