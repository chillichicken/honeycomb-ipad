# Interaction design

The iPad app is a Swift rewrite of the desktop game (`honeycomb`, TypeScript). Interaction is redesigned for touch: one finger does the active mode's action, two fingers always navigate.

## Modes

A top bar switches between three modes. Exactly one is active. Default: **Grab**.

| Mode | Icon | One finger (press and drag) |
|---|---|---|
| Grab | `hand.draw` | Drag tiles (snap edge to edge); on empty canvas, pan |
| Select | `rectangle.dashed` | Tap a shape to toggle it; drag a frame to toggle every shape it touches |
| Recolor | `drop.fill` (SF Symbols has no bucket) | Tap a shape to recolor it |

Not modes:

- **"+"** adds a tile next to the last tile added, then switches to Grab. Holding it repeats (first tile at once, repeat after 800 ms, every 100 ms) until released or the board is full (then a toast shows).
- **Delete** is a button with the selection count, visible only while a selection exists.
- **Shape button** (top left) shows the current shape and opens a picker. Choosing a different shape on a board with tiles asks first: "A puzzle can only use one shape — switching clears the current board. Continue?" Confirming starts a new puzzle (the old one stays saved) with one seed tile.
- **Puzzles button** (folder) saves and returns to the start screen.

## Navigation

Two fingers pan and zoom in every mode, without leaving the current mode. Trackpad scroll pans; Cmd + scroll zooms; a real trackpad pinch works on an iPad. Debug builds add zoom buttons.

## Selection

- The selection persists across mode switches.
- **Select mode, frame:** every shape the frame *touches* (not just those whose center is inside) toggles: unselected ones become selected, selected ones become unselected. A frame always adds to the existing selection. While dragging, the shapes it touches show their outline live.
- **Select mode, tap:** toggles that shape.
- **Grab mode:** dragging a selected tile moves the whole selection together. Dragging an unselected tile moves just that tile and clears the selection.

## Recolor

Matches the desktop Alt+click behavior:

- Tapping an unselected tile recolors that tile only.
- Tapping a tile that is part of the selection recolors the whole selection.
- Picking a color in the strip (shown under the top bar in Recolor mode) while a selection exists recolors the whole selection.
- New tiles start in the classic orange, `#f5a623`.

## Start screen and saving

The start screen offers Triangle, Hexagon and Diamond, and lists saved puzzles (tap to open, trash to delete after confirming). Saving is automatic: about 2 s after an edit, every 30 s regardless, never mid-drag, and when the app leaves the foreground.
