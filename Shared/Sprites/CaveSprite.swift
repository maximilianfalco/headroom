import SwiftUI

/// Stalactites and stalagmites closing on each other. The gap between them is your headroom,
/// so the rock grows toward the middle as usage climbs and meets when you are out.
///
/// Note this one is nearly blank below about 40%, which is where most usage sits. Demo motion
/// exists largely so it can be seen at all.
struct CaveSprite: View {
    var cell: CGFloat = 9
    var fill: Double = 0
    var motion: SpriteMotion = .follow

    /// Rows of solid rock at the ceiling and the floor.
    private static let slab = 1

    var body: some View {
        SpriteCanvas(cell: cell, fill: fill, motion: motion, growSeconds: 1.6, draw: draw)
    }

    private func draw(_ frame: SpriteFrame) {
        let span = max(1, frame.rows - Self.slab * 2)

        for column in 0..<frame.columns {
            for row in 0..<Self.slab {
                frame.paint(column, row)
                frame.paint(column, frame.rows - 1 - row)
            }

            let (top, bottom) = spikes(column: column, span: span, fill: frame.level)
            for step in 0..<top {
                frame.paint(column, Self.slab + step, shade: taper(step, of: top))
            }
            for step in 0..<bottom {
                frame.paint(column, frame.rows - Self.slab - 1 - step,
                            shade: taper(step, of: bottom))
            }
        }

        dust(in: frame, span: span)
    }

    /// Splits one column's rock between the ceiling and the floor. Peaky on purpose: a linear
    /// profile makes every column grow together, which reads as a wall rather than formations.
    private func spikes(column: Int, span: Int, fill: Double) -> (top: Int, bottom: Int) {
        let ridge = 0.2 + 0.85 * pow(SpriteNoise.profile(column), 2.3)
        let hangs = 0.35 + 0.4 * SpriteNoise.value(column &+ 13)
        let reach = min(Double(span), fill * Double(span) * ridge)
        let top = Int((reach * hangs).rounded())
        let bottom = Int((reach * (1 - hangs)).rounded())
        // Never let the two sides pass through each other.
        guard top + bottom > span else { return (top, bottom) }
        let scaled = Int(Double(top) * Double(span) / Double(top + bottom))
        return (scaled, span - scaled)
    }

    /// Spikes fade over their last few pixels, which is what makes them read as tapering rock
    /// rather than as blunt bars.
    private func taper(_ step: Int, of length: Int) -> Double {
        guard length > 2 else { return 0.75 }
        switch length - step {
        case 1: return 0.3
        case 2: return 0.55
        case 3: return 0.8
        default: return 1
        }
    }

    /// Motes drifting down the gap, so an idle cave still has something moving in it.
    private func dust(in frame: SpriteFrame, span: Int) {
        for mote in 0..<4 {
            let column = Int(SpriteNoise.value(mote &+ 71) * Double(frame.columns))
            let speed = 1.4 + SpriteNoise.value(mote &+ 29) * 1.6
            let offset = SpriteNoise.value(mote &+ 53) * Double(span)
            let drift = (frame.time * speed + offset).truncatingRemainder(dividingBy: Double(span))
            frame.paint(column, Self.slab + Int(drift), shade: 0.35)
        }
    }
}
