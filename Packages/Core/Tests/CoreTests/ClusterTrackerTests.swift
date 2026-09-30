import Foundation
import Testing
@testable import Core

private let chunk = chunkWorld
private let allShapes: [TileShape] = ShapeID.allCases.map(TileShape.of)

private func drain(_ tracker: ClusterTracker, _ shape: TileShape) -> ClusterCounts {
    tracker.step(shape: shape, budget: .seconds(3600))
    return tracker.counts
}

@Suite struct ClusterTrackerTests {
    @Test func isEmptyAndReadyOnAnEmptyBoard() {
        let t = ClusterTracker(store: TileStore())
        #expect(drain(t, .hexagon) == ClusterCounts(islands: 0, largest: 0))
        #expect(t.ready)
    }

    @Test func joinsAnIslandThatRunsAcrossSeveralChunks() {
        let d = TileShape.hexagon.neighborDist
        let store = TileStore()
        var x = -chunk
        while x < chunk * 2 {  // a row over 3+ chunks
            store.add(makeTile(x, 0))
            x += d
        }
        store.add(makeTile(0, 5000))  // and one loner
        let got = drain(ClusterTracker(store: store), .hexagon)
        #expect(got == computeClusters(store, shape: .hexagon))
        #expect(got.islands == 2)
    }

    @Test(arguments: allShapes)
    func agreesWithTheFullFloodFillOnRandomBoards(shape: TileShape) {
        for seed in 1...6 {
            let store = randomBoard(shape, seed: UInt64(seed), builds: 25, tilesPerBuild: 400, spread: chunk * 4)
            #expect(drain(ClusterTracker(store: store), shape) == computeClusters(store, shape: shape))
        }
    }

    @Test(arguments: allShapes)
    func staysRightThroughRandomEdits(shape: TileShape) {
        let store = randomBoard(shape, seed: 99, builds: 15, tilesPerBuild: 500, spread: chunk * 3)
        let tracker = ClusterTracker(store: store)
        _ = drain(tracker, shape)
        var rng = SeededRandom(seed: 5)
        for round in 0..<25 {
            let tiles = Array(store)
            for _ in 0..<30 { store.remove(tiles[Int(rng.next() * Double(tiles.count))]) }  // holes / split islands
            if round % 3 == 0 {
                let extra = randomBoard(shape, seed: UInt64(round + 200), builds: 2, tilesPerBuild: 80, spread: chunk * 3)
                for e in Array(extra) where store.near(e.tx, e.ty, radius: 10).isEmpty { store.add(e) }
            }
            #expect(drain(tracker, shape) == computeClusters(store, shape: shape))
        }
    }

    @Test func followsAShapeChange() {
        let store = randomBoard(.hexagon, seed: 3, builds: 5, tilesPerBuild: 100, spread: chunk)
        let tracker = ClusterTracker(store: store)
        _ = drain(tracker, .hexagon)
        // the same points read as a different lattice: results are recomputed, not carried over
        #expect(drain(tracker, .triangle) == computeClusters(store, shape: .triangle))
    }

    @Test func timeSlicesWithAZeroBudgetItStillMakesProgressAndConverges() {
        let store = randomBoard(.hexagon, seed: 8, builds: 30, tilesPerBuild: 300, spread: chunk * 4)
        let tracker = ClusterTracker(store: store)
        var steps = 0
        while tracker.version == 0 && steps < 100_000 {
            tracker.step(shape: .hexagon, budget: .zero)
            steps += 1
        }
        #expect(steps > 1)  // it didn't do everything in one go
        #expect(tracker.counts == computeClusters(store, shape: .hexagon))
    }

    @Test func keepsTheLastAnswerWhileNewWorkIsPendingThenRepublishes() {
        let store = randomBoard(.hexagon, seed: 4, builds: 5, tilesPerBuild: 200, spread: chunk * 2)
        let tracker = ClusterTracker(store: store)
        _ = drain(tracker, .hexagon)
        let before = tracker.version
        store.add(makeTile(chunk * 9, chunk * 9))
        #expect(drain(tracker, .hexagon) == computeClusters(store, shape: .hexagon))
        #expect(tracker.version > before)
    }

    @Test func doesNothingWhenNothingChanged() {
        let store = randomBoard(.hexagon, seed: 4, builds: 5, tilesPerBuild: 200, spread: chunk * 2)
        let tracker = ClusterTracker(store: store)
        _ = drain(tracker, .hexagon)
        let v = tracker.version
        _ = drain(tracker, .hexagon)
        _ = drain(tracker, .hexagon)
        #expect(tracker.version == v)
    }

    @Test(arguments: allShapes)
    func growingABuildAcrossChunkBordersStaysOneIsland(shape: TileShape) {
        // "+" from the origin, where four chunks meet: a new tile lands next to a chunk
        // that itself did not change, and the two halves must still join
        let board = Board(shape: shape)
        board.spawnTile(color: 1, cameraCenter: .zero)
        let tracker = ClusterTracker(store: board.store)
        for i in 0..<120 {
            board.spawnTile(color: 2, cameraCenter: .zero)
            board.easeTowardTargets(factor: 0.3)
            if i % 3 == 0 { tracker.step(shape: shape, budget: .seconds(10)) }  // like a frame tick between presses
            if i % 17 == 0 {
                #expect(drain(tracker, shape) == computeClusters(board.store, shape: shape))
            }
        }
        #expect(drain(tracker, shape) == ClusterCounts(islands: 1, largest: 121))
    }

    @Test func aTileAddedBesideAnUnchangedChunkJoinsItsIsland() {
        let d = TileShape.hexagon.neighborDist
        let store = TileStore()
        // a row ending exactly at a chunk border, then one more tile across it
        var x = -chunk + 10
        while x < 0 {
            store.add(makeTile(x, 10))
            x += d
        }
        let tracker = ClusterTracker(store: store)
        #expect(drain(tracker, .hexagon).islands == 1)
        store.add(makeTile(x, 10))  // first tile of the next chunk over
        #expect(drain(tracker, .hexagon) == computeClusters(store, shape: .hexagon))
        #expect(tracker.counts.islands == 1)
    }
}
