import SwiftUI

/// Falling blocks piling into a heap, tetris style. The heap height is how much of your plan
/// is gone: pieces land and stack for real, and the bottom row clears when it grows too tall.
struct BlocksSprite: View {
    var cell: CGFloat = 9
    var fill: Double = 0
    var danger: Double?
    var motion: SpriteMotion = .follow

    @State private var board = BlocksBoard()

    var body: some View {
        SpriteCanvas(cell: cell, fill: fill, danger: danger, motion: motion, growSeconds: 2) { frame in
            board.draw(frame)
        }
    }
}

/// The running game. Landed pieces have to survive between frames, which per frame noise
/// cannot do, so this one sprite keeps a board. Every pick still comes from SpriteNoise.
private final class BlocksBoard {
    /// One gravity tick: the falling piece drops one cell.
    private static let stepSeconds: TimeInterval = 0.18
    private static let flashSeconds: TimeInterval = 0.45

    private static let oBlock: [(x: Int, y: Int)] = [(0, 0), (1, 0), (0, 1), (1, 1)]
    private static let iBeam: [(x: Int, y: Int)] = [(0, 0), (1, 0), (2, 0), (3, 0)]
    private static let iPost: [(x: Int, y: Int)] = [(0, 0), (0, 1), (0, 2), (0, 3)]
    private static let dot: [(x: Int, y: Int)] = [(0, 0)]
    private static let tee: [(x: Int, y: Int)] = [(0, 0), (1, 0), (2, 0), (1, 1)]
    private static let ess: [(x: Int, y: Int)] = [(1, 0), (2, 0), (0, 1), (1, 1)]
    private static let zed: [(x: Int, y: Int)] = [(0, 0), (1, 0), (1, 1), (2, 1)]
    private static let jay: [(x: Int, y: Int)] = [(0, 0), (1, 0), (2, 0), (0, 1)]
    private static let ell: [(x: Int, y: Int)] = [(0, 0), (1, 0), (2, 0), (2, 1)]

    private var columns = 0
    private var rows = 0
    /// Shade per cell, row 0 at the top. Zero means empty.
    private var cells: [[Double]] = []

    private var shape: [(x: Int, y: Int)] = []
    private var left = 0
    private var top = 0
    private var seed = 0

    private var program: [(shape: [(x: Int, y: Int)], column: Int)] = []
    private var programStep = 0
    private var cycle = 0

    private var stepAt: TimeInterval = 0
    private var flashUntil: TimeInterval?
    private var grewAt: TimeInterval = 0
    private var rowKey = 0

    func draw(_ frame: SpriteFrame) {
        let target = SpriteNoise.clamp(frame.level) * Double(frame.rows)
        prepare(frame, target: target)
        advance(to: frame.time, target: target)

        let flashing = (flashUntil ?? 0) > frame.time
        for (row, line) in cells.enumerated() {
            for (column, shade) in line.enumerated() where shade > 0 {
                frame.paint(column, row, shade: flashing && row == rows - 1 ? 1 : shade)
            }
        }
        for offset in shape {
            let row = top + offset.y
            guard row >= 0, row < rows else { continue }
            frame.paint(left + offset.x, row, shade: 1)
        }
    }

    /// Builds a fresh board at the current level. Runs once, and again if the canvas resizes.
    private func prepare(_ frame: SpriteFrame, target: Double) {
        guard frame.columns != columns || frame.rows != rows else { return }
        columns = frame.columns
        rows = frame.rows
        cells = (0..<rows).map { row in
            Double(rows - row) <= target ? packedRow() : .init(repeating: 0, count: columns)
        }
        program = []
        programStep = 0
        spawn()
        stepAt = frame.time + Self.stepSeconds
    }

    private func advance(to time: TimeInterval, target: Double) {
        // A long gap means the panel was away. Skip ahead rather than replay it all.
        if time - stepAt > 3 { stepAt = time }
        while stepAt <= time {
            step(at: stepAt, target: target)
            stepAt += Self.stepSeconds
        }
    }

    private func step(at now: TimeInterval, target: Double) {
        if let flash = flashUntil {
            guard now >= flash else { return }
            flashUntil = nil
            cells.remove(at: rows - 1)
            cells.insert(.init(repeating: 0, count: columns), at: 0)
        }

        var filled = 0
        for line in cells { for shade in line where shade > 0 { filled += 1 } }
        let height = Double(filled) / Double(columns)

        // Usage jumped up: push full rows in from below, faster than pieces could pile.
        if height < target - 1.4, now - grewAt > 0.25 {
            grewAt = now
            cells.removeFirst()
            cells.append(packedRow())
        }

        // The heap outgrew the level, so the bottom row goes, tetris style.
        if flashUntil == nil, height > target + 0.6, bottomRowFull {
            flashUntil = now + (height > target + 3 ? 0.15 : Self.flashSeconds)
        }

        if canDrop {
            top += 1
        } else {
            land()
            spawn()
        }
    }

    private var bottomRowFull: Bool {
        cells[rows - 1].allSatisfy { $0 > 0 }
    }

    private var canDrop: Bool {
        shape.allSatisfy { offset in
            let row = top + offset.y + 1
            let column = left + offset.x
            guard row < rows, column < columns else { return false }
            return row < 0 || cells[row][column] == 0
        }
    }

    private func land() {
        let shade = 0.55 + 0.45 * SpriteNoise.value(seed &* 29)
        for offset in shape {
            let row = top + offset.y
            let column = left + offset.x
            guard row >= 0, row < rows, column < columns else { continue }
            cells[row][column] = shade
        }
    }

    /// The next drop in the pattern. No aiming: the pattern already lands every piece flush.
    private func spawn() {
        if programStep >= program.count {
            cycle += 1
            program = buildCycle()
            programStep = 0
        }
        seed += 1
        (shape, left) = program[programStep]
        programStep += 1
        top = -((shape.map(\.y).max() ?? 0) + 1)
    }

    private typealias Drop = (shape: [(x: Int, y: Int)], column: Int)

    /// One loop of the pattern: four rows of chunk recipes. Chunks build in a shuffled
    /// order, so the board fills organically instead of sweeping left to right.
    private func buildCycle() -> [Drop] {
        guard columns > 1 else { return [(Self.iPost, 0)] }
        var chunks: [[Drop]] = []
        var x = 0
        while x < columns {
            let remaining = columns - x
            let widths = [2, 3, 3, 4].filter { $0 <= remaining && remaining - $0 != 1 }
            let width = widths[Int(SpriteNoise.value(cycle &* 37 &+ x &* 7)
                * Double(widths.count)) % widths.count]
            chunks.append(chunkDrops(width: width, at: x))
            x += width
        }

        var order = Array(chunks.indices)
        for index in order.indices.reversed() where index > 0 {
            order.swapAt(index, Int(SpriteNoise.value(cycle &* 97 &+ index &* 41)
                * Double(index + 1)) % (index + 1))
        }

        var drops: [Drop] = []
        var cursor = [Int](repeating: 0, count: chunks.count)
        let total = chunks.reduce(0) { $0 + $1.count }
        while drops.count < total {
            for index in order where cursor[index] < chunks[index].count {
                drops.append(chunks[index][cursor[index]])
                cursor[index] += 1
            }
        }
        return drops
    }

    /// Fills width x 4 for one cycle: usually two stacked layer recipes, sometimes one tall
    /// pillar pair or striped slab, so the skyline varies while every chunk still ends flat.
    private func chunkDrops(width: Int, at x: Int) -> [Drop] {
        if SpriteNoise.value(cycle &* 61 &+ x &* 13) < 0.22 {
            switch width {
            case 2: return [(Self.iPost, x), (Self.iPost, x + 1)]
            case 4: return (0..<4).map { _ in (Self.iBeam, x) }
            default: break
            }
        }
        return layer(width: width, at: x, pick: cycle &* 53 &+ x &* 11)
            + layer(width: width, at: x, pick: cycle &* 53 &+ x &* 11 &+ 1009)
    }

    /// A recipe that fills width x 2 with no holes and ends flat. Dots prep a ledge or a
    /// notch, then a T, S, Z, J or L drops in flush, so every line still completes.
    private func layer(width: Int, at x: Int, pick: Int) -> [Drop] {
        let roll = SpriteNoise.value(pick)
        switch width {
        case 2:
            return roll < 0.6
                ? [(Self.oBlock, x)]
                : [(Self.dot, x), (Self.dot, x + 1), (Self.dot, x), (Self.dot, x + 1)]
        case 3:
            switch Int(roll * 5) % 5 {
            case 0: return [(Self.dot, x), (Self.dot, x + 2), (Self.tee, x)]
            case 1: return [(Self.dot, x + 2), (Self.ess, x), (Self.dot, x)]
            case 2: return [(Self.dot, x), (Self.zed, x), (Self.dot, x + 2)]
            case 3: return [(Self.dot, x + 1), (Self.dot, x + 2), (Self.jay, x)]
            default: return [(Self.dot, x), (Self.dot, x + 1), (Self.ell, x)]
            }
        default:
            switch Int(roll * 3) % 3 {
            case 0: return [(Self.iBeam, x), (Self.iBeam, x)]
            case 1: return [(Self.oBlock, x), (Self.oBlock, x + 2)]
            default: return [(Self.dot, x), (Self.dot, x + 3), (Self.oBlock, x + 1),
                             (Self.dot, x), (Self.dot, x + 3)]
            }
        }
    }

    /// A full row shaded in short runs, so it reads as pieces packed tight, not one slab.
    private func packedRow() -> [Double] {
        rowKey += 1
        var shades = [Double](repeating: 0, count: columns)
        var x = 0
        var run = 0
        while x < columns {
            let width = 2 + Int(SpriteNoise.value(rowKey &* 91 &+ run &* 13) * 3)
            let shade = 0.55 + 0.45 * SpriteNoise.value(rowKey &* 57 &+ run &* 23)
            for column in x..<min(columns, x + width) { shades[column] = shade }
            x += width
            run += 1
        }
        return shades
    }
}
