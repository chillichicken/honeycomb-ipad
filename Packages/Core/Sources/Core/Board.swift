import Foundation

/// The document: the tiles, which shape they are, what's selected, and the
/// bookkeeping "+" needs. Interaction state (camera, an active drag, the current
/// mode) belongs to the UI layer, not here.
public final class Board {
    /// A safety ceiling on board size, not a performance limit: queries and drawing
    /// cost what the neighborhood or viewport holds. What grows with the total is
    /// memory and load time. Callers that add tiles check `canAdd` first.
    public static let defaultMaxTiles = 2_000_000

    public let store = TileStore()
    public private(set) var shape: TileShape
    public let maxTiles: Int

    public var selected: Set<Tile> = []
    /// Tiles mid-animation: drawn position still easing toward the settled one.
    public private(set) var easing: Set<Tile> = []
    /// The tile "+" grows from: the last one added or touched.
    public var lastActive: Tile?
    /// Slot index (around `lastActive`) of the neighbor we came from, so the
    /// next "+" rotates onward from there and hugs the build's border.
    private(set) var spawnBackIndex: Int?

    public init(shape: TileShape = .hexagon, maxTiles: Int = Board.defaultMaxTiles) {
        self.shape = shape
        self.maxTiles = maxTiles
    }

    public var lattice: Lattice { Lattice(store: store, shape: shape) }

    public func canAdd(_ count: Int) -> Bool { store.size + count <= maxTiles }

    /// Marks a tile as animating toward its settled position.
    public func startEasing(_ tile: Tile) { easing.insert(tile) }

    // MARK: Adding

    /// "+": pops a new tile out of `lastActive` into a free neighbor slot. The
    /// first tile goes at `cameraCenter`.
    @discardableResult
    public func spawnTile(color: TileColor, cameraCenter: SIMD2<Double>) -> Tile {
        let tile: Tile
        if let anchor = lastActive {
            // Walk around the anchor's slots starting just past the one we came
            // from, so consecutive "+" presses hug the border (a growing snake).
            let slots = shape.neighborSlots[anchor.orientation]
            let start = spawnBackIndex.map { ($0 + 1) % slots.count } ?? 0
            var slot: Slot?
            for k in 0..<slots.count {
                let candidate = slots[(start + k) % slots.count]
                let sx = anchor.tx + candidate.dx
                let sy = anchor.ty + candidate.dy
                if lattice.tile(inSlotAt: sx, sy) == nil {
                    slot = Slot(x: sx, y: sy, orientation: candidate.orientation)
                    break
                }
            }
            // Fully surrounded (a ring just closed): hop to the nearest free slot.
            let target = slot ?? lattice.slotNear(anchor)
            tile = Tile(x: anchor.tx, y: anchor.ty, color: color, orientation: target.orientation)
            tile.tx = target.x
            tile.ty = target.y
        } else {
            var c = cameraCenter
            while lattice.tileAt(c.x, c.y) != nil { c.x += shape.neighborDist }  // camera sits on a tile
            tile = Tile(x: c.x, y: c.y, color: color)
        }
        place(tile)
        spawnBackIndex = store.size > 1 ? occupiedNeighborIndex(of: tile) : nil
        return tile
    }

    /// Places a tile at a point the user picked (double-tap on empty ground),
    /// connecting it to the nearest build via its nearest free slot.
    @discardableResult
    public func spawnTile(color: TileColor, at point: SIMD2<Double>) -> Tile {
        let tile: Tile
        if store.size == 0 {
            tile = Tile(x: point.x, y: point.y, color: color)
        } else {
            let slot = lattice.nearestReachableSlot(toX: point.x, point.y)
            tile = Tile(x: point.x, y: point.y, color: color, orientation: slot.orientation)
            tile.tx = slot.x
            tile.ty = slot.y
        }
        place(tile)
        spawnBackIndex = nil  // explicit placement, not a "+" chain
        return tile
    }

    private func place(_ tile: Tile) {
        store.add(tile)
        if tile.x != tile.tx || tile.y != tile.ty { easing.insert(tile) }
        lastActive = tile
    }

    /// Index of the first occupied neighbor slot around `tile`: where we came from.
    private func occupiedNeighborIndex(of tile: Tile) -> Int {
        let slots = shape.neighborSlots[tile.orientation]
        for (i, s) in slots.enumerated()
        where lattice.tile(inSlotAt: tile.tx + s.dx, tile.ty + s.dy) != nil {
            return i
        }
        return 0
    }

    // MARK: Removing

    public func remove(_ tile: Tile) {
        guard store.remove(tile) else { return }
        selected.remove(tile)
        easing.remove(tile)
        if lastActive === tile { reanchor(nearX: tile.tx, tile.ty) }
    }

    /// Bulk removal: O(removed), independent of board size.
    public func remove(_ tiles: some Collection<Tile>) {
        guard !tiles.isEmpty else { return }
        let anchor = lastActive.flatMap { tiles.contains($0) ? $0 : nil }
        for t in tiles {
            store.remove(t)
            selected.remove(t)
            easing.remove(t)
        }
        if let anchor { reanchor(nearX: anchor.tx, anchor.ty) }
    }

    /// Marks a tile as the one "+" grows from next (a drag just put it down).
    public func didTouch(_ tile: Tile) {
        lastActive = tile
        spawnBackIndex = nil
    }

    /// After removing the anchor, "+" continues right beside the gap.
    private func reanchor(nearX x: Double, _ y: Double) {
        lastActive = store.nearest(x, y)
        spawnBackIndex = nil
    }

    // MARK: Whole board

    /// Swaps the whole board for `tiles`, laid out in stacking order.
    public func replace(shape: TileShape, tiles: [Tile]) {
        store.clear()
        self.shape = shape
        for t in tiles { store.add(t) }
        easing = []  // incoming tiles are at rest
        selected = []
        lastActive = tiles.last
        spawnBackIndex = nil
    }

    // MARK: Animation

    /// Snaps every animating tile straight to its settled position.
    public func settleEasing() {
        for t in easing {
            t.x = t.tx
            t.y = t.ty
        }
        easing = []
    }

    /// Eases only the tiles actually mid-animation, not every tile on the board;
    /// a tile drops out once it visually converges. `skipping` are tiles held by a drag.
    /// `factor` is the fraction of the remaining distance covered this step.
    public func easeTowardTargets(skipping held: Set<Tile> = [], factor: Double = 0.25) {
        for t in easing where !held.contains(t) {
            t.x += (t.tx - t.x) * factor
            t.y += (t.ty - t.y) * factor
            if abs(t.tx - t.x) < 0.05 && abs(t.ty - t.y) < 0.05 {
                t.x = t.tx
                t.y = t.ty
                easing.remove(t)
            }
        }
    }
}
