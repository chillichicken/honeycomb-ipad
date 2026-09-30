# Interaction design

The iPad app is a Swift rewrite of the web/desktop game (`honeycomb`, TypeScript). Interaction is
redesigned for touch: one finger does the active mode's action, two fingers always navigate.

## Modes

A top bar switches between three modes. Exactly one is active. Default: **Grab**.

| Mode | Icon (SF Symbols) | One finger (press and drag) |
|---|---|---|
| Grab | `hand.draw` / `hand.point.up.left` | Drag tiles (snap edge to edge); on empty canvas, pan |
| Select | `rectangle.dashed` | Tap a tile to toggle it; drag a marquee to toggle everything inside |
| Recolor | `paintbucket` | Tap a tile to recolor it |

Not modes:

- **"+"** adds a tile next to the last tile added (same as the PC version), then switches to Grab.
- **Delete** is a button, visible only while a selection exists; it deletes the selection.

## Navigation

Two fingers pan and zoom in every mode (like a trackpad). It never requires leaving the current mode.

## Selection

- The selection persists across mode switches.
- **Select mode, marquee:** each tile inside the marquee toggles individually. A marquee always
  adds to the existing selection; tiles that were already selected become unselected.
- **Select mode, tap:** toggles that tile.
- **Grab mode:** dragging a selected tile moves the whole selection together. Dragging an
  unselected tile moves just that tile and clears the selection. (Selecting only happens in Select mode.)

## Recolor

Matches the PC Alt+click behaviour:

- Tapping an unselected tile recolors that tile only.
- Tapping a tile that is part of the selection recolors the whole selection.
- Picking a color in the palette while a selection exists recolors the whole selection.

## Open questions

- Palette placement: strip under the top bar vs. popover on the bucket button.
