import Foundation

/// Deterministic randomness for sprites. Never use a real random source: a sprite redraws ten
/// times a second, so anything that changes between frames flickers instead of holding still.
enum SpriteNoise {
    /// Stable pseudo-random value in 0...1 for any integer. Same input, same output, forever.
    static func value(_ seed: Int) -> Double {
        let scrambled = sin(Double(seed) * 12.9898) * 43758.5453
        return scrambled - scrambled.rounded(.down)
    }

    /// A smooth wave across columns times per column grit. Multiplying rather than adding gives
    /// clusters with individual sizes, instead of one evenly lumpy mass.
    static func profile(_ column: Int, grit: Double = 0.7) -> Double {
        let envelope = (sin(Double(column) * 0.7 + 1.1) + sin(Double(column) * 0.29 + 0.4)) / 4 + 0.5
        return clamp(envelope * ((1 - grit) + grit * value(column)))
    }

    /// A whole cell sideways lean, strongest at the top and none at the base. One phase for the
    /// whole shape: giving each row its own phase shears it apart instead of bending it.
    static func lean(time: TimeInterval, row: Int, base: Int, amount: Double = 1.6) -> CGFloat {
        let height = Double(max(0, base - row)) / Double(max(1, base))
        return CGFloat((sin(time * 1.1) * amount * height * height).rounded())
    }

    static func clamp(_ value: Double, to range: ClosedRange<Double> = 0...1) -> Double {
        min(range.upperBound, max(range.lowerBound, value))
    }
}
