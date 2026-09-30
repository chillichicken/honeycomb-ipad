import Foundation
import Testing
@testable import Core

private let origin = SIMD2(0.0, 0.0)
private let allShapes: [TileShape] = ShapeID.allCases.map(TileShape.of)

@Suite struct SpawnTests {
    @Test func firstTileGoesAtTheCameraCenter() {
        let board = makeBoard()
        let t = board.spawnTile(color: 0x123456, cameraCenter: SIMD2(300, -120))
        #expect(board.store.size == 1)
        #expect(t.tx == 300 && t.ty == -120 && t.color == 0x123456 && t.orientation == 0)
        #expect(board.lastActive === t)
        #expect(board.spawnBackIndex == nil)
    }

    @Test(arguments: allShapes)
    func sixtyPressesBuildOneConnectedIslandWithNoOverlaps(shape: TileShape) {
        let board = makeBoard(shape)
        for _ in 0..<60 { board.spawnTile(color: 0xABCDEF, cameraCenter: origin) }
        let tiles = Array(board.store)
        #expect(tiles.count == 60)
        #expect(computeClusters(board.store, shape: shape) == ClusterCounts(islands: 1, largest: 60))
        for i in 0..<tiles.count {
            for j in (i + 1)..<tiles.count {
                #expect(hypot(tiles[i].tx - tiles[j].tx, tiles[i].ty - tiles[j].ty) > shape.occupiedEps)
            }
        }
    }

    @Test func newTilesStartEasedFromTheAnchorAndAreRegisteredForEasing() {
        let board = makeBoard()
        let first = board.spawnTile(color: 0x111111, cameraCenter: origin)
        let second = board.spawnTile(color: 0x222222, cameraCenter: origin)
        #expect(!board.easing.contains(first))
        #expect(board.easing.contains(second))
        #expect(second.x == first.tx && second.y == first.ty)
    }

    @Test func keepsBuildingAfterTheLastActiveTileIsRemoved() {
        let board = makeBoard()
        for _ in 0..<10 { board.spawnTile(color: 0x111111, cameraCenter: origin) }
        board.remove(board.lastActive!)
        #expect(board.lastActive != nil)
        board.spawnTile(color: 0x222222, cameraCenter: origin)
        #expect(computeClusters(board.store, shape: .hexagon).islands == 1)
    }

    @Test func hopsToAnotherFreeSlotWhenTheAnchorIsFullySurrounded() {
        let shape = TileShape.hexagon
        let board = makeBoard()
        let center = makeTile(0, 0)
        board.store.add(center)
        for s in shape.neighborSlots[0] { board.store.add(makeTile(s.dx, s.dy)) }
        board.lastActive = center
        let t = board.spawnTile(color: 0x333333, cameraCenter: origin)
        #expect(board.store.size == 8)
        #expect(hypot(t.tx, t.ty) > shape.neighborDist * 1.5)
    }
}

@Suite struct SpawnAtTests {
    @Test func placesAtThePointWhenTheBoardIsEmpty() {
        let board = makeBoard()
        let t = board.spawnTile(color: 0x111111, at: SIMD2(50, 60))
        #expect(t.tx == 50 && t.ty == 60)
    }

    @Test func snapsToAFreeNeighborSlotOfTheNearestBuild() {
        let shape = TileShape.hexagon
        let board = makeBoard(tiles: [makeTile(0, 0)])
        let t = board.spawnTile(color: 0x111111, at: SIMD2(500, 3))
        let nearest = shape.neighborSlots[0].min {
            hypot($0.dx - 500, $0.dy - 3) < hypot($1.dx - 500, $1.dy - 3)
        }!
        #expect(abs(t.tx - nearest.dx) < 1e-6 && abs(t.ty - nearest.dy) < 1e-6)
        #expect(board.spawnBackIndex == nil)
    }

    @Test func givesTrianglesTheOrientationTheLatticeRequires() {
        let tri = TileShape.triangle
        let board = makeBoard(tri, tiles: [makeTile(0, 0, orientation: 0)])
        let t = board.spawnTile(color: 0x111111, at: SIMD2(10, 200))
        let slot = tri.neighborSlots[0].first { abs($0.dx - t.tx) < 1e-6 && abs($0.dy - t.ty) < 1e-6 }
        #expect(slot != nil)
        #expect(t.orientation == slot?.orientation)
    }
}

@Suite struct FreeSlotTests {
    let shape = TileShape.hexagon
    var east: NeighborSlot { shape.neighborSlots[0][5] }  // 330°

    func lattice(_ tiles: [Tile]) -> Lattice {
        Lattice(store: makeBoard(tiles: tiles).store, shape: shape)
    }

    @Test func returnsTheNearestFreeSlotWithinRange() throws {
        let s = try #require(lattice([makeTile(0, 0)]).freeSlot(nearX: east.dx + 5, east.dy + 5, maxDist: 60))
        #expect(abs(s.slot.x - east.dx) < 1e-6 && abs(s.slot.y - east.dy) < 1e-6)
        #expect(abs(s.distance - hypot(5, 5)) < 1e-6)
    }

    @Test func returnsNilWhenNothingIsWithinMaxDist() {
        let l = lattice([makeTile(0, 0)])
        #expect(l.freeSlot(nearX: 2000, 2000, maxDist: 60) == nil)
        #expect(l.freeSlot(nearX: east.dx + 40, east.dy, maxDist: 10) == nil)
    }

    @Test func skipsSlotsThatAreAlreadyOccupied() {
        let l = lattice([makeTile(0, 0), makeTile(east.dx, east.dy)])
        #expect(l.freeSlot(nearX: east.dx, east.dy, maxDist: 20) == nil)
    }

    @Test func ignoredTilesAreNeitherOwnersNorBlockers() {
        let owner = makeTile(0, 0)
        let blocker = makeTile(east.dx, east.dy)
        let l = lattice([owner, blocker])
        #expect(l.freeSlot(nearX: east.dx, east.dy, ignoring: [blocker], maxDist: 20) != nil)
        #expect(l.freeSlot(nearX: east.dx, east.dy, ignoring: [owner, blocker], maxDist: 20) == nil)
    }

    @Test func filtersByRequiredOrientationForTriangles() {
        let tri = TileShape.triangle
        let l = Lattice(store: makeBoard(tri, tiles: [makeTile(0, 0, orientation: 0)]).store, shape: tri)
        let slot = tri.neighborSlots[0][0]
        #expect(l.freeSlot(nearX: slot.dx, slot.dy, maxDist: 20, orientation: 1) != nil)
        #expect(l.freeSlot(nearX: slot.dx, slot.dy, maxDist: 20, orientation: 0) == nil)
    }

    @Test func worksAtNegativeCoordinates() {
        let l = lattice([makeTile(-1000, -2000)])
        #expect(l.freeSlot(nearX: -1000 + east.dx, -2000 + east.dy, maxDist: 20) != nil)
    }

    @Test func tileAtReturnsTheTopmostTileUnderThePoint() {
        let a = makeTile(0, 0), b = makeTile(0, 0)
        let board = makeBoard(tiles: [a, b])
        let l = Lattice(store: board.store, shape: .hexagon)
        #expect(l.tileAt(1, 1) === b)
        board.store.raise(a)
        #expect(l.tileAt(1, 1) === a)
        #expect(l.tileAt(500, 500) == nil)
    }
}

@Suite struct RemovalTests {
    @Test func removeDropsTheTileFromBoardSelectionAndEasing() {
        let a = makeTile(0, 0), b = makeTile(100, 0)
        let board = makeBoard(tiles: [a, b])
        board.selected.insert(a)
        board.startEasing(a)
        board.remove(a)
        #expect(Array(board.store).count == 1 && Array(board.store)[0] === b)
        #expect(!board.selected.contains(a))
        #expect(!board.easing.contains(a))
    }

    @Test func removingAnUnknownTileIsANoOp() {
        let board = makeBoard(tiles: [makeTile(0, 0)])
        board.remove(makeTile(5, 5))
        #expect(board.store.size == 1)
    }

    @Test func removesAWholeSetInOneGo() {
        let tiles = (0..<20).map { makeTile(Double($0) * 100, 0) }
        let board = makeBoard(tiles: tiles)
        let doomed = Set(tiles.enumerated().filter { $0.offset % 2 == 0 }.map(\.element))
        board.selected = doomed
        board.remove(doomed)
        #expect(board.store.size == 10)
        #expect(Array(board.store).allSatisfy { !doomed.contains($0) })
        #expect(board.selected.isEmpty)
    }

    @Test func lastActiveNeverDangles() {
        let tiles = [makeTile(0, 0), makeTile(100, 0), makeTile(200, 0)]
        let board = makeBoard(tiles: tiles)
        board.lastActive = tiles[2]
        board.remove([tiles[2]])
        #expect(board.lastActive != nil && board.store.contains { $0 === board.lastActive })
        board.remove(Array(board.store))
        #expect(board.lastActive == nil)
    }

    @Test func replaceSwapsTheWholeBoard() {
        let board = makeBoard(tiles: [makeTile(0, 0), makeTile(100, 0)])
        board.selected = [Array(board.store)[0]]
        let fresh = [makeTile(5, 5), makeTile(9, 9)]
        board.replace(shape: .diamond, tiles: fresh)
        #expect(board.shape.id == .diamond)
        #expect(board.store.size == 2)
        #expect(board.selected.isEmpty && board.easing.isEmpty)
        #expect(board.lastActive === fresh[1])
        #expect(fresh[0].z < fresh[1].z)  // stacking follows the given order
    }
}

@Suite struct ClusterCountTests {
    @Test func isZeroForAnEmptyBoard() {
        #expect(computeClusters(TileStore(), shape: .hexagon) == ClusterCounts(islands: 0, largest: 0))
    }

    @Test func countsSeparateIslandsAndTheLargest() {
        let d = TileShape.hexagon.neighborDist
        func line(_ n: Int, _ y: Double) -> [Tile] { (0..<n).map { makeTile(Double($0) * d, y) } }
        let board = makeBoard(tiles: line(5, 0) + line(2, 1000) + line(1, -1000))
        #expect(computeClusters(board.store, shape: .hexagon) == ClusterCounts(islands: 3, largest: 5))
    }
}

@Suite struct EasingTests {
    @Test func movesEasingTilesTowardTargetAndReleasesThemOnceConverged() {
        let board = makeBoard()
        let t = Tile(x: 0, y: 0, color: 0)
        board.store.add(t)
        board.store.setTarget(t, 100, 0)
        board.startEasing(t)
        board.easeTowardTargets()
        #expect(t.x > 0 && t.x < 100)
        for _ in 0..<100 { board.easeTowardTargets() }
        #expect(t.x == 100 && t.y == 0)
        #expect(board.easing.isEmpty)
    }

    @Test func leavesHeldTilesAlone() {
        let board = makeBoard()
        let t = Tile(x: 0, y: 0, color: 0)
        board.store.add(t)
        board.store.setTarget(t, 100, 0)
        board.startEasing(t)
        board.easeTowardTargets(skipping: [t])
        #expect(t.x == 0)
    }
}

@Suite struct TileCapTests {
    @Test func canAddRespectsMaxTiles() {
        let board = Board(maxTiles: 100)
        board.store.add(makeTile(0, 0))
        #expect(board.canAdd(1))
        #expect(board.canAdd(99))
        #expect(!board.canAdd(100))
        #expect(Board.defaultMaxTiles == 2_000_000)
    }
}

@Suite struct BigBoardTests {
    @Test func slotSearchEdgeSpawningAndRemovalDontScaleWithTileCount() {
        let board = makeBoard()
        let d = TileShape.hexagon.neighborDist
        let cols = 700
        for i in 0..<300_000 {
            let col = i % cols
            board.store.add(makeTile(
                Double(col) * d * 0.866, Double(i / cols) * d + (col % 2 == 1 ? d / 2 : 0)))
        }
        let elapsed = ContinuousClock().measure {
            for i in 0..<300 {  // deep inside the block
                _ = board.lattice.freeSlot(nearX: 20000 + Double(i), 10000, maxDist: 80)
            }
            for i in 0..<30 {  // just off its east edge
                board.remove(board.spawnTile(color: 0x123456, at: SIMD2(60000, 10000 + Double(i) * 50)))
            }
            for i in 0..<5 {  // very far away: nearest() falls back to one full pass
                board.remove(board.spawnTile(color: 0x123456, at: SIMD2(1e6, 1e6 + Double(i) * 50)))
            }
        }
        #expect(elapsed < .seconds(10))  // debug build, run in parallel; an O(n) regression takes minutes
    }
}

@Suite struct BuriedSpawnTests {
    @Test(arguments: [(ShapeID.hexagon, 40.0), (.diamond, 40.0), (.triangle, 60.0)])
    func findsAFreeEdgeSlotQuicklyAndTheResultIsAValidLatticeSlot(id: ShapeID, radius: Double) {
        let shape = TileShape.of(id)
        let board = lattice(block: shape, radiusTiles: radius)
        let before = board.store.size
        #expect(before > 3000)  // deeper than the BFS cap, so the walk path runs
        board.lastActive = board.store.nearest(0, 0)
        var t: Tile!
        let elapsed = ContinuousClock().measure {
            t = board.spawnTile(color: 0x123456, cameraCenter: origin)
        }
        #expect(elapsed < .milliseconds(500))
        #expect(board.store.size == before + 1)
        // it landed in a real slot of some neighbor, with that slot's orientation
        let neighbor = board.store.near(t.tx, t.ty, radius: shape.neighborDist * 1.5).first { o in
            o !== t && shape.neighborSlots[o.orientation].contains {
                abs(o.tx + $0.dx - t.tx) < 1e-6 && abs(o.ty + $0.dy - t.ty) < 1e-6
                    && $0.orientation == t.orientation
            }
        }
        #expect(neighbor != nil)
        // and it isn't stacked on another tile
        let stacked = board.store.near(t.tx, t.ty, radius: 1).filter {
            hypot($0.tx - t.tx, $0.ty - t.ty) < shape.occupiedEps
        }
        #expect(stacked.count == 1 && stacked[0] === t)
    }

    @Test func aNearbyHoleIsStillFoundRingByRingNotSkippedForTheFarEdge() {
        let shape = TileShape.hexagon
        let board = lattice(block: shape, radiusTiles: 30)
        let target = board.store.nearest(shape.neighborDist * 3, 0)!
        let center = board.store.nearest(0, 0)!
        board.store.remove(target)  // a hole three tiles from the anchor
        board.lastActive = center
        let t = board.spawnTile(color: 0x123456, cameraCenter: origin)
        #expect(hypot(t.tx - target.tx, t.ty - target.ty) < 1e-6)
    }
}
