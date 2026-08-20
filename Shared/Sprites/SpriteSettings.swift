import Foundation

enum SpriteKind: String, CaseIterable, Identifiable {
    case plant, cave, water, hourglass

    var id: String { rawValue }

    var label: String {
        switch self {
        case .plant: return "Plant"
        case .cave: return "Cave"
        case .water: return "Water"
        case .hourglass: return "Hourglass"
        }
    }
}

enum SpriteMotion: String, CaseIterable, Identifiable {
    /// Sits at whatever the worst limit currently reads.
    case follow
    /// Sweeps the whole range regardless of usage, so the sprite is worth watching at 5%.
    case demo

    var id: String { rawValue }
    var label: String { self == .follow ? "Usage" : "Demo" }
}

enum SpriteLevel {
    /// 0 to 1 to 0 over 16 seconds, so every level gets a moment on screen.
    static func demoSweep(at time: TimeInterval) -> Double {
        let phase = (time / 8).truncatingRemainder(dividingBy: 2)
        return 1 - abs(phase - 1)
    }

    /// Eases in from nothing when the panel opens, so the sprite grows rather than snapping.
    static func easedIn(_ level: Double, grown: TimeInterval, over seconds: TimeInterval) -> Double {
        let progress = min(1, max(0, grown) / seconds)
        return level * (1 - pow(1 - progress, 2.5))
    }

    /// What the sprite should draw, given the mode and the worst limit.
    static func resolve(motion: SpriteMotion, fill: Double, grown: TimeInterval,
                        growSeconds: TimeInterval, time: TimeInterval) -> Double {
        switch motion {
        case .demo: return demoSweep(at: time)
        case .follow: return easedIn(fill, grown: grown, over: growSeconds)
        }
    }
}
