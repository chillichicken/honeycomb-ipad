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
