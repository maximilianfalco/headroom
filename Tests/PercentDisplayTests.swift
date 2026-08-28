import Foundation
import Testing

struct PercentDisplayTests {
    private func bucket(_ percent: Int) -> UsageBucket {
        UsageBucket(key: "k", label: "Session", percent: percent, resetsAt: nil)
    }

    @Test("used shows the number the API gave us")
    func usedIsVerbatim() {
        #expect(bucket(28).shown(.used) == 28)
    }

    @Test("remaining shows what is left of the hundred")
    func remainingIsTheComplement() {
        #expect(bucket(28).shown(.remaining) == 72)
    }

    @Test(arguments: [0, 7, 50, 93, 100])
    func thePairAlwaysSumsToAHundred(percent: Int) {
        let b = bucket(percent)
        #expect(b.shown(.used) + b.shown(.remaining) == 100)
    }

    @Test("a limit past its cap does not show negative headroom")
    func overCapClampsToZero() {
        #expect(bucket(140).shown(.remaining) == 0)
    }

    @Test("only remaining carries the word, since a bare number reads as used")
    func text() {
        #expect(bucket(28).shownText(.used) == "28%")
        #expect(bucket(28).shownText(.remaining) == "72% left")
    }

    @Test("colour keeps meaning danger, so it ignores which number is on screen")
    func severityIgnoresTheDisplay() {
        #expect(bucket(7).severity == .normal)
        #expect(bucket(97).severity == .critical)
    }

    @Test("a snapshot written before this setting existed still decodes")
    func decodesWithoutDisplay() throws {
        let json = #"{"fetchedAt":0,"buckets":[]}"#
        let decoded = try JSONDecoder().decode(UsageSnapshot.self, from: Data(json.utf8))
        #expect(decoded.display == nil)
    }

    @Test("the widget reads the setting off the snapshot, so it has to survive a round trip")
    func displaySurvivesTheSnapshot() throws {
        var snapshot = UsageSnapshot(fetchedAt: .now, buckets: [bucket(40)])
        snapshot.display = .remaining
        let data = try JSONEncoder().encode(snapshot)
        #expect(try JSONDecoder().decode(UsageSnapshot.self, from: data).display == .remaining)
    }

    @Test("an absent setting reads as used, so nothing changes for an existing install")
    func defaultsToUsed() {
        #expect(UsageSnapshot(fetchedAt: .now, buckets: []).display ?? .used == .used)
    }
}
