import SwiftUI

/// Falling blocks settling into a heap. The heap is how much of your plan is gone, and a piece
/// is always on its way down so a settled level is still a moving picture.
struct BlocksSprite: View {
    var cell: CGFloat = 9
    var fill: Double = 0
    var motion: SpriteMotion = .follow

    var body: some View {
        SpriteCanvas(cell: cell, fill: fill, motion: motion, growSeconds: 2, draw: draw)
    }

    /// How long one piece takes to fall and be replaced.
    private static let dropSeconds: TimeInterval = 2.4

    /// Four cell pieces, as column and row offsets from the piece's top left.
    private static let pieces: [[(x: Int, y: Int)]] = [
        [(0, 0), (1, 0), (0, 1), (1, 1)],
        [(0, 0), (1, 0), (2, 0), (3, 0)],
        [(0, 0), (0, 1), (0, 2), (1, 2)],
        [(0, 0), (1, 0), (2, 0), (1, 1)],
        [(1, 0), (2, 0), (0, 1), (1, 1)],
    ]

    private func draw(_ frame: SpriteFrame) {
        let heap = heap(in: frame)
        drawHeap(heap, in: frame)
        drawFalling(over: heap, in: frame)
    }

    /// How many cells are stacked in each column. Uneven on purpose: a level top edge reads as
    /// a filled bar, and the whole point is that these are separate pieces.
    private func heap(in frame: SpriteFrame) -> [Int] {
        let level = SpriteNoise.clamp(frame.level)
        let full = level * Double(frame.rows)
        // The jitter fades out at both ends, so an empty heap is truly empty and a full one
        // does not poke through the ceiling.
        let ragged = 3.2 * sin(level * .pi)

        return (0..<frame.columns).map { column in
            let lean = (SpriteNoise.value(column / 2 &+ 5) - 0.5) * ragged
            return min(frame.rows, max(0, Int((full + lean).rounded())))
        }
    }

    private func drawHeap(_ heap: [Int], in frame: SpriteFrame) {
        for (column, height) in heap.enumerated() where height > 0 {
            for step in 0..<height {
                let row = frame.rows - 1 - step
                guard row >= 0 else { break }
                // A few trapped gaps, buried rather than scattered. Holes near the surface
                // read as speckle instead of as pieces that landed badly.
                let buried = step < height - 2
                if buried, SpriteNoise.value(column &* 13 &+ row &* 7) < 0.06 { continue }
                frame.paint(column, row, shade: shade(column: column, row: row))
            }
        }
    }

    /// Shading in two by two patches rather than per cell, so the heap reads as pieces that
    /// landed separately instead of as one wall. The spread is wide on purpose: at this size a
    /// subtle difference between patches just looks like noise.
    private func shade(column: Int, row: Int) -> Double {
        0.55 + 0.45 * SpriteNoise.value((column / 2) &* 31 &+ (row / 2) &* 17)
    }

    /// The piece on its way down. Which piece and which column are picked from the drop's
    /// number, so they hold still for the whole fall instead of flickering each frame.
    private func drawFalling(over heap: [Int], in frame: SpriteFrame) {
        let drop = Int(frame.time / Self.dropSeconds)
        let progress = frame.time.truncatingRemainder(dividingBy: Self.dropSeconds) / Self.dropSeconds

        let piece = Self.pieces[Int(SpriteNoise.value(drop &+ 3) * Double(Self.pieces.count))
            % Self.pieces.count]
        let span = (piece.map(\.x).max() ?? 0) + 1
        let tall = (piece.map(\.y).max() ?? 0) + 1
        let left = Int(SpriteNoise.value(drop &+ 11) * Double(max(1, frame.columns - span)))

        // Lands on the tallest column it covers, so it never sinks into the heap.
        let peak = (left..<min(frame.columns, left + span)).map { heap[$0] }.max() ?? 0
        let restingTop = frame.rows - peak - tall
        let top = Int((Double(-tall) + Double(restingTop + tall) * progress).rounded())

        for offset in piece {
            let row = top + offset.y
            guard row >= 0, row < frame.rows else { continue }
            frame.paint(left + offset.x, row, shade: 1)
        }
    }
}
