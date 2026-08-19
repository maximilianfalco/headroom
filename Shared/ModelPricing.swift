import Foundation

struct ModelRate {
    let input: Double
    let output: Double

    static func perMillion(_ input: Double, _ output: Double) -> ModelRate {
        ModelRate(input: input / 1_000_000, output: output / 1_000_000)
    }
}

/// List prices, so the cost shown is what the same work would bill on the API. A plan
/// subscription is flat rate, so treat it as a size, not an invoice.
enum ModelPricing {
    /// Cache writes bill off the input rate, and the hour TTL costs more than the five minute
    /// one. Claude Code writes almost entirely at the hour TTL, so collapsing the two
    /// underprices a session badly.
    private static let write5mRate = 1.25
    private static let write1hRate = 2.0
    private static let readRate = 0.1

    private static let standard: [String: ModelRate] = [
        "claude-fable-5": .perMillion(10, 50),
        "claude-mythos-5": .perMillion(10, 50),
        "claude-opus-5": .perMillion(5, 25),
        "claude-opus-4-8": .perMillion(5, 25),
        "claude-opus-4-7": .perMillion(5, 25),
        "claude-opus-4-6": .perMillion(5, 25),
        "claude-sonnet-5": .perMillion(3, 15),
        "claude-sonnet-4-6": .perMillion(3, 15),
        "claude-haiku-4-5": .perMillion(1, 5),
    ]

    /// Fast mode runs Opus at a premium tier, so the same model bills at twice the rate.
    private static let fast: [String: ModelRate] = [
        "claude-opus-5": .perMillion(10, 50),
        "claude-opus-4-8": .perMillion(10, 50),
    ]

    /// Unknown models fall back to their family rather than to free, so a model released
    /// after this table was written is priced approximately instead of silently at zero.
    static func rate(model: String, fastMode: Bool) -> ModelRate? {
        if fastMode, let rate = fast[model] { return rate }
        if let rate = standard[model] { return rate }
        if model.contains("fable") || model.contains("mythos") { return .perMillion(10, 50) }
        if model.contains("opus") { return .perMillion(5, 25) }
        if model.contains("sonnet") { return .perMillion(3, 15) }
        if model.contains("haiku") { return .perMillion(1, 5) }
        return nil
    }

    static func cost(model: String, fastMode: Bool, input: Int, output: Int,
                     cacheWrite5m: Int, cacheWrite1h: Int, cacheRead: Int) -> Double {
        guard let rate = rate(model: model, fastMode: fastMode) else { return 0 }
        return Double(input) * rate.input
            + Double(output) * rate.output
            + Double(cacheWrite5m) * rate.input * write5mRate
            + Double(cacheWrite1h) * rate.input * write1hRate
            + Double(cacheRead) * rate.input * readRate
    }
}
