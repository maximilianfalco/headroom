import Foundation
import Testing

struct SpriteLevelTests {
    @Test("the demo sweep spends time at both ends and the middle")
    func sweepCoversTheRange() {
        #expect(isClose(SpriteLevel.demoSweep(at: 0), 0))
        #expect(isClose(SpriteLevel.demoSweep(at: 8), 1))
        #expect(isClose(SpriteLevel.demoSweep(at: 16), 0))
        #expect(isClose(SpriteLevel.demoSweep(at: 4), 0.5))
    }

    @Test("the sweep never leaves 0...1, however long it has been running")
    func sweepStaysInRange() {
        for step in 0..<200 {
            let level = SpriteLevel.demoSweep(at: Double(step) * 0.7)
            #expect(level >= 0 && level <= 1)
        }
    }

    @Test("growing in starts at nothing and lands on the level asked for")
    func easeInReachesTheTarget() {
        #expect(isClose(SpriteLevel.easedIn(0.8, grown: 0, over: 2), 0))
        #expect(isClose(SpriteLevel.easedIn(0.8, grown: 2, over: 2), 0.8))
        #expect(isClose(SpriteLevel.easedIn(0.8, grown: 99, over: 2), 0.8))
    }

    @Test("a negative elapsed time is treated as not started, not as overshoot")
    func easeInClampsNegativeTime() {
        #expect(isClose(SpriteLevel.easedIn(0.8, grown: -5, over: 2), 0))
    }

    @Test("demo sweeps shape and colour together, so a swept sprite still changes colour")
    func demoResolvesShapeAndColourAlike() {
        let shape = SpriteLevel.resolve(motion: .demo, fill: 0.93, grown: 99, growSeconds: 2, time: 5)
        let colour = SpriteLevel.resolve(motion: .demo, fill: 0.07, grown: 99, growSeconds: 2, time: 5)
        #expect(isClose(shape, colour))
    }

    @Test("demo ignores usage entirely")
    func demoIgnoresFill() {
        let atZero = SpriteLevel.resolve(motion: .demo, fill: 0, grown: 99, growSeconds: 2, time: 8)
        let atFull = SpriteLevel.resolve(motion: .demo, fill: 1, grown: 99, growSeconds: 2, time: 8)
        #expect(isClose(atZero, atFull))
        #expect(isClose(atZero, 1))
    }

    @Test("follow settles on usage and ignores the clock")
    func followTracksFill() {
        let early = SpriteLevel.resolve(motion: .follow, fill: 0.3, grown: 99, growSeconds: 2, time: 4)
        let later = SpriteLevel.resolve(motion: .follow, fill: 0.3, grown: 99, growSeconds: 2, time: 400)
        #expect(isClose(early, 0.3))
        #expect(isClose(later, 0.3))
    }
}

struct SpriteNoiseTests {
    @Test("the same seed always gives the same value, so sprites do not flicker")
    func valueIsStable() {
        #expect(SpriteNoise.value(42) == SpriteNoise.value(42))
        #expect(SpriteNoise.value(42) != SpriteNoise.value(43))
    }

    @Test(arguments: [0, 1, 7, 42, 999, -13])
    func valueStaysInRange(seed: Int) {
        let value = SpriteNoise.value(seed)
        #expect(value >= 0 && value < 1)
    }

    @Test(arguments: [0, 3, 9, 14, 27])
    func profileStaysInRange(column: Int) {
        let value = SpriteNoise.profile(column)
        #expect(value >= 0 && value <= 1)
    }

    @Test("no grit means neighbouring columns follow a smooth envelope")
    func profileWithoutGritIsSmooth() {
        let steps = (0..<10).map { SpriteNoise.profile($0, grit: 0) }
        let jumps = zip(steps, steps.dropFirst()).map { abs($1 - $0) }
        #expect(jumps.allSatisfy { $0 < 0.35 })
    }

    @Test("the base of a shape never leans, and the top leans most")
    func leanIsAnchoredAtTheBase() {
        let time = 4.0
        #expect(SpriteNoise.lean(time: time, row: 20, base: 20) == 0)
        let top = abs(SpriteNoise.lean(time: time, row: 0, base: 20))
        let middle = abs(SpriteNoise.lean(time: time, row: 15, base: 20))
        #expect(top >= middle)
    }

    @Test("lean is whole cells, so pixel art never lands on a half cell")
    func leanIsWholeCells() {
        for step in 0..<40 {
            let offset = SpriteNoise.lean(time: Double(step) * 0.3, row: 2, base: 20)
            #expect(offset == offset.rounded())
        }
    }

    @Test(arguments: [(-4.0, 0.0), (0.5, 0.5), (9.0, 1.0)])
    func clampBounds(input: Double, expected: Double) {
        #expect(SpriteNoise.clamp(input) == expected)
    }
}

struct SpriteKindTests {
    @Test("every sprite is offered, named and identified by itself")
    func everyKindIsUsable() {
        #expect(SpriteKind.allCases.count == 5)
        for kind in SpriteKind.allCases {
            #expect(!kind.label.isEmpty)
            #expect(kind.id == kind.rawValue)
        }
    }

    @Test("labels are distinct, so the picker cannot show the same name twice")
    func labelsAreDistinct() {
        let labels = SpriteKind.allCases.map(\.label)
        #expect(Set(labels).count == labels.count)
    }

    @Test(arguments: zip(SpriteKind.allCases, ["Plant", "Cave", "Water", "Hourglass", "Blocks"]))
    func labelReads(kind: SpriteKind, expected: String) {
        #expect(kind.label == expected)
    }
}
