import Foundation

/// The board's tiles, bucketed by settled position (`tx`/`ty`) into cells and
/// kept that way incrementally. It is the one source of truth for which tiles
/// exist and where: every spatial question reads only the buckets involved,
/// so cost tracks the size of the neighborhood, never the size of the board.
public final class TileStore: Sequence {
    /// Ceiling on `near`'s search radius in cells: bucket count grows with r²,
    /// so an unbounded radius would turn a lookup into a scan of empty space.
    private static let maxNearCells = 128

    private var buckets: [CellCoord: [Tile]] = [:]
    private var watches: [ChunkWatch] = []
    private let saveWatch = ChunkWatch()  // the autosave's, see `takeDirty`
    private var colors: [TileColor: Int] = [:]
    private var nextZ = 1

    public private(set) var size = 0

    public init() {
        watches.append(saveWatch)
    }

    /// How many non-empty cells there are: the ceiling on any bucket walk.
    public var bucketCount: Int { buckets.count }

    /// How many tiles there are of each color.
    public var colorCounts: [TileColor: Int] { colors }

    // MARK: Changing the board

    /// A tile that arrives without a stacking order goes on top of everything;
    /// one that already has one keeps its place.
    public func add(_ tile: Tile) {
        if tile.z == 0 {
            tile.z = nextZ
            nextZ += 1
        }
        bucketAdd(tile)
        size += 1
        colorDelta(tile.color, 1)
        flag(tile.tx, tile.ty)
    }

    @discardableResult
    public func remove(_ tile: Tile) -> Bool {
        guard bucketRemove(tile, atX: tile.tx, y: tile.ty) else { return false }
        size -= 1
        colorDelta(tile.color, -1)
        flag(tile.tx, tile.ty)
        return true
    }

    /// Lifts a tile above everything else.
    public func raise(_ tile: Tile) {
        tile.z = nextZ
        nextZ += 1
    }

    /// Moves a tile's settled position and re-files it. The caller owns
    /// `tile.x`/`y`, which are free to lag behind while easing.
    public func setTarget(_ tile: Tile, _ tx: Double, _ ty: Double) {
        if tx == tile.tx && ty == tile.ty { return }
        flag(tile.tx, tile.ty)
        flag(tx, ty)
        if CellCoord(containing: tx, ty) == CellCoord(containing: tile.tx, tile.ty) {
            tile.tx = tx
            tile.ty = ty
            return
        }
        bucketRemove(tile, atX: tile.tx, y: tile.ty)
        tile.tx = tx
        tile.ty = ty
        bucketAdd(tile)
    }

    public func setColor(_ tile: Tile, _ color: TileColor) {
        if color == tile.color { return }
        colorDelta(tile.color, -1)
        colorDelta(color, 1)
        tile.color = color
        flag(tile.tx, tile.ty)
    }

    public func clear() {
        let all = chunkCoords()
        for watch in watches { watch.restore(all) }
        colors.removeAll()
        buckets.removeAll()
        size = 0
    }

    // MARK: Watching for changes

    /// Starts a new watch. It begins with every current chunk flagged, since
    /// whatever it maintains has nothing yet.
    public func watch() -> ChunkWatch {
        let watch = ChunkWatch()
        watch.restore(chunkCoords())
        watches.append(watch)
        return watch
    }

    /// The autosave's view: chunks changed since the last call. If the save
    /// they were taken for fails, give them back with `restoreDirty`.
    public func takeDirty() -> Set<ChunkCoord> { saveWatch.take() }

    /// Has anything changed since the last `takeDirty`?
    public var hasUnsavedChanges: Bool { saveWatch.count > 0 }

    public func restoreDirty(_ chunks: some Sequence<ChunkCoord>) { saveWatch.restore(chunks) }

    // MARK: Chunks

    /// Every chunk that currently holds at least one tile.
    public func chunkCoords() -> Set<ChunkCoord> {
        Set(buckets.keys.map(ChunkCoord.init(of:)))
    }

    /// The tiles filed under a chunk (empty if it holds none).
    public func tiles(in chunk: ChunkCoord) -> [Tile] {
        let gx0 = chunk.x * chunkCells
        let gy0 = chunk.y * chunkCells
        var out: [Tile] = []
        for gx in gx0..<(gx0 + chunkCells) {
            for gy in gy0..<(gy0 + chunkCells) {
                if let bucket = buckets[CellCoord(x: gx, y: gy)] { out += bucket }
            }
        }
        return out
    }

    // MARK: Spatial queries

    public func makeIterator() -> FlattenSequence<Dictionary<CellCoord, [Tile]>.Values>.Iterator {
        buckets.values.joined().makeIterator()
    }

    /// Tiles whose settled center could be within `radius` of the point.
    /// Over-inclusive by up to one cell width; callers do their own exact check.
    public func near(_ x: Double, _ y: Double, radius: Double) -> [Tile] {
        let r = Int(Swift.min(Double(Self.maxNearCells), Swift.max(1, (radius / cellSize).rounded(.up))))
        let center = CellCoord(containing: x, y)
        var out: [Tile] = []
        for gx in (center.x - r)...(center.x + r) {
            for gy in (center.y - r)...(center.y + r) {
                if let bucket = buckets[CellCoord(x: gx, y: gy)] { out += bucket }
            }
        }
        return out
    }

    /// Visits every non-empty bucket overlapping the world rectangle. Cost is
    /// the smaller of "cells in the rectangle" and "buckets that exist", so a
    /// huge viewport over a sparse board doesn't walk millions of empty cells.
    /// `visit` returns true to stop the walk.
    public func forEachBucket(
        inMinX minX: Double, minY: Double, maxX: Double, maxY: Double,
        _ visit: (CellCoord, [Tile]) -> Bool
    ) {
        let lo = CellCoord(containing: minX, minY)
        let hi = CellCoord(containing: maxX, maxY)
        let cells = Double(hi.x - lo.x + 1) * Double(hi.y - lo.y + 1)
        if cells <= Double(buckets.count) {
            for gx in lo.x...hi.x {
                for gy in lo.y...hi.y {
                    let cell = CellCoord(x: gx, y: gy)
                    if let bucket = buckets[cell], visit(cell, bucket) { return }
                }
            }
        } else {
            for (cell, bucket) in buckets
            where cell.x >= lo.x && cell.x <= hi.x && cell.y >= lo.y && cell.y <= hi.y {
                if visit(cell, bucket) { return }
            }
        }
    }

    /// Is any tile filed in a bucket overlapping the rectangle? Stops at the first.
    public func hasTile(inMinX minX: Double, minY: Double, maxX: Double, maxY: Double) -> Bool {
        var found = false
        forEachBucket(inMinX: minX, minY: minY, maxX: maxX, maxY: maxY) { _, _ in
            found = true
            return true
        }
        return found
    }

    /// Tiles whose settled center lies inside the rectangle (inclusive).
    public func forEachTile(
        inMinX minX: Double, minY: Double, maxX: Double, maxY: Double, _ visit: (Tile) -> Void
    ) {
        forEachBucket(inMinX: minX, minY: minY, maxX: maxX, maxY: maxY) { _, tiles in
            for t in tiles where t.tx >= minX && t.tx <= maxX && t.ty >= minY && t.ty <= maxY {
                visit(t)
            }
            return false
        }
    }

    /// The tile closest to the point, or nil on an empty board. Searches
    /// outward in growing square rings of cells, falling back to one full pass
    /// only when the board is so sparse that ringing outward would cost more.
    public func nearest(_ x: Double, _ y: Double) -> Tile? {
        if size == 0 { return nil }
        let center = CellCoord(containing: x, y)
        var best: Tile?
        var bestD2 = Double.infinity
        func consider(_ bucket: [Tile]) {
            for t in bucket {
                let d2 = (t.tx - x) * (t.tx - x) + (t.ty - y) * (t.ty - y)
                if d2 < bestD2 {
                    bestD2 = d2
                    best = t
                }
            }
        }
        var r = 1
        while true {
            let side = 2 * r + 1
            if side * side > buckets.count {
                best = nil
                bestD2 = .infinity
                for bucket in buckets.values { consider(bucket) }
                return best
            }
            best = nil
            bestD2 = .infinity
            for gx in (center.x - r)...(center.x + r) {
                for gy in (center.y - r)...(center.y + r) {
                    if let bucket = buckets[CellCoord(x: gx, y: gy)] { consider(bucket) }
                }
            }
            // every cell within r of ours has been seen, so nothing closer than
            // r cells away can be hiding in an unsearched bucket
            let reach = Double(r) * cellSize
            if best != nil && bestD2 <= reach * reach { return best }
            r *= 2
        }
    }

    // MARK: Internals

    private func bucketAdd(_ tile: Tile) {
        buckets[CellCoord(containing: tile.tx, tile.ty), default: []].append(tile)
    }

    /// Swap-with-last removal: a bucket's order carries no meaning.
    @discardableResult
    private func bucketRemove(_ tile: Tile, atX x: Double, y: Double) -> Bool {
        let cell = CellCoord(containing: x, y)
        guard var bucket = buckets.removeValue(forKey: cell),
            let i = bucket.firstIndex(where: { $0 === tile })
        else { return false }
        bucket.swapAt(i, bucket.count - 1)
        bucket.removeLast()
        if !bucket.isEmpty { buckets[cell] = bucket }
        return true
    }

    private func flag(_ x: Double, _ y: Double) {
        let chunk = ChunkCoord(containing: x, y)
        for watch in watches { watch.add(chunk) }
    }

    private func colorDelta(_ color: TileColor, _ delta: Int) {
        let n = (colors[color] ?? 0) + delta
        if n > 0 { colors[color] = n } else { colors.removeValue(forKey: color) }
    }
}
