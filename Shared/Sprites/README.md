# Sprites

The animated pixel art in the right column of the menu bar panel, and in the Settings preview.

## Adding one

Three steps. The scaffolding is already written, so a sprite is a single `draw` function.

**1. Write the sprite.** One file in this directory:

```swift
import SwiftUI

/// One sentence on what it is and what growing means.
struct StackSprite: View {
    var cell: CGFloat = 9
    var fill: Double = 0
    var motion: SpriteMotion = .follow

    var body: some View {
        SpriteCanvas(cell: cell, fill: fill, motion: motion, growSeconds: 2, draw: draw)
    }

    private func draw(_ frame: SpriteFrame) {
        let height = Int(frame.level * Double(frame.rows))
        for row in 0..<height {
            for column in 0..<frame.columns {
                frame.paint(column, frame.rows - 1 - row)
            }
        }
    }
}
```

**2. Add the case** to `SpriteKind` in `SpriteSettings.swift`:

```swift
case plant, cave, water, stack
```

...and give it a `label`.

**3. Add it to the switch** in `SpriteView.swift`. That is the only switch. The panel and the
settings preview both go through it, so they cannot disagree.

**4. Check it.** Nothing else to edit, `project.yml` excludes this whole directory from the
test target already:

```sh
xcodegen generate
./build.sh
xcodebuild test -project Headroom.xcodeproj -scheme HeadroomTests \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO
```

Run the tests, not just the build. The app target and the test target compile different file
sets, so a mistake here can build fine and still break the suite. It shows up in Settings
straight away.

## What you get

`SpriteCanvas` handles the timeline, the growth easing, the motion mode and the colour. Your
`draw` receives a `SpriteFrame`:

| | |
|---|---|
| `frame.level` | 0 to 1. Already resolved from usage or the demo sweep. **Draw from this.** |
| `frame.columns` / `frame.rows` | Grid size for the space you were given |
| `frame.tint` | Green, orange or red, already matched to the level |
| `frame.time` | Seconds, for anything that keeps moving after the level settles |
| `frame.paint(col, row, shade:offset:)` | Fill one cell. `shade` dims, `offset` shifts sideways |

`SpriteNoise` has deterministic randomness, a clustered `profile`, and a `lean` for swaying.

## Rules

- **Draw from `frame.level`, never from elapsed time.** Time-driven growth ignores the user's
  usage and breaks Demo mode.
- **Never use `Double.random` or `Date()` inside `draw`.** It redraws ten times a second, so
  anything that changes between frames flickers. Use `SpriteNoise.value(seed)`.
- **Only ever use `frame.tint`.** Hardcoding a colour breaks the severity signal.
- **Read `frame.columns` and `frame.rows`.** Never assume a grid size. The panel and the
  Settings preview are different sizes.
- **Look good at 5%.** Usage sits in single digits most days. A sprite that is blank until 50%
  is blank whenever anyone actually looks at it. This is the cave's known flaw.

## Seeing it

Settings has a live preview, so pick your sprite there and switch Level to **Demo** to watch it
sweep the whole 0 to 100 range in 16 seconds, colours included.

For a side by side of several levels at once, see the offline renderer in `CONTEXT.md`.
