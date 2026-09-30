import Foundation
@testable import Core

/// Deterministic uniform [0, 1) numbers, so randomized tests are reproducible.
struct SeededRandom {
    private var state: UInt64

    init(seed: UInt64) { state = seed }

    mutating func next() -> Double {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        z ^= z >> 31
        return Double(z >> 11) / Double(1 << 53)
    }
}

func makeTile(_ tx: Double, _ ty: Double, orientation: Int = 0, color: TileColor = 0xFF0000) -> Tile {
    Tile(x: tx, y: ty, color: color, orientation: orientation)
}

func randomStore(_ n: Int, spread: Double, seed: UInt64 = 7)
    -> (store: TileStore, tiles: [Tile], rng: SeededRandom)
{
    var rng = SeededRandom(seed: seed)
    let store = TileStore()
    var tiles: [Tile] = []
    for _ in 0..<n {
        let t = makeTile((rng.next() - 0.5) * spread, (rng.next() - 0.5) * spread)
        store.add(t)
        tiles.append(t)
    }
    return (store, tiles, rng)
}

func ids(_ tiles: some Sequence<Tile>) -> Set<ObjectIdentifier> {
    Set(tiles.map(ObjectIdentifier.init))
}

func contains(_ tiles: [Tile], _ t: Tile) -> Bool {
    tiles.contains { $0 === t }
}

func makeBoard(_ shape: Shape = .hexagon, tiles: [Tile] = []) -> Board {
    let board = Board(shape: shape)
    for t in tiles { board.store.add(t) }
    return board
}

/// Grows a disc of tiles by walking the shape's lattice from the origin.
func lattice(block shape: Shape, radiusTiles: Double) -> Board {
    let board = Board(shape: shape)
    var seen: Set<[Int]> = [[0, 0]]
    var queue: [(Double, Double, Int)] = [(0, 0, 0)]
    while let (x, y, o) = queue.popLast() {
        if hypot(x, y) > radiusTiles * shape.neighborDist { continue }
        board.store.add(makeTile(x, y, orientation: o))
        for s in shape.neighborSlots[o] {
            let nx = x + s.dx, ny = y + s.dy
            if seen.insert([Int(nx.rounded()), Int(ny.rounded())]).inserted {
                queue.append((nx, ny, s.orientation))
            }
        }
    }
    return board
}

/// Grows random connected builds by walking the shape's lattice, so borders
/// between chunks get crossed.
func randomBoard(
    _ shape: Shape, seed: UInt64, builds: Int, tilesPerBuild: Int, spread: Double
) -> TileStore {
    var rng = SeededRandom(seed: seed)
    let store = TileStore()
    var taken = Set<[Int]>()
    for _ in 0..<builds {
        let ox = (rng.next() - 0.5) * spread
        let oy = (rng.next() - 0.5) * spread
        var frontier: [(Double, Double, Int)] = [(ox, oy, 0)]
        var n = 0
        while n < tilesPerBuild && !frontier.isEmpty {
            n += 1
            let (x, y, o) = frontier.remove(at: Int(rng.next() * Double(frontier.count)))
            guard taken.insert([Int(x.rounded()), Int(y.rounded())]).inserted else { continue }
            store.add(makeTile(x, y, orientation: o))
            for s in shape.neighborSlots[o] { frontier.append((x + s.dx, y + s.dy, s.orientation)) }
        }
    }
    return store
}
