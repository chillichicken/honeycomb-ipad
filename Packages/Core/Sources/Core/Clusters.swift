import Foundation

public struct ClusterCounts: Equatable, Sendable {
    public var islands: Int
    public var largest: Int
}

/// Are two settled tiles snapped neighbors? Their centers sit `neighborDist`
/// apart, give or take a few px of easing/rounding slop, compared as a squared
/// window with no sqrt per pair.
@inline(__always)
func areAdjacent(_ a: Tile, _ b: Tile, neighborDist d: Double) -> Bool {
    let d2 = dist2(a.tx, a.ty, b.tx, b.ty)
    return d2 > (d - 3) * (d - 3) && d2 < (d + 3) * (d + 3)
}

/// Full flood fill over snapped adjacency: separate islands and the size of the
/// biggest connected build. Simple and whole-board (O(n)), so it's the test
/// oracle for `ClusterTracker`, not something to call every frame.
public func computeClusters(_ store: TileStore, shape: TileShape) -> ClusterCounts {
    let d = shape.neighborDist
    var visited = Set<Tile>()
    var counts = ClusterCounts(islands: 0, largest: 0)
    for start in store where !visited.contains(start) {
        counts.islands += 1
        var size = 0
        var stack = [start]
        visited.insert(start)
        while let cur = stack.popLast() {
            size += 1
            for o in store.near(cur.tx, cur.ty, radius: d)
            where !visited.contains(o) && areAdjacent(cur, o, neighborDist: d) {
                visited.insert(o)
                stack.append(o)
            }
        }
        counts.largest = Swift.max(counts.largest, size)
    }
    return counts
}

/// Counts islands and the biggest one without ever scanning the whole board in
/// one go, so it works at any size:
///
///  1. Each chunk is labeled on its own (a flood fill that only follows neighbors
///     inside the chunk), giving it a few local components. Tiles that touch a
///     tile of another chunk are remembered as "border" tiles.
///  2. For every chunk, its border tiles are matched with those next door,
///     producing edges between (chunk, component) nodes.
///  3. A union-find over those nodes merges components that continue across chunk
///     borders. Its size is the number of components, tiny next to the tile count.
///
/// Only chunks the store reports as changed are re-labeled (and their neighbors'
/// edges redone), and work runs in small time slices, so a big board costs a few
/// ms per call for a while rather than one long stall. `counts` updates once
/// everything pending is processed; until then it shows the previous answer.
public final class ClusterTracker {
    private struct ChunkInfo {
        var sizes: [Int]  // tile count per local component
        var border: [Tile: Int]  // tiles touching another chunk -> their local component
        var edges: [Edge] = []
    }

    private struct Edge {
        let component: Int
        let otherChunk: ChunkCoord
        let otherComponent: Int
    }

    /// The chunks within `radius` of `chunk` (including itself).
    private static func around(_ chunk: ChunkCoord, radius r: Int) -> [ChunkCoord] {
        (-r...r).flatMap { dx in (-r...r).map { dy in ChunkCoord(x: chunk.x + dx, y: chunk.y + dy) } }
    }

    public private(set) var counts = ClusterCounts(islands: 0, largest: 0)
    /// False until the first full pass has published.
    public private(set) var ready = false
    /// Bumps whenever `counts` is republished.
    public private(set) var version = 0

    private let store: TileStore
    private let watch: ChunkWatch
    private var infos: [ChunkCoord: ChunkInfo] = [:]
    private var labelQueue = Set<ChunkCoord>()
    private var edgeQueue = Set<ChunkCoord>()
    private var shape: TileShape?
    private var stale = true

    public init(store: TileStore) {
        self.store = store
        self.watch = store.watch()
    }

    /// Does up to `budget` of pending work (at least one chunk, if any is pending).
    public func step(shape: TileShape, budget: Duration) {
        if shape.id != self.shape?.id {
            // adjacency depends on tile size: start over
            self.shape = shape
            infos.removeAll()
            labelQueue = store.chunkCoords()
            edgeQueue = labelQueue
            stale = true
        }
        for chunk in watch.take() {
            // A change can add or remove a tile that touches a neighboring chunk, so the
            // neighbors' border lists (and the numbering of their components) may be stale
            // too: re-label the 3x3 around it, and redo the edges of the 5x5, since every
            // chunk next to a re-labeled one holds edges that point at its old numbering.
            labelQueue.insert(chunk)
            for other in Self.around(chunk, radius: 1) where infos[other] != nil { labelQueue.insert(other) }
            for other in Self.around(chunk, radius: 2) where infos[other] != nil || other == chunk { edgeQueue.insert(other) }
            stale = true
        }
        guard stale else { return }

        let deadline = ContinuousClock.now + budget
        repeat {
            // labels come strictly before edges: an edge needs its neighbor's labels current
            if let chunk = labelQueue.first {
                labelQueue.remove(chunk)
                label(chunk, neighborDist: shape.neighborDist)
            } else if let chunk = edgeQueue.first {
                edgeQueue.remove(chunk)
                connect(chunk, neighborDist: shape.neighborDist)
            } else {
                break
            }
        } while ContinuousClock.now < deadline

        if labelQueue.isEmpty && edgeQueue.isEmpty { publish() }
    }

    private func label(_ chunk: ChunkCoord, neighborDist d: Double) {
        let tiles = store.tiles(in: chunk)
        if tiles.isEmpty {
            infos[chunk] = nil
            return
        }
        var labels: [Tile: Int] = [:]
        var sizes: [Int] = []
        var border: [Tile: Int] = [:]
        for start in tiles where labels[start] == nil {
            let comp = sizes.count
            sizes.append(0)
            labels[start] = comp
            var stack = [start]
            while let cur = stack.popLast() {
                sizes[comp] += 1
                for o in store.near(cur.tx, cur.ty, radius: d) where areAdjacent(cur, o, neighborDist: d) {
                    if ChunkCoord(containing: o.tx, o.ty) != chunk {
                        border[cur] = comp
                    } else if labels[o] == nil {
                        labels[o] = comp
                        stack.append(o)
                    }
                }
            }
        }
        infos[chunk] = ChunkInfo(sizes: sizes, border: border)
    }

    private func connect(_ chunk: ChunkCoord, neighborDist d: Double) {
        guard var info = infos[chunk] else { return }
        var edges: [Edge] = []
        for (a, ca) in info.border {
            for o in store.near(a.tx, a.ty, radius: d) where areAdjacent(a, o, neighborDist: d) {
                let otherChunk = ChunkCoord(containing: o.tx, o.ty)
                if otherChunk == chunk { continue }
                if let cb = infos[otherChunk]?.border[o] {
                    edges.append(Edge(component: ca, otherChunk: otherChunk, otherComponent: cb))
                }
            }
        }
        info.edges = edges
        infos[chunk] = info
    }

    private func publish() {
        var base: [ChunkCoord: Int] = [:]
        var total = 0
        for (chunk, info) in infos {
            base[chunk] = total
            total += info.sizes.count
        }
        var parent = Array(0..<total)
        var size = [Int](repeating: 0, count: total)
        for (chunk, info) in infos {
            for (i, s) in info.sizes.enumerated() { size[base[chunk]! + i] = s }
        }
        func find(_ start: Int) -> Int {
            var x = start
            while parent[x] != x {
                parent[x] = parent[parent[x]]  // path halving
                x = parent[x]
            }
            return x
        }
        for (chunk, info) in infos {
            for e in info.edges {
                guard let other = base[e.otherChunk] else { continue }
                let ra = find(base[chunk]! + e.component)
                let rb = find(other + e.otherComponent)
                if ra == rb { continue }
                parent[rb] = ra
                size[ra] += size[rb]
            }
        }
        var counts = ClusterCounts(islands: 0, largest: 0)
        for i in 0..<total where parent[i] == i {
            counts.islands += 1
            counts.largest = Swift.max(counts.largest, size[i])
        }
        self.counts = counts
        ready = true
        stale = false
        version += 1
    }
}
