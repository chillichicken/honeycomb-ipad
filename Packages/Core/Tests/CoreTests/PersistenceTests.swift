import Foundation
import Testing
@testable import Core

// MARK: Helpers

/// Wraps a real store, records every save request, and can be told to fail.
final class SpyStore: PuzzleStoring, @unchecked Sendable {
    struct Failure: Error {}
    let inner: PuzzleStoring
    var saves: [SaveRequest] = []
    var failNext = false

    init(_ inner: PuzzleStoring) { self.inner = inner }

    func list() async throws -> [PuzzleMeta] { try await inner.list() }
    func load(id: String) async throws -> StoredPuzzle { try await inner.load(id: id) }
    func remove(id: String) async throws { try await inner.remove(id: id) }
    func save(_ request: SaveRequest) async throws -> String {
        if failNext {
            failNext = false
            throw Failure()
        }
        saves.append(request)
        return try await inner.save(request)
    }
    var last: SaveRequest { saves[saves.count - 1] }
}

func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory.appendingPathComponent("core-tests-\(UUID().uuidString)")
}

/// Order-independent fingerprint of the board's settled content.
func fingerprint(_ board: Board) -> [String] {
    board.store.map { String(format: "%.3f,%.3f,%06X,%d", $0.tx, $0.ty, $0.color, $0.orientation) }.sorted()
}

/// Tiles spread over a 3x3 block of chunks.
func spreadBoard() -> Board {
    var tiles: [Tile] = []
    for cx in 0..<3 {
        for cy in 0..<3 {
            for i in 0..<5 {
                tiles.append(makeTile(
                    Double(cx) * chunkWorld + 100 + Double(i) * 80, Double(cy) * chunkWorld + 100,
                    color: UInt32(i * 16 + cx)))
            }
        }
    }
    return makeBoard(tiles: tiles)
}

@MainActor
struct Rig {
    let spy: SpyStore
    let persistence: BoardPersistence
    let folder = temporaryFolder()

    init() {
        spy = SpyStore(FilePuzzleStore(root: folder))
        persistence = BoardPersistence(puzzles: spy)
    }

    func chunkFiles(_ id: String) -> [String] {
        let dir = folder.appendingPathComponent(id).appendingPathComponent("chunks")
        return ((try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []).sorted()
    }
}

// MARK: Chunk encoding

@Suite struct ChunkDataTests {
    @Test func roundTripsPositionsExactlyColorsAndOrientations() throws {
        let tiles = [
            makeTile(1.23456789012345, -9.87654321, orientation: 1, color: 0xABCDEF),
            makeTile(1e6, -1e6, orientation: 0, color: 0x000001),
        ]
        let back = try ChunkData(serialized: ChunkData(tiles: tiles).serialized()).makeTiles()
        #expect(back.map(\.tx) == tiles.map(\.tx))
        #expect(back.map(\.ty) == tiles.map(\.ty))
        #expect(back.map(\.color) == tiles.map(\.color))
        #expect(back.map(\.orientation) == tiles.map(\.orientation))
        #expect(back.allSatisfy { $0.x == $0.tx && $0.y == $0.ty })  // at rest
    }

    @Test func handlesAnEmptyChunk() throws {
        let data = ChunkData(tiles: [])
        #expect(try ChunkData(serialized: data.serialized()).count == 0)
    }

    @Test func storesTheSettledPositionNotTheMidEaseOne() {
        let t = Tile(x: 0, y: 0, color: 1)
        let store = TileStore()
        store.add(t)
        store.setTarget(t, 100, 50)
        let data = ChunkData(tiles: [t])
        #expect(data.x == [100] && data.y == [50])
    }

    @Test func rejectsTruncatedOrForeignData() {
        let good = ChunkData(tiles: [makeTile(1, 2)]).serialized()
        #expect(throws: CorruptChunkError.self) { try ChunkData(serialized: good.dropLast()) }
        #expect(throws: CorruptChunkError.self) { try ChunkData(serialized: Data("nonsense!".utf8)) }
        #expect(throws: CorruptChunkError.self) { try ChunkData(serialized: Data()) }
    }
}

// MARK: Saving and loading

@MainActor
@Suite struct BoardPersistenceTests {
    @Test func savesANewPuzzleInFullAndLoadsBackTheIdenticalBoard() async throws {
        let rig = Rig()
        let board = spreadBoard()
        let id = try await rig.persistence.save(board, id: nil, name: "p", activeMs: 5)
        let loaded = Board()
        _ = try await rig.persistence.load(id: id, into: loaded)
        #expect(fingerprint(loaded) == fingerprint(board))
        let meta = try #require(try await rig.spy.list().first)
        #expect(meta.id == id && meta.name == "p" && meta.tileCount == 45 && meta.activeMs == 5)
    }

    @Test func remembersTheShape() async throws {
        let rig = Rig()
        let id = try await rig.persistence.save(
            makeBoard(.triangle, tiles: [makeTile(0, 0, orientation: 1)]), id: nil, name: "t", activeMs: 0)
        let loaded = Board()
        _ = try await rig.persistence.load(id: id, into: loaded)
        #expect(loaded.shape.id == .triangle)
    }

    @Test func writesOnlyTheChunksAnEditTouched() async throws {
        let rig = Rig()
        let board = spreadBoard()
        let id = try await rig.persistence.save(board, id: nil, name: "p", activeMs: 0)
        #expect(rig.spy.last.writes.count == 9)

        board.store.setColor(Array(board.store)[0], 0xFFFFFF)
        _ = try await rig.persistence.save(board, id: id, name: "p", activeMs: 0)
        #expect(rig.spy.last.writes.count == 1)
        #expect(rig.spy.last.deletes.isEmpty)
        #expect(!rig.spy.last.replaceAll)

        _ = try await rig.persistence.save(board, id: id, name: "p", activeMs: 0)  // nothing changed
        #expect(rig.spy.last.writes.isEmpty)
    }

    @Test func rewritesBothChunksWhenATileMovesAcrossABoundary() async throws {
        let rig = Rig()
        let board = spreadBoard()
        let id = try await rig.persistence.save(board, id: nil, name: "p", activeMs: 0)
        let t = try #require(board.store.nearest(100, 100))
        board.store.setTarget(t, chunkWorld + 500, 100)
        _ = try await rig.persistence.save(board, id: id, name: "p", activeMs: 0)
        #expect(rig.spy.last.writes.count == 2)
    }

    @Test func deletesTheFileOfAChunkThatEmptied() async throws {
        let rig = Rig()
        let board = spreadBoard()
        let id = try await rig.persistence.save(board, id: nil, name: "p", activeMs: 0)
        #expect(rig.chunkFiles(id).count == 9)
        board.remove(board.store.tiles(in: ChunkCoord(x: 1, y: 1)))
        _ = try await rig.persistence.save(board, id: id, name: "p", activeMs: 0)
        #expect(rig.spy.last.deletes == [ChunkCoord(x: 1, y: 1)])
        #expect(rig.chunkFiles(id).count == 8)
        let loaded = Board()
        _ = try await rig.persistence.load(id: id, into: loaded)
        #expect(fingerprint(loaded) == fingerprint(board))
    }

    @Test func roundTripsAnEmptyBoard() async throws {
        let rig = Rig()
        let id = try await rig.persistence.save(Board(), id: nil, name: "e", activeMs: 0)
        let loaded = makeBoard(tiles: [makeTile(0, 0)])
        _ = try await rig.persistence.load(id: id, into: loaded)
        #expect(loaded.store.size == 0)
    }

    @Test func keepsTheChangesFlaggedWhenASaveFailsAndRetriesThem() async throws {
        let rig = Rig()
        let board = spreadBoard()
        let id = try await rig.persistence.save(board, id: nil, name: "p", activeMs: 0)
        board.store.setColor(Array(board.store)[0], 0xFFFFFF)
        rig.spy.failNext = true
        await #expect(throws: SpyStore.Failure.self) {
            _ = try await rig.persistence.save(board, id: id, name: "p", activeMs: 0)
        }
        _ = try await rig.persistence.save(board, id: id, name: "p", activeMs: 0)
        #expect(rig.spy.last.writes.count == 1)
    }

    @Test func aFailedFullSaveStaysAFullSave() async throws {
        let rig = Rig()
        let board = spreadBoard()
        rig.spy.failNext = true
        await #expect(throws: SpyStore.Failure.self) {
            _ = try await rig.persistence.save(board, id: nil, name: "p", activeMs: 0)
        }
        _ = try await rig.persistence.save(board, id: nil, name: "p", activeMs: 0)
        #expect(rig.spy.last.writes.count == 9)
    }

    @Test func saveAsNewWritesEverythingUnderANewIDAndLeavesTheOriginalAlone() async throws {
        let rig = Rig()
        let board = spreadBoard()
        let original = try await rig.persistence.save(board, id: nil, name: "a", activeMs: 0)
        let copy = try await rig.persistence.save(board, id: nil, name: "b", activeMs: 0)
        #expect(copy != original)
        #expect(rig.spy.last.writes.count == 9)
        #expect(rig.chunkFiles(original).count == 9 && rig.chunkFiles(copy).count == 9)
        #expect(try await rig.spy.list().count == 2)
    }

    @Test func afterLoadingNothingIsDirtyUntilItsEdited() async throws {
        let rig = Rig()
        let id = try await rig.persistence.save(spreadBoard(), id: nil, name: "p", activeMs: 0)
        let loaded = Board()
        _ = try await rig.persistence.load(id: id, into: loaded)
        _ = try await rig.persistence.save(loaded, id: id, name: "p", activeMs: 0)
        #expect(rig.spy.last.writes.isEmpty)
        loaded.store.setColor(Array(loaded.store)[0], 0xFFFFFF)
        _ = try await rig.persistence.save(loaded, id: id, name: "p", activeMs: 0)
        #expect(rig.spy.last.writes.count == 1)
    }

    @Test func savingADifferentPuzzleIDIsAFullWrite() async throws {
        let rig = Rig()
        let board = spreadBoard()
        let a = try await rig.persistence.save(board, id: nil, name: "a", activeMs: 0)
        let b = try await rig.persistence.save(board, id: nil, name: "b", activeMs: 0)
        _ = try await rig.persistence.save(board, id: a, name: "a", activeMs: 0)  // b was the last synced
        #expect(rig.spy.last.writes.count == 9 && rig.spy.last.replaceAll)
        _ = b
    }

    @Test func fullRewriteDropsChunksThatNoLongerExist() async throws {
        let rig = Rig()
        let board = spreadBoard()
        let id = try await rig.persistence.save(board, id: nil, name: "p", activeMs: 0)
        let b = try await rig.persistence.save(board, id: nil, name: "other", activeMs: 0)  // makes `id` stale
        board.remove(board.store.tiles(in: ChunkCoord(x: 2, y: 2)))
        _ = try await rig.persistence.save(board, id: id, name: "p", activeMs: 0)  // full: chunk (2,2) is gone
        #expect(rig.chunkFiles(id).count == 8)
        #expect(rig.chunkFiles(b).count == 9)
    }

    @Test func removingAPuzzleRemovesItsChunksAndOnlyItsOwn() async throws {
        let rig = Rig()
        let a = try await rig.persistence.save(spreadBoard(), id: nil, name: "a", activeMs: 0)
        let b = try await rig.persistence.save(spreadBoard(), id: nil, name: "b", activeMs: 0)
        try await rig.spy.remove(id: a)
        #expect(rig.chunkFiles(a).isEmpty)
        #expect(rig.chunkFiles(b).count == 9)
        #expect(try await rig.spy.list().map(\.id) == [b])
        await #expect(throws: PuzzleNotFoundError.self) { _ = try await rig.spy.load(id: a) }
    }

    @Test func listsMostRecentlySavedFirstAndKeepsCreatedAt() async throws {
        let rig = Rig()
        let a = try await rig.persistence.save(makeBoard(tiles: [makeTile(0, 0)]), id: nil, name: "a", activeMs: 0)
        let created = try #require(try await rig.spy.list().first).createdAt
        let b = try await rig.persistence.save(makeBoard(tiles: [makeTile(0, 0)]), id: nil, name: "b", activeMs: 0)
        #expect(try await rig.spy.list().map(\.id) == [b, a])
        let board = makeBoard(tiles: [makeTile(0, 0)])
        _ = try await rig.persistence.save(board, id: a, name: "a2", activeMs: 9)
        let listed = try await rig.spy.list()
        #expect(listed.map(\.id) == [a, b])
        #expect(listed[0].createdAt == created && listed[0].name == "a2" && listed[0].activeMs == 9)
    }

    @Test func returnsTheCentroidForTheCamera() async throws {
        let rig = Rig()
        let board = makeBoard(tiles: [makeTile(0, 0), makeTile(100, 200)])
        let id = try await rig.persistence.save(board, id: nil, name: "c", activeMs: 0)
        let at = try await rig.persistence.load(id: id, into: Board())
        #expect(at == SIMD2(50, 100))
        #expect(try await rig.persistence.load(id: try await rig.persistence.save(Board(), id: nil, name: "e", activeMs: 0), into: Board()) == .zero)
    }

    @Test func aBigBoardSavesAndLoadsAndAOneTileEditStaysOneChunk() async throws {
        let rig = Rig()
        let board = makeBoard()
        let d = TileShape.hexagon.neighborDist
        for i in 0..<100_000 {
            board.store.add(makeTile(Double(i % 400) * d, Double(i / 400) * d, color: UInt32(i % 7)))
        }
        let id = try await rig.persistence.save(board, id: nil, name: "big", activeMs: 0)
        let loaded = Board()
        _ = try await rig.persistence.load(id: id, into: loaded)
        #expect(loaded.store.size == 100_000)
        #expect(loaded.store.colorCounts == board.store.colorCounts)
        loaded.store.setColor(Array(loaded.store)[0], 0xFFFFFF)
        _ = try await rig.persistence.save(loaded, id: id, name: "big", activeMs: 0)
        #expect(rig.spy.last.writes.count == 1)
    }

    @Test func stackingOrderSurvivesASaveAndLoad() async throws {
        let rig = Rig()
        let bottom = makeTile(10, 10, color: 1), middle = makeTile(10, 10, color: 2), top = makeTile(10, 10, color: 3)
        let board = makeBoard(tiles: [bottom, middle, top])
        board.store.raise(bottom)  // order is now middle, top, bottom
        let id = try await rig.persistence.save(board, id: nil, name: "z", activeMs: 0)
        let loaded = Board()
        _ = try await rig.persistence.load(id: id, into: loaded)
        let topFirst = loaded.store.near(10, 10, radius: 1).sorted { $0.z > $1.z }.map(\.color)
        #expect(topFirst == [1, 3, 2])
    }
}
