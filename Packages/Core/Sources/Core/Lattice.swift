import Foundation

/// A free position where a tile can be glued on, with the orientation it needs.
public struct Slot: Sendable {
    public let x: Double
    public let y: Double
    public let orientation: Int
}

public struct FreeSlot: Sendable {
    public let slot: Slot
    public let distance: Double
}

/// The pure spatial questions the board asks of its tiles: what's under a
/// point, which slots are free, where a new tile should go. Reads only the
/// store's neighborhood buckets, so cost never scales with board size.
public struct Lattice {
    /// How far out (in tile-widths) a snap query may reach. Callers zoomed far
    /// out pass a `maxDist` that is huge in world units; anything genuinely this
    /// far away isn't a meaningful snap, and querying that many buckets is what
    /// would turn "check nearby tiles" into a scan of empty space.
    static let maxSearchTileWidths = 8.0

    /// Ring-search visit cap before `slotNear` heads straight out instead.
    static let slotSearchNodeCap = 4096

    public let store: TileStore
    public let shape: TileShape

    public init(store: TileStore, shape: TileShape) {
        self.store = store
        self.shape = shape
    }

    /// The topmost tile whose drawn outline contains the point. Bucketed by
    /// settled position while the outline test uses the drawn one, so a tile
    /// still easing can miss by a whisker; settled tiles never overlap.
    public func tileAt(_ wx: Double, _ wy: Double) -> Tile? {
        var top: Tile?
        for t in store.near(wx, wy, radius: tileSize) {
            if top == nil || t.z > top!.z,
                shape.contains(
                    orientation: t.orientation, center: SIMD2(t.x, t.y), radius: tileSize,
                    point: SIMD2(wx, wy))
            {
                top = t
            }
        }
        return top
    }

    /// Every tile whose outline touches the rectangle (not just those whose
    /// center is inside it), at its settled position.
    public func forEachTile(
        touchingMinX minX: Double, minY: Double, maxX: Double, maxY: Double, _ visit: (Tile) -> Void
    ) {
        store.forEachTile(
            inMinX: minX - tileSize, minY: minY - tileSize, maxX: maxX + tileSize, maxY: maxY + tileSize
        ) { t in
            if shape.intersects(
                orientation: t.orientation, center: SIMD2(t.tx, t.ty), radius: tileSize,
                minX: minX, minY: minY, maxX: maxX, maxY: maxY)
            {
                visit(t)
            }
        }
    }

    /// The tile occupying the slot at (sx, sy), other than those in `ignore`.
    func tile(inSlotAt sx: Double, _ sy: Double, ignoring ignore: Set<Tile> = []) -> Tile? {
        let eps = shape.occupiedEps
        for t in store.near(sx, sy, radius: eps) where !ignore.contains(t) {
            if dist2(t.tx, t.ty, sx, sy) < eps * eps { return t }
        }
        return nil
    }

    /// Nearest free neighbor slot (among tiles not in `ignore`) within `maxDist`
    /// of the point, restricted to slots wanting `orientation` if given. A tile's
    /// orientation is fixed, so it can only glue into slots built for it.
    public func freeSlot(
        nearX wx: Double, _ wy: Double, ignoring ignore: Set<Tile> = [], maxDist: Double,
        orientation required: Int? = nil
    ) -> FreeSlot? {
        let d0 = shape.neighborDist
        let searchRadius = Swift.min(maxDist, d0 * Self.maxSearchTileWidths)
        var best: Slot?
        var bestD2 = maxDist * maxDist
        for t in store.near(wx, wy, radius: searchRadius + d0) where !ignore.contains(t) {
            for slot in shape.neighborSlots[t.orientation] {
                if let required, slot.orientation != required { continue }
                let sx = t.tx + slot.dx
                let sy = t.ty + slot.dy
                let d2 = dist2(wx, wy, sx, sy)
                if d2 < bestD2, tile(inSlotAt: sx, sy, ignoring: ignore) == nil {
                    bestD2 = d2
                    best = Slot(x: sx, y: sy, orientation: slot.orientation)
                }
            }
        }
        return best.map { FreeSlot(slot: $0, distance: bestD2.squareRoot()) }
    }

    /// Up to `limit` free neighbor slots within `maxDist` of the point, nearest first
    /// (distinct positions). `freeSlot` is the one-answer fast path; this is for callers
    /// that may have to reject the nearest and fall back to the next.
    public func freeSlots(
        nearX wx: Double, _ wy: Double, maxDist: Double, orientation required: Int? = nil, limit: Int
    ) -> [FreeSlot] {
        let d0 = shape.neighborDist
        let searchRadius = Swift.min(maxDist, d0 * Self.maxSearchTileWidths)
        var found: [FreeSlot] = []
        let maxD2 = maxDist * maxDist
        for t in store.near(wx, wy, radius: searchRadius + d0) {
            for slot in shape.neighborSlots[t.orientation] {
                if let required, slot.orientation != required { continue }
                let sx = t.tx + slot.dx
                let sy = t.ty + slot.dy
                let d2 = dist2(wx, wy, sx, sy)
                guard d2 < maxD2 else { continue }
                // several owners share the same free slot: keep it once
                if found.contains(where: { dist2($0.slot.x, $0.slot.y, sx, sy) < 1 }) { continue }
                if tile(inSlotAt: sx, sy) == nil {
                    found.append(FreeSlot(slot: Slot(x: sx, y: sy, orientation: slot.orientation), distance: d2.squareRoot()))
                }
            }
        }
        found.sort { $0.distance < $1.distance }
        return Array(found.prefix(limit))
    }

    /// Closest free neighbor slot reachable from `origin`, so "+" fills rings
    /// outward tile by tile. Breadth-first over the connected build. If the
    /// origin is buried so deep this would flood a huge solid block, it walks
    /// straight out along each of the origin's own slot directions and takes the
    /// nearest edge slot: O(block width) rather than O(block area).
    func slotNear(_ origin: Tile) -> Slot {
        var queue = [origin]
        var visited: Set<Tile> = [origin]
        var head = 0
        while head < queue.count && visited.count < Self.slotSearchNodeCap {
            let t = queue[head]
            head += 1
            for slot in shape.neighborSlots[t.orientation] {
                let sx = t.tx + slot.dx
                let sy = t.ty + slot.dy
                guard let occupant = tile(inSlotAt: sx, sy) else {
                    return Slot(x: sx, y: sy, orientation: slot.orientation)
                }
                if visited.insert(occupant).inserted { queue.append(occupant) }
            }
        }
        var best: Slot?
        var bestD2 = Double.infinity
        for dir in shape.neighborSlots[origin.orientation] {
            let slot = walkToFreeSlot(from: origin, towardX: dir.dx, dir.dy)
            let d2 = dist2(slot.x, slot.y, origin.tx, origin.ty)
            if d2 < bestD2 {
                bestD2 = d2
                best = slot
            }
        }
        return best!  // the walk always ends at a free slot of a finite build
    }

    /// From `origin`, keeps stepping to whichever occupied neighbor lies most in
    /// direction (ux, uy) until some tile has a free neighbor slot. Every tile's
    /// slots fan out around it, so one always points at least 60° "forward":
    /// the walk makes strict progress and reaches the build's edge.
    private func walkToFreeSlot(from origin: Tile, towardX ux: Double, _ uy: Double) -> Slot {
        var t = origin
        while true {
            var next: Tile?
            var nextDot = -Double.infinity
            for slot in shape.neighborSlots[t.orientation] {
                let sx = t.tx + slot.dx
                let sy = t.ty + slot.dy
                guard let occupant = tile(inSlotAt: sx, sy) else {
                    return Slot(x: sx, y: sy, orientation: slot.orientation)
                }
                let dot = slot.dx * ux + slot.dy * uy
                if dot > nextDot {
                    nextDot = dot
                    next = occupant
                }
            }
            t = next!
        }
    }

    /// The nearest tile to the point, then a breadth-first search of its
    /// connected build for the empty boundary slot closest to the point, however
    /// far that is. This guarantees the placed tile gets the orientation the real
    /// tiling requires there. Requires a non-empty board.
    func nearestReachableSlot(toX wx: Double, _ wy: Double) -> Slot {
        let anchor = store.nearest(wx, wy)!
        let d = shape.neighborDist
        var visited: Set<Tile> = [anchor]
        var queue = [anchor]
        var head = 0
        var best: Slot?
        var bestDist = Double.infinity
        while head < queue.count {
            let t = queue[head]
            head += 1
            // Once a candidate exists, a strictly closer free slot must belong to a
            // tile within bestDist + d of the point; skip the rest rather than
            // flooding the whole connected build.
            if best != nil {
                let reach = bestDist + d
                if dist2(wx, wy, t.tx, t.ty) > reach * reach { continue }
            }
            for slot in shape.neighborSlots[t.orientation] {
                let sx = t.tx + slot.dx
                let sy = t.ty + slot.dy
                if let occupant = tile(inSlotAt: sx, sy) {
                    if visited.insert(occupant).inserted { queue.append(occupant) }
                    continue
                }
                let sd = dist2(wx, wy, sx, sy).squareRoot()
                if sd < bestDist {
                    bestDist = sd
                    best = Slot(x: sx, y: sy, orientation: slot.orientation)
                }
            }
        }
        return best!  // a finite build always has a free boundary slot
    }
}

/// Squared distance, for callers that only compare against a threshold.
func dist2(_ ax: Double, _ ay: Double, _ bx: Double, _ by: Double) -> Double {
    let dx = ax - bx
    let dy = ay - by
    return dx * dx + dy * dy
}
