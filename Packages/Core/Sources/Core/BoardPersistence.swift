import Foundation

/// Saves and loads a `Board` through a `PuzzleStoring`.
///
/// When the stored copy of a puzzle is known to match the board except for what
/// the tile store has flagged dirty, only the dirty chunks are written (or
/// deleted, if they emptied), so a one-tile edit on a huge board is one small
/// file. Otherwise (a new puzzle, "save as new") every chunk is written.
@MainActor
public final class BoardPersistence {
    private let puzzles: PuzzleStoring
    /// The puzzle whose stored copy is known to match the store's chunks.
    private var syncedPuzzleID: String?

    public init(puzzles: PuzzleStoring) {
        self.puzzles = puzzles
    }

    /// Saves the board and returns the puzzle's id. Pass `id: nil` to create a
    /// new puzzle (also how "save as new" branches off an existing one).
    public func save(_ board: Board, id: String?, name: String, activeMs: Int) async throws -> String {
        let store = board.store
        let full = id == nil || syncedPuzzleID != id
        let dirty = store.takeDirty()  // edits made while the write is in flight land in a fresh set
        let chunks = full ? store.chunkCoords() : dirty

        var writes: [ChunkRecord] = []
        var deletes: [ChunkCoord] = []
        for chunk in chunks {
            // saved bottom-to-top, so a load (which restamps stacking order in
            // sequence) keeps overlapping tiles the way they were
            let tiles = store.tiles(in: chunk).sorted { $0.z < $1.z }
            if tiles.isEmpty {
                deletes.append(chunk)
            } else {
                writes.append(ChunkRecord(coord: chunk, data: ChunkData(tiles: tiles)))
            }
        }

        let request = SaveRequest(
            id: id, name: name, shape: board.shape.id, activeMs: activeMs, tileCount: store.size,
            writes: writes, deletes: deletes, replaceAll: full && id != nil)
        do {
            let saved = try await puzzles.save(request)
            syncedPuzzleID = saved
            return saved
        } catch {
            store.restoreDirty(dirty)  // nothing was written: the next attempt must still cover these
            throw error
        }
    }

    /// Replaces the board with a saved puzzle, at its saved world coordinates.
    /// Returns where the camera should look (the tiles' centroid).
    public func load(id: String, into board: Board) async throws -> SIMD2<Double> {
        let stored = try await puzzles.load(id: id)
        let tiles = stored.chunks.flatMap { $0.data.makeTiles() }
        board.replace(shape: .of(stored.meta.shape), tiles: tiles)
        // the store now matches what's saved, so nothing is dirty until it's edited
        _ = board.store.takeDirty()
        syncedPuzzleID = id
        return Self.centroid(of: tiles)
    }

    static func centroid(of tiles: [Tile]) -> SIMD2<Double> {
        guard !tiles.isEmpty else { return .zero }
        var sum = SIMD2<Double>.zero
        for t in tiles { sum += SIMD2(t.tx, t.ty) }
        return sum / Double(tiles.count)
    }
}
