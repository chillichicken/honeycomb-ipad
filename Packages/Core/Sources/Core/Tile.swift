/// 0xRRGGBB.
public typealias TileColor = UInt32

/// One tile on the board. A class, because tiles have identity: the store, the
/// selection and a drag all refer to the same tile.
///
/// `tx`/`ty` (where it settles), `color` and `z` change only through
/// `TileStore`, which keeps its buckets, watches and color counts truthful.
/// `x`/`y` (where it is drawn, easing toward `tx`/`ty`) belong to the caller.
public final class Tile {
    public var x: Double
    public var y: Double
    public internal(set) var tx: Double
    public internal(set) var ty: Double
    public internal(set) var color: TileColor
    /// Index into the shape's orientation arrays.
    public let orientation: Int
    /// Stacking order, higher draws on top. 0 = unassigned; `TileStore.add` assigns one.
    public internal(set) var z: Int = 0

    public init(x: Double, y: Double, color: TileColor, orientation: Int = 0) {
        self.x = x
        self.y = y
        self.tx = x
        self.ty = y
        self.color = color
        self.orientation = orientation
    }
}

/// Tiles are equal only to themselves.
extension Tile: Hashable {
    public static func == (a: Tile, b: Tile) -> Bool { a === b }
    public func hash(into hasher: inout Hasher) { hasher.combine(ObjectIdentifier(self)) }
}
