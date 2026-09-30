# CLAUDE.md

Guidance for Claude Code working in this repository.

## What this is

**Snappy Shapes for iPad**: a native Swift rewrite of the desktop/web game (repo `honeycomb`, TypeScript, at `../honeycomb`). Place tiles of one shape (hexagon, triangle or diamond) on an unlimited canvas, drag them, and they magnetically snap edge to edge. The iPad version is a separate app on purpose: touch interaction differs a lot from the mouse/keyboard original (see `docs/interaction.md`), and there is no save-file compatibility with the desktop app.

The `../honeycomb` repo is the reference for behavior and algorithms. When porting or matching a feature, read its source and tests first (`src/*.ts`, `test/*.test.ts`) rather than guessing.

## Principles

Follow KISS, SOLID, DRY and YAGNI (the owner cares about this; they explicitly asked for "the Design Patterns book, SOLID and KISS"). Small files with one responsibility; depend on protocols where a backend may change (`PuzzleStoring`); don't build for hypothetical futures.

## Commands

```bash
# Core package: pure logic, no UIKit. Fast (~4 s), no simulator needed.
cd Packages/Core && swift test

# Build the app for the iPad simulator
xcodebuild -project "Snappy Shapes.xcodeproj" -scheme "Snappy Shapes" \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' build

# UI tests (synthesized touches). Reset simulators first, run serially.
xcrun simctl shutdown all
xcodebuild test -project "Snappy Shapes.xcodeproj" -scheme "Snappy Shapes" \
  -destination 'platform=iOS Simulator,name=iPad Pro 13-inch (M4)' \
  -parallel-testing-enabled NO -only-testing:"Snappy ShapesUITests/GestureUITests"
```

Toolchain: Xcode with Swift 6.1, deployment target iOS 18.5. Bundle id `south-coast-spiele-kiste.Snappy-Shapes`. The project path and target names contain a space; always quote them.

## Layout

```
Packages/Core/            local Swift package "Core": all game logic, unit-tested
  Sources/Core/
    TileShape, Geometry   corner/neighbor geometry per shape; tileSize, snapRadius
    Tile, Cells           Tile (identity class), CellCoord/ChunkCoord keys
    TileStore, ChunkWatch spatial index (bucketed cells), dirty-chunk watches, color counts, z-order
    Lattice               pure spatial queries: hit-test, free snap slots, "+" search, shape-vs-rect
    Board                 the document: store + shape + selection + lastActive + easing + tile cap
    DragSession           carrying tiles outside the store, snapping on drop
    Clusters              computeClusters (test oracle) + time-sliced ClusterTracker (islands)
    ChunkData             binary chunk file format
    PuzzleStore           PuzzleStoring protocol + value types
    FilePuzzleStore       folder-per-puzzle implementation
    BoardPersistence      differential save / load of a Board (MainActor)
    Format                relativeTime / formatDuration
    SoundSynth            the two sounds synthesized to sample buffers (pure DSP, no audio hardware)
  Tests/CoreTests/        Swift Testing (123 tests), mostly ported from the desktop vitest suite
Snappy Shapes/            the app target (SwiftUI + UIKit canvas)
  AppModel                screens, current puzzle, autosave loop, shape-switch confirmation
  Editor                  turns touches into board actions per mode; owns camera/drag/marquee
  BoardView               UIView canvas: display link + gesture recognizers; hosts the MTKView
  TileRenderer            Metal: fills the instance buffer from the viewport's buckets, encodes the frame
  Shaders.metal           backdrop (gradient + dot grid) and tiles (polygon distance field: fabric, stitch, wall, outline)
  CanvasOverlay           marquee, snap ghost and stats watermark as small layers/labels over the GPU view
  SoundPlayer             plays the synthesized sounds (AVAudioEngine, small voice pool); on/off toggle
  Camera, Theme, Palette  view transform; the one-hue theme (hue 230); tile colors
  StartScreen, PuzzleRow, ShapeIcon, TopBar, ConfirmOverlay, RepeatButton, ContentView
Snappy ShapesUITests/     GestureUITests: real touches against the running app
docs/interaction.md       the interaction spec (modes, gestures, recolor rules)
```

## Architecture notes

- **The board is a spatial index, not an array** (`TileStore`): tiles bucketed by settled position (`tx/ty`) into 2-tile-wide cells. Every spatial question reads only the buckets involved; don't iterate the whole store except for whole-board work. `tx/ty/color/z` are `internal(set)` on `Tile`, so they change only through the store (the compiler enforces what the TypeScript version only documented). `x/y` is the drawn position, which eases toward `tx/ty`.
- **Carried tiles are out of the store** (`DragSession`): grabbing removes tiles from the store; they move as plain objects; `drop` snaps and files them back. Per-move snap checks are sampled round-robin for big groups (`sampleLimit`); the drop is always an exact pass. **A group is only snapped where every member lands on free ground**: `findSnap` ranks candidate slots by distance (`Lattice.freeSlots`) and takes the nearest one the whole rigid group fits (`groupFits`); if none fits it stays where it was dropped. The desktop version just shifts by the nearest single-tile slot, which stacked group members on top of existing tiles in about half of all group snaps (measured on 300 random drops per shape). A lone tile dropped on another slides to the nearest free slot within two tile-widths.
- **Core vs app split**: `Core` has no UIKit and no interaction state. `Board` is the document only. Camera, current mode, drag and marquee live in `Editor` in the app target.
- **Rendering is on the GPU** (`TileRenderer` + `Shaders.metal`). Every visible tile is one 16-byte instance of a quad (position relative to the camera center as `Float`, so precision never degrades far from the origin; packed color; orientation and outline flags). The fragment shader draws the shape as a polygon distance field and picks its detail from the tile's on-screen radius: under 3px a flat padded square, then fill + border, then (>=12px) the inner honeycomb wall, then (>=30px) the fabric grain (an overlay-blended twill + noise pattern anchored to world coordinates) and the dashed stitch seam. Selected tiles get the accent outline in the shader. The CPU's per-frame work is walking the viewport's buckets and writing instances (stacking order is sorted only up to 65,536 visible tiles). Frames are triple-buffered; a frame is skipped, not blocked, if the GPU is behind. Redraws happen only when `Editor.version` changes (bumped by `touch()`, or every frame while tiles ease). If you add a new way for the board to change, call `touch()` (or `edited()` for real board edits).
- **Why Metal**: the first version drew with Core Graphics on the CPU. A full-screen bitmap redrawn and uploaded every frame made a 100-tile animation crawl, and 100k tiles cost about 61 ms per frame (unoptimized). The Metal version costs about 7 ms CPU and 0.2 ms GPU per frame with 90k tiles on screen. The stats watermark shows fps, cpu and gpu ms.
- **Easing is time-based**: `Board.easeTowardTargets(factor:)`, with `Editor.frameTick(dt:)` passing `1 - 0.75^(dt*60)`, so the glide takes the same time at 60 Hz and 120 Hz.
- **Debug builds are optimized** (`SWIFT_OPTIMIZATION_LEVEL = -O` for the app in `project.pbxproj`, and `-O` for `Core` in its `Package.swift`), because unoptimized Swift is many times slower and the board code is hot. Debug still has the `DEBUG` flag and symbols. This also made `swift test` about 3x faster.
- **Sound** is synthesized, not sampled: `SoundSynth` (Core) renders the desktop's two sounds (a band-passed-noise snap click and a softer low-passed "bloop" for a new tile) to buffers; `SoundPlayer` plays them through 4 round-robin player nodes so held-down "+" overlaps instead of cutting off. Sound is on by default, remembered in `UserDefaults`, and uses the `.ambient` audio session (respects the silent switch).
- **Edits vs touches**: `Editor.edited()` stamps `lastEditAt` (drives autosave and "active time"); `touch()` only requests a redraw. A drag only counts as an edit if it moved.
- **Persistence** is chunked and differential: `BoardPersistence.save` writes only the chunks `TileStore.takeDirty()` reports (full write for a new puzzle or after switching puzzle); on failure the dirty flags are restored so the retry still covers them. `FilePuzzleStore` writes each file atomically and `meta.json` last, but a many-file save is not one transaction (a crash midway can leave chunks of mixed age). Autosave is driven by `AppModel.tick()` (about 2 s after the last edit, 30 s safety, never mid-drag) plus a save when the scene leaves the foreground.
- **Island counting** (`ClusterTracker`) is incremental per chunk, and a change in one chunk can alter its neighbors' cached borders (a tile added beside an unchanged chunk creates a new cross-chunk edge). So a changed chunk re-labels its 3x3 neighborhood and redoes edges for the 5x5; re-labeling only the changed chunk made the count report 2 islands for one connected build, most visibly at the origin where four chunks meet. The desktop TypeScript version has the same design and the same latent bug. `computeClusters` is the oracle, and `ClusterTrackerTests` compare against it after every kind of edit; keep doing that when touching it.
- **Modes** are Grab / Select / Recolor; "+" is an action that returns to Grab. Details in `docs/interaction.md`.
- **Dev-only UI** is behind `#if DEBUG` (tile-fill menu, zoom buttons, the `pinchpad` test element, the `SEED_*` launch environment).

## Testing and verifying changes

- Logic changes: add or extend Swift Testing tests in `Packages/Core/Tests/CoreTests` and run `swift test`. Port the matching desktop test when there is one. Timing assertions run in debug builds in parallel, so keep thresholds generous (an O(n) regression takes minutes, not seconds).
- Interaction changes: extend `GestureUITests`. The canvas exposes its state as an accessibility value (`zoom=..;cx=..;cy=..;tiles=..;selected=..;islands=..;mode=..`, see `Editor.stateSummary`), which is how tests read back what the touches did.
- Visual changes: launch with seeded data and look at a screenshot.
  ```bash
  xcrun simctl install <device> <path to Snappy Shapes.app>
  SIMCTL_CHILD_SEED_SHAPE=hexagon SIMCTL_CHILD_SEED_TILES=40 xcrun simctl launch <device> south-coast-spiele-kiste.Snappy-Shapes
  xcrun simctl io <device> screenshot out.png
  ```
  A temporary XCUITest that taps things and writes `XCUIScreen.main.screenshot()` to a file works for states you can't reach by launch arguments (popovers, dialogs); delete it afterwards.

## Gotchas learned the hard way

- **Xcode project wiring**: the project uses file-system-synchronized groups, so new files under `Snappy Shapes/` are picked up automatically. The `Core` package must be in the app target's *Frameworks* build phase (it was referenced but not linked at first; fixed by hand in `project.pbxproj`). If `project.pbxproj` is edited on disk while Xcode has the project open, quit Xcode (Cmd-Q) and reopen it, or it keeps a stale copy and reports "Cannot find type ... in scope".
- **Name clash**: `Shape` collides with SwiftUI's `Shape`, hence `TileShape`. `View.panel(_:)` in `Theme.swift` is generic over SwiftUI's `Shape`.
- **macOS `sed` has no `\b`** (and silently does nothing); use `perl -pi -e`. `xargs` breaks on the space in `Snappy Shapes/`; use `-print0 | xargs -0` or loops.
- **`UIView.frame` selector clash**: don't name a display-link handler `frame()`; it's `tick()`.
- **SF Symbols has no paint bucket** (`paintbucket` does not exist); Recolor uses `drop.fill`. Check names with a small `NSImage(systemSymbolName:)` script before using one.
- **Simulator input limits**: the Simulator does not turn a Mac trackpad pinch into an iPad pinch. Hold Option and drag for a simulated pinch. Trackpad/wheel scrolls need their own recognizer (`allowedScrollTypesMask = .all` with `allowedTouchTypes = []`); Cmd+scroll zooms. Debug builds have zoom buttons at the bottom left. On a real iPad a trackpad pinch works natively.
- **A pan recognizer fires late**: by the time `UIPanGestureRecognizer` reports `.began`, the finger has already moved (a slop, and far more for a fast flick or a mouse), and its `location` is where the finger *is*, not where it touched down. Hit-testing that point meant a tile only a few points wide (zoomed out) was missed and the drag panned the canvas instead of grabbing the tile, so tiles never got moved to attach. `BoardUIView` records the real touch-down point in `touchesBegan` and uses that to start a drag or marquee. `testDraggingSnapsAtEveryZoomLevel` guards it.
- **XCUITest pinch**: an inward pinch on a full-screen element starts the fingers at the screen edges (home indicator, toolbar), so it never reaches the canvas. Tests pinch the invisible `pinchpad` element instead (debug builds only).
- **Running UI tests**: `xcrun simctl shutdown all` first and pass `-parallel-testing-enabled NO`; otherwise the test runner sometimes fails to launch on a cloned simulator. The "result bundle could not be saved" message is harmless.
- **Swift 6 concurrency**: `BoardPersistence` is `@MainActor` so a `Board` never crosses isolation domains; requests sent to `PuzzleStoring` are `Sendable` value types.
- **Tests need `import Foundation`** for `hypot` etc.
- **Metal Shading Language reserves `half`** (half-precision float); don't name a variable that. New `.metal` files in `Snappy Shapes/` are compiled automatically by the synchronized group. The Swift structs `TileInstance` and `GPUUniforms` must match the ones in `Shaders.metal` field for field (everything in `GPUUniforms` is a `float4` on purpose, to sidestep alignment mismatches).
- **The Simulator's Metal is the host GPU**, so its GPU numbers are optimistic for an iPad; CPU numbers (the instance walk) are more transferable. Judge feel on a real device.

## Differences from the desktop version (intentional)

Native Swift, no web stack; file-based puzzle storage (no IndexedDB, no legacy JSON format, no palette in chunks: colors are stored per tile); tile colors are `UInt32` (0xRRGGBB), not strings; `Board` no longer holds camera/drag state; no undo (the game is a sandbox, same as desktop); selection is by mode and touch instead of Shift/Alt/Ctrl modifiers.

## Not ported yet

Chunk thumbnails or a persistent GPU instance buffer for boards well past 100k visible tiles (today the CPU rewrites the instance buffer each redraw: about 7 ms at 90k tiles, fine, but it grows linearly), the time-budgeted snap search (uses a tile-count sample instead), text tool, JSON export/import, the color wheel and color schemes (there is a 12-swatch strip), puzzle rename and "save as new", help screen, color breakdown and memory/session lines in the stats watermark, a per-platform tile cap (currently the desktop's 2,000,000; iPad memory is tighter and needs measuring on a device), and a logo on the start screen (currently text).

## Roadmap

Ship to iPad (TestFlight, then App Store). Needs an Apple Developer Program membership (also needed for macOS notarization of the desktop app). Real-device testing of gestures, sound and large-board performance has not happened yet; everything so far was verified in the Simulator.

## Status and open issues (handoff, 2026-10-01)

**Where things are:** work is on branch `metal-sound-and-drag-fixes` (pushed; `main` is at the same commit, `a82e375`, nothing merged beyond that). 123 Core tests and 13 UI tests (`GestureUITests`) pass. Everything has only been verified in the iPad Pro 13" Simulator, never on a real iPad.

**Open issue 1: "hexagons don't visually attach" (reported by the owner several times, NOT reproduced).** What was found and fixed along the way, each with regression tests:
1. `ClusterTracker` reported 2 islands for one connected build (neighbor chunks' cached borders went stale).
2. Dragged groups snapped by the nearest single-tile slot and stacked on existing tiles about half the time; now a group snaps only where every member fits.
3. A drag hit-tested where the pan recognizer fired, not where the finger landed, so zoomed out the tile was missed and the canvas panned instead (`touchDown` in `BoardUIView`).
What was verified NOT to be the problem: "+" (start screen -> Hexagon -> hold "+" 12 s -> 126 tiles, 1 island, all aligned), single-tile drag snap at 3 zoom levels, drawn vs logical positions (`drift=0`), a stale build (the owner's Xcode build post-dated the drag fix). The owner said that after reopening the saved puzzle "things were in place", which points at something live-only (input or rendering), not saved data.
**To resolve it I need from the owner, at the moment it happens:** a screenshot with the bottom-right stats visible (the "N islands" line says whether the game thinks the tiles are connected; "built HH:MM:SS" says which build is running), which action they did ("+", dragging one tile, dragging a selection, Select or Recolor mode), the zoom shown in the stats, and what input they use (Simulator mouse/trackpad, or a real iPad with finger/Pencil). Ideas not yet checked: palm or second finger cancelling the one-finger drag (`maximumNumberOfTouches = 1`), trackpad "tap and drag" arriving as a scroll, drop behavior in Select/Recolor mode (one finger does not move tiles there, by design).

**Open issue 2: "zooming shows only a partial rectangle with 200k tiles" (NOT reproduced).** Zoom in/out with the buttons, pinches, portrait and landscape, and the merged-to-tile hand-over all render fully. Need the same details (zoom method, screenshot, the cpu ms in the stats).

**Other things to know:** debug zoom buttons exist because the Simulator doesn't forward trackpad pinches (Option-drag, Cmd+scroll also work). Sound is on by default with a toggle; the owner hasn't reported on how it sounds. The recolor icon is a water drop (no bucket symbol exists). The "Puzzles" folder button and the shape button are separate on purpose.

**Next steps, in order:** (1) get the owner's screenshot/steps for issue 1 and reproduce it with a UI test before changing code; (2) same for issue 2; (3) test on a real iPad (gestures, sound, 100k+ tile performance, memory, and a per-platform tile cap); (4) the "Not ported yet" list above; (5) TestFlight/App Store needs an Apple Developer membership.

**Desktop repo (`../honeycomb`):** has the same two logic bugs as the iPad version had (cross-chunk island counting in `clusters.ts`; group snapping in `input.ts` `findSnap`). Not fixed there; offer it to the owner. That repo also holds the owner's own uncommitted store-page work (`website/index.html`, images, large videos): do not touch or commit it without being asked.

