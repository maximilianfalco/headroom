import SwiftUI

/// A pixel fern whose size tracks how much of your worst limit is gone. A seedling means
/// plenty of room, a full fern means you are nearly out.
///
/// Generated rather than hand drawn, so it fills whatever height the panel gives it and gains
/// detail on a taller panel instead of scaling up a fixed bitmap.
struct PlantSprite: View {
    var cell: CGFloat = 9
    var fill: Double = 0
    var motion: SpriteMotion = .follow

    /// Rows between one frond pair and the next.
    private static let frondSpacing = 4

    var body: some View {
        SpriteCanvas(cell: cell, fill: fill, motion: motion, growSeconds: 2.5, draw: draw)
    }

    private func draw(_ frame: SpriteFrame) {
        let center = frame.columns / 2
        let ground = frame.rows - 2
        let tip = ground - Int(SpriteNoise.clamp(frame.level) * Double(ground - 1))

        var pixels = Set<Pixel>()
        stem(from: tip, to: ground, center: center, into: &pixels)
        fronds(tip: tip, ground: ground, center: center, into: &pixels)
        crown(tip: tip, center: center, into: &pixels, level: frame.level)

        for pixel in pixels {
            frame.paint(pixel.x, pixel.y, shade: pixel.faint ? 0.45 : 1,
                        offset: SpriteNoise.lean(time: frame.time, row: pixel.y, base: ground))
        }

        // Dotted soil, so the fern reads as planted rather than floating.
        for column in stride(from: 0, to: frame.columns, by: 2) {
            frame.paint(column, ground + 1, shade: 0.22)
        }
    }

    private func stem(from tip: Int, to ground: Int, center: Int, into pixels: inout Set<Pixel>) {
        guard tip <= ground else { return }
        for y in tip...ground { pixels.insert(Pixel(x: center, y: y)) }
    }

    /// Older fronds sit lower and have had longer to unfurl, which is what gives the fern its
    /// taper without any per-frond bookkeeping.
    private func fronds(tip: Int, ground: Int, center: Int, into pixels: inout Set<Pixel>) {
        let maxReach = min(6, max(1, center - 1))
        var y = ground - 2
        while y > tip {
            let reach = min(maxReach, (y - tip) / 3)
            if reach > 0 {
                for step in 1...reach {
                    let row = y + step / 4
                    guard row <= ground else { continue }
                    // The outermost leaflet is dimmer, so the frond fades out at its tip.
                    let faint = step == reach && reach > 2
                    pixels.insert(Pixel(x: center - step, y: row, faint: faint))
                    pixels.insert(Pixel(x: center + step, y: row, faint: faint))

                    // The inner half is two pixels deep, which is what stops it reading as kelp.
                    guard step <= (reach + 1) / 2, row + 1 <= ground else { continue }
                    pixels.insert(Pixel(x: center - step, y: row + 1))
                    pixels.insert(Pixel(x: center + step, y: row + 1))
                }
            }
            y -= Self.frondSpacing
        }
    }

    /// The curled head at the growing tip, which opens up as the fern matures.
    private func crown(tip: Int, center: Int, into pixels: inout Set<Pixel>, level: Double) {
        pixels.insert(Pixel(x: center, y: tip))
        guard level > 0.15 else { return }
        pixels.insert(Pixel(x: center - 1, y: tip + 1, faint: level < 0.5))
        pixels.insert(Pixel(x: center + 1, y: tip + 1, faint: level < 0.5))
        guard level > 0.55 else { return }
        pixels.insert(Pixel(x: center - 1, y: tip - 1, faint: true))
        pixels.insert(Pixel(x: center + 1, y: tip - 1, faint: true))
    }

    /// Position only for identity, so overlapping leaflets do not double paint and the brighter
    /// one wins.
    private struct Pixel: Hashable {
        let x: Int
        let y: Int
        var faint = false

        static func == (a: Pixel, b: Pixel) -> Bool { a.x == b.x && a.y == b.y }
        func hash(into hasher: inout Hasher) { hasher.combine(x); hasher.combine(y) }
    }
}
