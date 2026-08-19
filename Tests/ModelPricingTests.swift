import Testing

struct ModelPricingTests {
    @Test(arguments: [
        ("claude-fable-5", false, 10.0, 50.0),
        ("claude-mythos-5", false, 10.0, 50.0),
        ("claude-opus-5", false, 5.0, 25.0),
        ("claude-opus-4-8", false, 5.0, 25.0),
        ("claude-sonnet-5", false, 3.0, 15.0),
        ("claude-haiku-4-5", false, 1.0, 5.0),
        ("claude-opus-5", true, 10.0, 50.0),
        ("claude-opus-4-8", true, 10.0, 50.0),
    ])
    func tableRates(model: String, fast: Bool, input: Double, output: Double) {
        let rate = ModelPricing.rate(model: model, fastMode: fast)
        #expect(rate?.input == input / 1_000_000)
        #expect(rate?.output == output / 1_000_000)
    }

    @Test("fast mode falls back to the standard rate for models without a premium tier")
    func fastFallsBackWhenNoPremiumTier() {
        #expect(ModelPricing.rate(model: "claude-sonnet-5", fastMode: true)?.output == 15.0 / 1_000_000)
    }

    @Test(arguments: [
        ("claude-fable-6-future", 10.0),
        ("some-mythos-thing", 10.0),
        ("claude-opus-9", 5.0),
        ("claude-sonnet-9", 3.0),
        ("claude-haiku-9", 1.0),
    ])
    func unknownModelsFallBackToTheirFamily(model: String, input: Double) {
        #expect(ModelPricing.rate(model: model, fastMode: false)?.input == input / 1_000_000)
    }

    @Test(arguments: ["<synthetic>", "", "gpt-5", "gemini-3"])
    func unpricedModelsHaveNoRate(model: String) {
        #expect(ModelPricing.rate(model: model, fastMode: false) == nil)
    }

    @Test("an unpriced model costs nothing, however many tokens it used")
    func unpricedModelCostsZero() {
        let cost = ModelPricing.cost(model: "<synthetic>", fastMode: false, input: 1_000_000,
                                     output: 1_000_000, cacheWrite5m: 1_000_000,
                                     cacheWrite1h: 1_000_000, cacheRead: 1_000_000)
        #expect(cost == 0)
    }

    @Test("input and output bill at the model's own rates")
    func inputAndOutputRates() {
        let cost = ModelPricing.cost(model: "claude-opus-5", fastMode: false, input: 1_000_000,
                                     output: 1_000_000, cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 0)
        #expect(isClose(cost, 30.0))
    }

    @Test("the hour cache TTL bills at twice input, the five minute one at 1.25x")
    func cacheWriteTTLsAreNotInterchangeable() {
        let hour = ModelPricing.cost(model: "claude-opus-5", fastMode: false, input: 0, output: 0,
                                     cacheWrite5m: 0, cacheWrite1h: 1_000_000, cacheRead: 0)
        let fiveMinute = ModelPricing.cost(model: "claude-opus-5", fastMode: false, input: 0, output: 0,
                                           cacheWrite5m: 1_000_000, cacheWrite1h: 0, cacheRead: 0)
        #expect(isClose(hour, 10.0))
        #expect(isClose(fiveMinute, 6.25))
    }

    @Test("cache reads bill at a tenth of input")
    func cacheReadRate() {
        let cost = ModelPricing.cost(model: "claude-opus-5", fastMode: false, input: 0, output: 0,
                                     cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 10_000_000)
        #expect(isClose(cost, 5.0))
    }

    @Test("fast mode doubles the bill for the same work")
    func fastModeDoublesCost() {
        let standard = ModelPricing.cost(model: "claude-opus-5", fastMode: false, input: 1_000,
                                         output: 2_000, cacheWrite5m: 3_000, cacheWrite1h: 4_000,
                                         cacheRead: 5_000)
        let fast = ModelPricing.cost(model: "claude-opus-5", fastMode: true, input: 1_000,
                                     output: 2_000, cacheWrite5m: 3_000, cacheWrite1h: 4_000,
                                     cacheRead: 5_000)
        #expect(isClose(fast, standard * 2))
    }

    @Test("every token kind adds to the total")
    func allKindsSum() {
        let cost = ModelPricing.cost(model: "claude-opus-5", fastMode: false, input: 1_000_000,
                                     output: 1_000_000, cacheWrite5m: 1_000_000,
                                     cacheWrite1h: 1_000_000, cacheRead: 1_000_000)
        #expect(isClose(cost, 5.0 + 25.0 + 6.25 + 10.0 + 0.5))
    }

    @Test("no tokens, no cost")
    func zeroTokensCostNothing() {
        #expect(ModelPricing.cost(model: "claude-opus-5", fastMode: false, input: 0, output: 0,
                                  cacheWrite5m: 0, cacheWrite1h: 0, cacheRead: 0) == 0)
    }
}
