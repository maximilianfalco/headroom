import Foundation

enum CodexModelPricing {
    private static let standard: [String: ModelRate] = [
        "gpt-6-astra": .perMillion(10, 50),
        "gpt-5.6-sol": .perMillion(4, 20),
        "gpt-5.6-terra": .perMillion(2, 12),
        "gpt-5.6-luna": .perMillion(0.2, 1.2),
        "gpt-5.5": .perMillion(5, 30),
        "gpt-5.4": .perMillion(2.5, 15),
    ]

    static func cost(model: String, input: Int, cached: Int, cacheWrite: Int, output: Int) -> Double? {
        guard let key = standard.keys.first(where: { model == $0 || model.hasPrefix($0 + "-202") }),
              let rate = standard[key] else { return nil }
        let inputScale = input > 272_000 ? 2.0 : 1.0
        let outputScale = input > 272_000 ? 1.5 : 1.0
        return (Double(input - cached - cacheWrite) + Double(cached) * 0.1 + Double(cacheWrite) * 1.25)
            * rate.input * inputScale + Double(output) * rate.output * outputScale
    }
}
