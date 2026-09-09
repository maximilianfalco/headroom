import SwiftUI

/// Water rising up the column as usage climbs. Full means you are out of room.
///
/// Two waves of different speed and wavelength cross the surface, so it never settles into one
/// repeating ripple. Reads well at any level, since even a shallow puddle still moves.
struct WaterSprite: View {
    var cell: CGFloat = 9
    var fill: Double = 0
    var danger: Double?
    var motion: SpriteMotion = .follow

    var body: some View {
        SpriteCanvas(cell: cell, fill: fill, danger: danger, motion: motion, growSeconds: 2, draw: draw)
    }

    private func draw(_ frame: SpriteFrame) {
        let depth = SpriteNoise.clamp(frame.level) * Double(frame.rows - 1)

        for column in 0..<frame.columns {
            let surface = frame.rows - Int((depth + wave(column: column, time: frame.time)).rounded())
            guard surface < frame.rows else { continue }
            let crest = max(0, surface)

            for row in crest..<frame.rows {
                // The crest is bright and the body behind it is not, which is what reads as a
                // waterline rather than as a filled rectangle.
                frame.paint(column, row, shade: row == crest ? 1 : 0.62)
            }
        }

        bubbles(in: frame, depth: depth)
        floor(in: frame)
    }

    /// Two sines with different wavelengths and drift directions. One alone looks mechanical.
    private func wave(column: Int, time: TimeInterval) -> Double {
        sin(Double(column) * 0.55 + time * 1.5) * 1.1
            + sin(Double(column) * 0.23 - time * 0.85) * 0.6
    }

    /// A few bubbles rising through whatever water there is, so a still level is not a still
    /// picture. They are skipped entirely when there is nothing to rise through.
    private func bubbles(in frame: SpriteFrame, depth: Double) {
        guard depth >= 3 else { return }
        for bubble in 0..<3 {
            let column = Int(SpriteNoise.value(bubble &+ 17) * Double(frame.columns))
            let speed = 1.1 + SpriteNoise.value(bubble &+ 41) * 1.3
            let offset = SpriteNoise.value(bubble &+ 83) * depth
            let risen = (frame.time * speed + offset).truncatingRemainder(dividingBy: depth)
            frame.paint(column, frame.rows - 1 - Int(risen), shade: 0.3)
        }
    }

    /// A dotted bed, so an empty column still shows where the water would go.
    private func floor(in frame: SpriteFrame) {
        for column in stride(from: 0, to: frame.columns, by: 2) {
            frame.paint(column, frame.rows - 1, shade: 0.22)
        }
    }
}
