import SwiftUI

/// The one place that maps a `SpriteKind` to its view. Adding a sprite means adding a case
/// here and nowhere else, so the panel and the settings preview cannot drift apart.
struct SpriteView: View {
    let kind: SpriteKind
    var fill: Double = 0
    var motion: SpriteMotion = .follow
    var cell: CGFloat = 9

    var body: some View {
        switch kind {
        case .plant: PlantSprite(cell: cell, fill: fill, motion: motion)
        case .cave: CaveSprite(cell: cell, fill: fill, motion: motion)
        case .water: WaterSprite(cell: cell, fill: fill, motion: motion)
        case .hourglass: HourglassSprite(cell: cell, fill: fill, motion: motion)
        }
    }
}
