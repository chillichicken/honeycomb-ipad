/// Circumradius (center to corner) shared by every shape, in world units.
public let tileSize: Double = 44

/// How close to a slot the magnet kicks in, in screen-independent world units
/// at zoom 1. Callers divide by `min(zoom, 1)` so it stays grabbable zoomed out.
public let snapRadius: Double = 34
