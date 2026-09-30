import Foundation

/// Listing info for a saved puzzle. Reading the list never touches the boards.
public struct PuzzleMeta: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    public var shape: ShapeID
    public var createdAt: Date
    public var updatedAt: Date
    /// Cumulative active editing time, across all sessions.
    public var activeMs: Int
    public var tileCount: Int
}

public struct ChunkRecord: Equatable, Sendable {
    public let coord: ChunkCoord
    public let data: ChunkData

    public init(coord: ChunkCoord, data: ChunkData) {
        self.coord = coord
        self.data = data
    }
}

public struct SaveRequest: Sendable {
    /// nil creates a new puzzle.
    public var id: String?
    public var name: String
    public var shape: ShapeID
    public var activeMs: Int
    public var tileCount: Int
    /// Chunks to create or overwrite.
    public var writes: [ChunkRecord]
    /// Chunks that are now empty.
    public var deletes: [ChunkCoord]
    /// Drop every existing chunk of this puzzle that isn't in `writes` (a full rewrite).
    public var replaceAll: Bool

    public init(
        id: String? = nil, name: String, shape: ShapeID, activeMs: Int, tileCount: Int,
        writes: [ChunkRecord], deletes: [ChunkCoord], replaceAll: Bool
    ) {
        self.id = id
        self.name = name
        self.shape = shape
        self.activeMs = activeMs
        self.tileCount = tileCount
        self.writes = writes
        self.deletes = deletes
        self.replaceAll = replaceAll
    }
}

public struct StoredPuzzle: Sendable {
    public let meta: PuzzleMeta
    public let chunks: [ChunkRecord]
}

public struct PuzzleNotFoundError: Error, Equatable {}

/// Where puzzles live. The only thing that knows *where*, so the backend (a
/// folder today, iCloud tomorrow) can change without any caller changing.
public protocol PuzzleStoring: Sendable {
    /// Most recently saved first.
    func list() async throws -> [PuzzleMeta]
    /// Returns the puzzle's id.
    func save(_ request: SaveRequest) async throws -> String
    func load(id: String) async throws -> StoredPuzzle
    func remove(id: String) async throws
}
