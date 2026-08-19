# Sprites — context

Why this is shaped the way it is, and what has already been tried and rejected. Read before
changing the scaffolding or adding a third sprite.

## Where sprites are drawn

Two places, both going through `SpriteView`:

- **The menu bar panel**, a 126pt column at `cell: 9`, full panel height
- **The Settings preview**, 98pt at `cell: 7`

They are different sizes on purpose, which is why `draw` must read `frame.columns` and
`frame.rows` rather than assume a grid.

## Why the level is passed in rather than computed

An earlier version had each sprite derive its own growth from elapsed time. That looked fine in
isolation but meant the sprite ignored usage entirely, and there was no way to add Demo mode
without writing it twice. `SpriteLevel.resolve` now owns both paths, so Demo behaves identically
in every sprite and a new one gets it for free.

## Why the timeline is only 10fps

Pixel art moves in whole cells. Anything faster spends frames redrawing an identical grid. The
timeline also only ticks while the popover is on screen, since a menu bar window stops rendering
when it closes, so nothing animates in the background.

## Why randomness must be deterministic

`draw` runs ten times a second. A real random source re-rolls every frame, so a shape that
should sit still flickers violently. `SpriteNoise.value(seed)` is a hash: same seed, same value,
forever. This was not hypothetical, it is why the helper exists.

## Things that have been tried and failed

**Per-row sway phase.** Giving each row its own `sin` phase shears a plant apart: rows slide
past each other and the symmetry dies. `SpriteNoise.lean` uses one phase scaled by height, so
the shape bends from its base. Do not reintroduce per-row phase.

**Hand authored frames.** The fern started as five ASCII art frames. It could not fill a variable
height, could not interpolate, and every tweak meant re-drawing five grids by hand. Generating
from `level` replaced all of it.

**Single pixel fronds.** A one pixel wide leaflet reads as seaweed. The fern only stopped
looking like kelp once the inner half of each frond became two pixels deep. Chunky beats fine at
this size, every time.

**The cave.** Stalactites hanging from a mass at the top are visually identical to liquid
dripping, and a one pixel wide spike cannot be drawn as the cone that would make it read as
stone. Three passes did not fix it. It is kept because the headroom metaphor is good and it
looks decent above 60%, but it is nearly blank below 40%, which is where usage normally sits.
If you are picking a sprite to imitate, imitate the plant or the water.

**Water** is the safest of the three. It reads at every level, since even a shallow puddle still
has a moving surface, and its crest gives an exact waterline the eye can read at a glance. Two
sines of different wavelength and drift direction cross the surface, because one alone looks
mechanical.

## Rendering offline

Settings previews one sprite at your current level. To see several levels side by side, compile
the sprite sources into a throwaway binary that writes a PNG. No Xcode project, no signing:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
$(xcrun --find swiftc) -sdk "$(xcrun --show-sdk-path)" -parse-as-library \
  Shared/UsageSnapshot.swift Shared/UsageViews.swift Shared/Sprites/*.swift preview.swift \
  -o preview && ./preview
```

Where `preview.swift` has an `@main` struct rendering an `HStack` of the sprite at several
`fill` values through `ImageRenderer`, writing the result with `NSBitmapImageRep`.

Two traps:

- **Growth is anchored to `onAppear`**, so an offline render always catches the sprite at
  level 0. Patch the *copy* to bypass the easing, never the shipping file.
- **Plain `swift file.swift` uses CommandLineTools** and dies on `SwiftBridging`. Always
  `DEVELOPER_DIR` plus `xcrun --find swiftc` plus an explicit `-sdk`.

Every layout bug so far was found this way and not by staring at the code.

## Build wiring

`project.yml` excludes **this whole directory** from the test target, then adds
`SpriteSettings.swift` and `SpriteNoise.swift` back by name, since those are pure logic and are
tested. `**/*.md` is excluded everywhere so docs never land in the app bundle.

It is written that way on purpose. Listing each view file by name meant a new sprite compiled
into the test target, where `Severity.tint` is not available, and the failure surfaced as
`cannot find type 'SpriteFrame' in scope` pointing at the new file rather than at the real
cause. Excluding the directory means adding a sprite needs no build change at all. This was
found by following the README literally and watching it break, which is worth repeating after
any change to the structure here.
