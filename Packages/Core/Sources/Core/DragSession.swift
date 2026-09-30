import Foundation

/// The best slot any carried tile could glue into.
public struct SnapCandidate {
    public let slot: Slot
    public let tile: Tile
}

public enum Landing {
    /// Glued into a free slot.
    case snapped
    /// Dropped on top of another tile and slid into the nearest free slot.
    case slid
    /// Left where it was put.
    case free
}

/// Carrying tiles around. The grabbed tiles leave the store and move as plain
/// objects (two writes each per move, no re-filing), so a huge group stays
/// cheap and never snaps against itself. `drop` files them back in.
public final class DragSession {
    public struct Item {
        public let tile: Tile
        /// Offset from the grab point.
        public let dx: Double
        public let dy: Double
    }

    public private(set) var items: [Item]
    public let tiles: Set<Tile>
    /// False until the first move: a plain tap isn't an edit.
    public private(set) var moved = false
    public private(set) var snapCandidate: SnapCandidate?

    private let board: Board
    private var cursor = 0  // where the next sampled snap check resumes

    /// Lifts `tiles` above everything (keeping their order among themselves) and
    /// takes them out of the store.
    public init(board: Board, tiles grabbed: [Tile], grabbedAt point: SIMD2<Double>) {
        self.board = board
        let ordered = grabbed.sorted { $0.z < $1.z }
        for t in ordered {
            board.store.raise(t)
            board.store.remove(t)
        }
        items = ordered.map { Item(tile: $0, dx: $0.x - point.x, dy: $0.y - point.y) }
        tiles = Set(ordered)
    }

    /// Follows the pointer and refreshes the snap preview. A group bigger than
    /// `sampleLimit` is checked round-robin across moves; `drop` always does one
    /// exact pass.
    public func move(to point: SIMD2<Double>, snapDistance: Double, sampleLimit: Int = 256) {
        moved = true
        for it in items {
            it.tile.x = point.x + it.dx
            it.tile.y = point.y + it.dy
            it.tile.tx = it.tile.x
            it.tile.ty = it.tile.y
        }
        snapCandidate = findSnap(within: snapDistance, sampleLimit: sampleLimit)
    }

    /// Ends the carry: snaps the group by the best slot found, then files every
    /// tile back into the board at its final spot.
    @discardableResult
    public func drop(snapDistance: Double) -> Landing {
        var landing = Landing.free
        if let snap = findSnap(within: snapDistance, sampleLimit: nil) {
            let ddx = snap.slot.x - snap.tile.tx
            let ddy = snap.slot.y - snap.tile.ty
            for it in items {
                it.tile.tx += ddx
                it.tile.ty += ddy
                board.startEasing(it.tile)
            }
            landing = .snapped
        } else if items.count == 1, let slot = slideOffOccupant(items[0].tile) {
            items[0].tile.tx = slot.x
            items[0].tile.ty = slot.y
            board.startEasing(items[0].tile)
            landing = .slid
        }
        for it in items { board.store.add(it.tile) }
        if let last = items.last { board.didTouch(last.tile) }
        snapCandidate = nil
        return landing
    }

    private func findSnap(within maxDist: Double, sampleLimit: Int?) -> SnapCandidate? {
        let n = items.count
        guard n > 0 else { return nil }
        let lattice = board.lattice
        // If nothing on the board is anywhere near the group, nothing can snap:
        // the usual case when carrying a group across empty ground.
        var minX = Double.infinity, minY = Double.infinity
        var maxX = -Double.infinity, maxY = -Double.infinity
        for it in items {
            minX = Swift.min(minX, it.tile.x)
            maxX = Swift.max(maxX, it.tile.x)
            minY = Swift.min(minY, it.tile.y)
            maxY = Swift.max(maxY, it.tile.y)
        }
        let reach = board.shape.neighborDist * 9  // freeSlot never looks further than this
        guard board.store.hasTile(inMinX: minX - reach, minY: minY - reach, maxX: maxX + reach, maxY: maxY + reach)
        else { return nil }

        let checks = Swift.min(n, sampleLimit ?? n)
        let start = sampleLimit == nil ? 0 : cursor % n
        var best: SnapCandidate?
        var bestD = maxDist
        for k in 0..<checks {
            let tile = items[(start + k) % n].tile
            if let s = lattice.freeSlot(
                nearX: tile.x, tile.y, maxDist: bestD, orientation: tile.orientation)
            {
                bestD = s.distance
                best = SnapCandidate(slot: s.slot, tile: tile)
            }
        }
        if sampleLimit != nil { cursor = (start + checks) % n }
        return best
    }

    /// A single tile dropped on top of another slides into the nearest free slot
    /// (it isn't in the store, so it can't block itself).
    private func slideOffOccupant(_ tile: Tile) -> Slot? {
        let d = board.shape.neighborDist
        let under = board.store.near(tile.x, tile.y, radius: d * 0.8).contains {
            dist2($0.tx, $0.ty, tile.x, tile.y) < (d * 0.8) * (d * 0.8)
        }
        guard under else { return nil }
        return board.lattice.freeSlot(
            nearX: tile.x, tile.y, maxDist: d * 2, orientation: tile.orientation)?.slot
    }
}
