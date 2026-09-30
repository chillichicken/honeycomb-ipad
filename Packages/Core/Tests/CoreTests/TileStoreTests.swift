import Foundation
import Testing
@testable import Core

@Suite struct TileStoreContentsTests {
    @Test func tracksSizeAndIteratesEveryTileOnce() {
        let (store, tiles, _) = randomStore(500, spread: 5000)
        #expect(store.size == 500)
        #expect(Array(store).count == 500)
        #expect(ids(store) == ids(tiles))
    }

    @Test func removeDropsATileReportsWhetherItWasThereAndEmptiesBuckets() {
        let store = TileStore()
        let a = makeTile(0, 0)
        store.add(a)
        #expect(store.remove(a))
        #expect(!store.remove(a))
        #expect(store.size == 0)
        #expect(Array(store).isEmpty)
        #expect(store.near(0, 0, radius: 100).isEmpty)
        #expect(store.bucketCount == 0)
    }

    @Test func handlesManyTilesStackedInOneBucket() {
        let store = TileStore()
        let stack = (0..<50).map { _ in makeTile(10, 10) }
        for t in stack { store.add(t) }
        for t in stack.prefix(25) { store.remove(t) }
        #expect(store.size == 25)
        #expect(ids(store) == ids(stack.suffix(25)))
    }

    @Test func clearEmptiesEverything() {
        let (store, _, _) = randomStore(100, spread: 1000)
        store.clear()
        #expect(store.size == 0)
        #expect(Array(store).isEmpty)
    }

    @Test func newTilesStackAboveOlderOnesAndKeepAnExistingOrder() {
        let store = TileStore()
        let a = makeTile(0, 0), b = makeTile(100, 0)
        store.add(a)
        store.add(b)
        #expect(b.z > a.z && a.z > 0)
        store.raise(a)
        #expect(a.z > b.z)
        let kept = a.z
        store.remove(a)
        store.add(a)  // re-adding keeps its place
        #expect(a.z == kept)
    }
}

@Suite struct TileStoreNearTests {
    @Test func neverMissesATileWithinTheRadius() {
        var (store, tiles, rng) = randomStore(2000, spread: 4000)
        for _ in 0..<200 {
            let x = (rng.next() - 0.5) * 4000
            let y = (rng.next() - 0.5) * 4000
            let r = 20 + rng.next() * 300
            let got = ids(store.near(x, y, radius: r))
            for t in tiles where hypot(t.tx - x, t.ty - y) <= r {
                #expect(got.contains(ObjectIdentifier(t)))
            }
        }
    }

    @Test func returnsNothingOnEmptyAndStaysBoundedForAnAbsurdRadius() {
        let store = TileStore()
        #expect(store.near(0, 0, radius: 100).isEmpty)
        store.add(makeTile(0, 0))
        let elapsed = ContinuousClock().measure { _ = store.near(0, 0, radius: 1e9) }
        #expect(elapsed < .seconds(1))
    }

    @Test func findsTilesAtNegativeCoordinates() {
        let store = TileStore()
        let t = makeTile(-500, -900)
        store.add(t)
        #expect(contains(store.near(-490, -890, radius: 30), t))
    }
}

@Suite struct TileStoreSetTargetTests {
    @Test func reFilesATileSoItIsFoundAtItsNewPlaceAndNotTheOld() {
        let store = TileStore()
        let t = makeTile(0, 0)
        store.add(t)
        store.setTarget(t, 5000, 5000)
        #expect(!contains(store.near(0, 0, radius: cellSize), t))
        #expect(contains(store.near(5000, 5000, radius: cellSize), t))
        #expect(t.tx == 5000 && t.ty == 5000)
        #expect(store.size == 1)
    }

    @Test func keepsATileFindableWhenItMovesWithinItsCell() {
        let store = TileStore()
        let t = makeTile(1, 1)
        store.add(t)
        store.setTarget(t, 2, 2)
        #expect(contains(store.near(2, 2, radius: 10), t))
        #expect(store.remove(t))
    }

    @Test func staysConsistentThroughALongRandomWalk() {
        var (store, tiles, rng) = randomStore(300, spread: 2000)
        for _ in 0..<3000 {
            let t = tiles[Int(rng.next() * Double(tiles.count))]
            store.setTarget(t, (rng.next() - 0.5) * 6000, (rng.next() - 0.5) * 6000)
        }
        #expect(store.size == 300)
        for t in tiles { #expect(contains(store.near(t.tx, t.ty, radius: 1), t)) }
        for t in tiles { #expect(store.remove(t)) }
        #expect(store.size == 0)
    }
}

@Suite struct TileStoreRectTests {
    @Test func forEachTileVisitsExactlyTheTilesInsideForSmallAndHugeRects() {
        var (store, tiles, rng) = randomStore(1500, spread: 6000)
        var rects: [(Double, Double, Double, Double)] = [
            (-300, -200, 400, 250),
            (-1e7, -1e7, 1e7, 1e7),  // far more cells than buckets: the sparse path
            (2000, 2000, 2100, 2100),
        ]
        for _ in 0..<30 {
            let x = (rng.next() - 0.5) * 6000
            let y = (rng.next() - 0.5) * 6000
            rects.append((x, y, x + rng.next() * 2000, y + rng.next() * 2000))
        }
        for (a, b, c, d) in rects {
            var got: [Tile] = []
            store.forEachTile(inMinX: a, minY: b, maxX: c, maxY: d) { got.append($0) }
            #expect(got.count == ids(got).count)  // no tile visited twice
            let want = tiles.filter { $0.tx >= a && $0.tx <= c && $0.ty >= b && $0.ty <= d }
            #expect(ids(got) == ids(want))
        }
    }

    @Test func forEachBucketCountsEveryTileWhicheverWayItWalks() {
        let (store, _, _) = randomStore(400, spread: 3000)
        func total(_ lo: Double, _ hi: Double) -> Int {
            var n = 0
            store.forEachBucket(inMinX: lo, minY: lo, maxX: hi, maxY: hi) { _, tiles in
                n += tiles.count
                return false
            }
            return n
        }
        #expect(total(-1e6, 1e6) == 400)  // sparse path
        #expect(total(-1600, 1600) == 400)  // dense path
    }

    @Test func hasTileStopsAtTheFirstBucketAndIsFalseOverEmptyGround() {
        let store = TileStore()
        #expect(!store.hasTile(inMinX: -1e6, minY: -1e6, maxX: 1e6, maxY: 1e6))
        store.add(makeTile(500, 500))
        #expect(store.hasTile(inMinX: 400, minY: 400, maxX: 600, maxY: 600))
        #expect(!store.hasTile(inMinX: -5000, minY: -5000, maxX: -4000, maxY: -4000))
    }
}

@Suite struct TileStoreNearestTests {
    @Test func isNilOnAnEmptyStore() {
        #expect(TileStore().nearest(0, 0) == nil)
    }

    @Test func matchesABruteForceSearchNearAndFar() {
        var (store, tiles, rng) = randomStore(800, spread: 8000)
        for _ in 0..<200 {
            let x = (rng.next() - 0.5) * 20000
            let y = (rng.next() - 0.5) * 20000
            let want = tiles.map { hypot($0.tx - x, $0.ty - y) }.min()!
            let got = store.nearest(x, y)!
            #expect(abs(hypot(got.tx - x, got.ty - y) - want) < 1e-6)
        }
    }

    @Test func findsALoneTileArbitrarilyFarAway() {
        let store = TileStore()
        let t = makeTile(1e6, -1e6)
        store.add(t)
        #expect(store.nearest(0, 0) === t)
    }
}

@Suite struct TileStoreChunkTests {
    @Test func tilesInChunkPartitionsTheBoard() {
        let (store, tiles, _) = randomStore(3000, spread: chunkWorld * 6)
        var seen: [ObjectIdentifier: Int] = [:]
        for chunk in store.chunkCoords() {
            for t in store.tiles(in: chunk) { seen[ObjectIdentifier(t), default: 0] += 1 }
        }
        #expect(seen.count == tiles.count)
        #expect(seen.values.allSatisfy { $0 == 1 })
    }

    @Test func emptyStoreHasNoChunksAndAMissingChunkIsEmpty() {
        let store = TileStore()
        #expect(store.chunkCoords().isEmpty)
        #expect(store.tiles(in: ChunkCoord(x: 3, y: 3)).isEmpty)
    }

    @Test func flagsExactlyTheChunkAnAddRemoveOrRecolorTouches() {
        let store = TileStore()
        let a = makeTile(10, 10)
        let b = makeTile(chunkWorld * 3 + 10, 10)
        store.add(a)
        store.add(b)
        #expect(store.takeDirty().count == 2)
        #expect(store.takeDirty().isEmpty)
        store.setColor(a, 0x123456)
        #expect(store.takeDirty() == [ChunkCoord(containing: 10, 10)])
        store.remove(b)
        #expect(store.takeDirty().count == 1)
    }

    @Test func flagsBothChunksWhenATileCrossesABoundary() {
        let store = TileStore()
        let t = makeTile(10, 10)
        store.add(t)
        _ = store.takeDirty()
        store.setTarget(t, chunkWorld * 2 + 10, 10)
        #expect(store.takeDirty().count == 2)
        store.setTarget(t, chunkWorld * 2 + 20, 10)  // same chunk
        #expect(store.takeDirty().count == 1)
    }

    @Test func restoreDirtyHandsFlagsBack() {
        let store = TileStore()
        store.add(makeTile(0, 0))
        store.restoreDirty(store.takeDirty())
        #expect(store.takeDirty().count == 1)
    }

    @Test func handlesNegativeCoordinates() {
        let store = TileStore()
        let t = makeTile(-chunkWorld - 5, -chunkWorld * 4)
        store.add(t)
        let key = ChunkCoord(x: -2, y: -4)
        #expect(store.chunkCoords() == [key])
        #expect(store.tiles(in: key).first === t)
        #expect(store.takeDirty() == [key])
    }
}

@Suite struct TileStoreWatchTests {
    @Test func eachWatchSeesChangesIndependently() {
        let store = TileStore()
        let a = store.watch()
        let b = store.watch()
        store.add(makeTile(0, 0))
        #expect(a.take().count == 1)
        #expect(a.take().isEmpty)
        #expect(b.take().count == 1)  // a consuming its flags didn't hide them from b
    }

    @Test func aNewWatchStartsWithEveryExistingChunkFlagged() {
        let store = TileStore()
        store.add(makeTile(0, 0))
        store.add(makeTile(chunkWorld * 3, 0))
        #expect(store.watch().take().count == 2)
    }

    @Test func restoreHandsFlagsBack() {
        let store = TileStore()
        let w = store.watch()
        store.add(makeTile(0, 0))
        w.restore(w.take())
        #expect(w.count == 1)
    }

    @Test func countsTilesPerColorThroughAddRemoveRecolorAndClear() {
        let store = TileStore()
        let a = makeTile(0, 0, color: 0x111111)
        let b = makeTile(100, 0, color: 0x111111)
        let c = makeTile(200, 0, color: 0x222222)
        for t in [a, b, c] { store.add(t) }
        #expect(store.colorCounts == [0x111111: 2, 0x222222: 1])
        store.setColor(a, 0x222222)
        #expect(store.colorCounts == [0x111111: 1, 0x222222: 2])
        store.setColor(a, 0x222222)  // unchanged: no double count
        #expect(store.colorCounts[0x222222] == 2)
        store.remove(b)
        #expect(store.colorCounts[0x111111] == nil)
        store.clear()
        #expect(store.colorCounts.isEmpty)
    }

    @Test func aRecolorFlagsTheTilesChunkAnIdenticalRecolorDoesNot() {
        let store = TileStore()
        let t = makeTile(0, 0, color: 0x111111)
        store.add(t)
        let w = store.watch()
        _ = w.take()
        store.setColor(t, 0x111111)
        #expect(w.count == 0)
        store.setColor(t, 0x222222)
        #expect(w.count == 1)
    }
}
