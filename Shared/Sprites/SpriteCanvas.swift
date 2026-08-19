import SwiftUI

/// One frame handed to a sprite: where to draw, how big the grid is, how far along the level
/// is, and what colour it should be. Everything a sprite needs and nothing it has to work out.
struct SpriteFrame {
    let canvas: GraphicsContext
    let size: CGSize
    let cell: CGFloat
    /// 0 to 1, already resolved from usage or the demo sweep.
    let level: Double
    /// Green, orange or red, already matched to the level.
    let tint: Color
    /// Seconds, for anything that should keep moving once the level settles.
    let time: TimeInterval

    var columns: Int { max(1, Int(size.width / cell)) }
    var rows: Int { max(1, Int(size.height / cell)) }

    /// Fills one grid cell. `shade` dims it, which is how a shape tapers or fades.
    /// `offset` shifts it sideways in whole cells, for leaning or swaying.
    func paint(_ column: Int, _ row: Int, shade: Double = 1, offset: CGFloat = 0) {
        let rect = CGRect(x: (CGFloat(column) + offset) * cell, y: CGFloat(row) * cell,
                          width: cell - 1, height: cell - 1)
        canvas.fill(Path(rect), with: .color(tint.opacity(shade)))
    }
}

/// The scaffolding every sprite shares: a ten frame a second timeline, growth anchored to when
/// the panel opened, the level resolved from usage or the demo sweep, and the colour picked to
/// match. A sprite supplies only what to draw.
///
/// The timeline only ticks while the panel is on screen, since a menu bar popover stops
/// rendering when it closes. Nothing animates in the background.
struct SpriteCanvas: View {
    var cell: CGFloat = 9
    var fill: Double = 0
    var motion: SpriteMotion = .follow
    /// How long the sprite takes to reach its level when the panel opens.
    var growSeconds: TimeInterval = 2
    let draw: (SpriteFrame) -> Void

    @State private var appeared = Date()

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 10.0)) { context in
            Canvas(rendersAsynchronously: false) { canvas, size in
                let now = context.date.timeIntervalSinceReferenceDate
                let level = SpriteLevel.resolve(
                    motion: motion, fill: fill,
                    grown: context.date.timeIntervalSince(appeared),
                    growSeconds: growSeconds, time: now)
                draw(SpriteFrame(canvas: canvas, size: size, cell: cell, level: level,
                                 tint: Severity(percent: Int(level * 100)).tint, time: now))
            }
        }
        // Re-arms every time the popover opens, so the sprite grows in rather than snapping.
        .onAppear { appeared = .now }
        .accessibilityHidden(true)
    }
}
