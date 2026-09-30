# Snappy Shapes for iPad

A tile puzzle sandbox: place tiles of one shape (hexagon, triangle or diamond) on an unlimited canvas and drag them around; they snap edge to edge. This is the native Swift version of the desktop game; see `CLAUDE.md` for how it is built.

## Run it

1. Open `Snappy Shapes.xcodeproj` in Xcode.
2. Pick an iPad simulator (or your iPad) as the run destination and press Cmd-R.

In debug builds the top-right `...` menu fills the board with test tiles and buttons at the bottom left zoom in and out. In the Simulator, hold Option and drag to simulate a two-finger pinch.

## Test it

```bash
cd Packages/Core && swift test      # game logic, ~4 s
```

Cmd-U in Xcode runs the UI tests, which drive the app with real synthesized touches.

## Layout

- `Packages/Core`: the game logic (spatial tile store, snapping, islands, chunked persistence). No UIKit.
- `Snappy Shapes`: the app (SwiftUI screens, Metal board renderer, gestures, sound).
- `Snappy ShapesUITests`: gesture tests.
- `docs/interaction.md`: how the modes and gestures work.
