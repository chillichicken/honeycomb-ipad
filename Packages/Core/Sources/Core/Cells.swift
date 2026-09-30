import Foundation

/// The store buckets tiles into square cells two tile-widths across: a bucket
/// holds a couple of tiles for every shape, and a neighbor lookup is just the
/// 3x3 cells around a point.
public let cellSize: Double = tileSize * 2

/// Persistence works in chunks: square regions of `chunkCells` x `chunkCells` cells.
public let chunkCells = 32

/// World size of one chunk's side.
public let chunkWorld: Double = cellSize * Double(chunkCells)

public struct CellCoord: Hashable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public init(containing wx: Double, _ wy: Double) {
        self.init(x: Int((wx / cellSize).rounded(.down)), y: Int((wy / cellSize).rounded(.down)))
    }
}

public struct ChunkCoord: Hashable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }

    public init(of cell: CellCoord) {
        self.init(x: floorDiv(cell.x, chunkCells), y: floorDiv(cell.y, chunkCells))
    }

    /// The chunk whose cells hold a tile settled at this position.
    public init(containing wx: Double, _ wy: Double) {
        self.init(of: CellCoord(containing: wx, wy))
    }
}

/// Integer division rounding toward negative infinity (Swift's `/` truncates).
func floorDiv(_ a: Int, _ b: Int) -> Int {
    let q = a / b
    return (a % b != 0 && (a < 0) != (b < 0)) ? q - 1 : q
}
