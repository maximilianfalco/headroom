import SwiftUI

/// An hourglass draining as usage climbs. Sand still in the top is the room you have left, the
/// pile below is what you have spent.
///
/// The glass is drawn dim and the sand bright, so the shape reads at a glance and the sand is
/// what your eye lands on.
struct HourglassSprite: View {
    var cell: CGFloat = 9
    var fill: Double = 0
    var motion: SpriteMotion = .follow

    var body: some View {
        SpriteCanvas(cell: cell, fill: fill, motion: motion, growSeconds: 2, draw: draw)
    }

    private func draw(_ frame: SpriteFrame) {
        let glass = Glass(frame: frame)
        let level = SpriteNoise.clamp(frame.level)

        glass.drawTo(frame)
        topSand(in: frame, glass: glass, left: 1 - level)
        pile(in: frame, glass: glass, level: level)
        if level < 0.98 { grain(in: frame, glass: glass) }
    }

    /// The vessel. Two funnels meeting at a neck, capped top and bottom.
    private struct Glass {
        let centre: Double
        let neckRow: Int
        let maxHalf: Double
        let rows: Int
        let neckHalf = 0.6

        init(frame: SpriteFrame) {
            centre = Double(frame.columns - 1) / 2
            rows = frame.rows
            neckRow = (frame.rows - 1) / 2
            maxHalf = Double(frame.columns) / 2 * 0.86
        }

        /// Half the vessel's width at this row: widest at the caps, pinched at the neck.
        func half(at row: Int) -> Double {
            let waist = Double(rows - 1) / 2
            let fromNeck = abs(Double(row) - waist) / max(1, waist)
            return neckHalf + (maxHalf - neckHalf) * fromNeck
        }

        /// The columns sand may occupy on this row.
        func inside(at row: Int) -> ClosedRange<Int>? {
            let half = self.half(at: row) - 1
            guard half >= 0 else { return nil }
            let from = Int((centre - half).rounded())
            let to = Int((centre + half).rounded())
            return from <= to ? from...to : nil
        }

        func drawTo(_ frame: SpriteFrame) {
            for row in 0..<rows {
                let half = self.half(at: row)
                for side in [-1.0, 1.0] {
                    let column = Int((centre + side * half).rounded())
                    guard column >= 0, column < frame.columns else { continue }
                    frame.paint(column, row, shade: 0.34)
                }
            }
            for row in [0, rows - 1] {
                let half = self.half(at: row)
                let from = max(0, Int((centre - half).rounded()))
                let to = min(frame.columns - 1, Int((centre + half).rounded()))
                guard from <= to else { continue }
                for column in from...to { frame.paint(column, row, shade: 0.34) }
            }
        }
    }

    /// Sand still to fall. It rests on the funnel, so its surface drops as the glass drains.
    private func topSand(in frame: SpriteFrame, glass: Glass, left: Double) {
        guard left > 0.01 else { return }
        let surface = Double(glass.neckRow) - left * Double(glass.neckRow - 1)
        for row in Int(surface.rounded())...glass.neckRow {
            guard row >= 1, let inside = glass.inside(at: row) else { continue }
            for column in inside { frame.paint(column, row, shade: 0.8) }
        }
    }

    /// Sand already spent. Heaped, because a flat top would read as water rather than grains.
    private func pile(in frame: SpriteFrame, glass: Glass, level: Double) {
        guard level > 0.01 else { return }
        let floor = glass.rows - 2
        let room = Double(floor - glass.neckRow)
        let crest = Double(floor) - level * room

        for row in Int(crest.rounded())...floor {
            guard row > glass.neckRow, let inside = glass.inside(at: row) else { continue }
            for column in inside {
                // The heap peaks in the middle, so its edges sit a little lower.
                let fromCentre = abs(Double(column) - glass.centre) / max(1, glass.maxHalf)
                guard Double(row) >= crest + fromCentre * 1.8 else { continue }
                frame.paint(column, row, shade: 1)
            }
        }
    }

    /// The falling stream, so a settled level is still a moving picture.
    private func grain(in frame: SpriteFrame, glass: Glass) {
        let column = Int(glass.centre.rounded())
        let drop = glass.rows - 2 - glass.neckRow
        guard drop > 0 else { return }
        for grain in 0..<2 {
            let start = SpriteNoise.value(grain &+ 31) * Double(drop)
            let fallen = (frame.time * 6 + start).truncatingRemainder(dividingBy: Double(drop))
            frame.paint(column, glass.neckRow + 1 + Int(fallen), shade: 0.72)
        }
    }
}
