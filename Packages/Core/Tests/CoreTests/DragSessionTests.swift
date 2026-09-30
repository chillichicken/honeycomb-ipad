import Foundation
import Testing
@testable import Core

@Suite struct DragSessionTests {
    let shape = TileShape.hexagon
    var east: NeighborSlot { shape.neighborSlots[0][5] }

    @Test func grabbedTilesLeaveTheStoreAndComeBackOnDrop() {
        let a = makeTile(0, 0), b = makeTile(500, 0)
        let board = makeBoard(tiles: [a, b])
        let drag = DragSession(board: board, tiles: [b], grabbedAt: SIMD2(500, 0))
        #expect(board.store.size == 1)
        drag.move(to: SIMD2(2000, 2000), snapDistance: snapRadius)
        #expect(b.x == 2000 && b.tx == 2000)
        #expect(drag.drop(snapDistance: snapRadius) == .free)
        #expect(board.store.size == 2)
        #expect(board.lastActive === b)
        #expect(contains(board.store.near(2000, 2000, radius: 10), b))
    }

    @Test func aTapWithoutMovingIsNotAnEditAndPutsTheTileBack() {
        let a = makeTile(10, 10)
        let board = makeBoard(tiles: [a])
        let drag = DragSession(board: board, tiles: [a], grabbedAt: SIMD2(10, 10))
        #expect(!drag.moved)
        drag.drop(snapDistance: snapRadius)
        #expect(a.tx == 10 && a.ty == 10 && board.store.size == 1)
    }

    @Test func snapsIntoAFreeSlotNextToATileWithinRange() {
        let anchor = makeTile(0, 0)
        let mover = makeTile(1000, 1000)
        let board = makeBoard(tiles: [anchor, mover])
        let drag = DragSession(board: board, tiles: [mover], grabbedAt: SIMD2(1000, 1000))
        drag.move(to: SIMD2(east.dx + 6, east.dy + 6), snapDistance: snapRadius)
        #expect(drag.snapCandidate != nil)
        #expect(drag.drop(snapDistance: snapRadius) == .snapped)
        #expect(abs(mover.tx - east.dx) < 1e-6 && abs(mover.ty - east.dy) < 1e-6)
        #expect(board.easing.contains(mover))  // glides into place
    }

    @Test func doesNotSnapOutOfRange() {
        let board = makeBoard(tiles: [makeTile(0, 0), makeTile(1000, 1000)])
        let mover = Array(board.store).first { $0.tx == 1000 }!
        let drag = DragSession(board: board, tiles: [mover], grabbedAt: SIMD2(1000, 1000))
        drag.move(to: SIMD2(east.dx + 60, east.dy), snapDistance: snapRadius)
        #expect(drag.snapCandidate == nil)
        #expect(drag.drop(snapDistance: snapRadius) == .free)
    }

    @Test func aGroupMovesRigidlyAndSnapsByItsBestTile() {
        let anchor = makeTile(0, 0)
        let g1 = makeTile(1000, 1000), g2 = makeTile(1000 + shape.neighborDist, 1000)
        let board = makeBoard(tiles: [anchor, g1, g2])
        let drag = DragSession(board: board, tiles: [g1, g2], grabbedAt: SIMD2(1000, 1000))
        drag.move(to: SIMD2(east.dx + 4, east.dy), snapDistance: snapRadius)
        #expect(drag.drop(snapDistance: snapRadius) == .snapped)
        #expect(abs(g1.tx - east.dx) < 1e-6)
        #expect(abs(g2.tx - g1.tx - shape.neighborDist) < 1e-6)  // still one piece
        #expect(board.store.size == 3)
    }

    @Test func aSingleTileDroppedOnAnotherSlidesToAFreeSlot() {
        let base = makeTile(0, 0), mover = makeTile(800, 0)
        let board = makeBoard(tiles: [base, mover])
        let drag = DragSession(board: board, tiles: [mover], grabbedAt: SIMD2(800, 0))
        drag.move(to: SIMD2(3, 3), snapDistance: 0)  // on top of base, snapping disabled
        #expect(drag.drop(snapDistance: 0) == .slid)
        #expect(hypot(mover.tx - base.tx, mover.ty - base.ty) > shape.occupiedEps)
    }

    @Test func liftedTilesKeepTheirStackingOrderAmongThemselvesAndEndOnTop() {
        let a = makeTile(0, 0), b = makeTile(0, 0), c = makeTile(0, 0)
        let board = makeBoard(tiles: [a, b, c])
        _ = DragSession(board: board, tiles: [b, a], grabbedAt: .zero)
        #expect(a.z < b.z && b.z > c.z)
    }

    @Test func aBigGroupIsSampledAcrossMovesButTheDropIsExact() {
        let anchor = makeTile(0, 0)
        let group = (0..<600).map { makeTile(5000 + Double($0) * 10, 5000) }
        let board = makeBoard(tiles: [anchor] + group)
        let drag = DragSession(board: board, tiles: group, grabbedAt: SIMD2(5000, 5000))
        // put the *last* group tile near the anchor's free slot
        drag.move(to: SIMD2(east.dx - 5990, east.dy - 5000 + 5000), snapDistance: snapRadius, sampleLimit: 8)
        #expect(drag.drop(snapDistance: snapRadius) == .snapped)
    }
}

@Suite struct GroupSnapTests {
    /// A build of `n` tiles, with a connected group of `size` tiles carried off its outer edge.
    func carve(_ shape: TileShape, build n: Int, group size: Int) -> (Board, [Tile]) {
        let board = Board(shape: shape)
        for _ in 0..<n { board.spawnTile(color: 1, cameraCenter: .zero) }
        board.settleEasing()
        let start = board.store.max { hypot($0.tx, $0.ty) < hypot($1.tx, $1.ty) }!
        let near = board.store.near(start.tx, start.ty, radius: shape.neighborDist * 3)
            .sorted { hypot($0.tx - start.tx, $0.ty - start.ty) < hypot($1.tx - start.tx, $1.ty - start.ty) }
        return (board, Array(near.prefix(size)))
    }

    @Test(arguments: [TileShape.hexagon, .triangle, .diamond])
    func aSnappedGroupNeverLandsOnTopOfExistingTiles(shape: TileShape) {
        var rng = SeededRandom(seed: 5)
        var snapped = 0
        for _ in 0..<300 {
            let (board, group) = carve(shape, build: 40, group: 2 + Int(rng.next() * 3))
            let start = group[0]
            let drag = DragSession(board: board, tiles: group, grabbedAt: SIMD2(start.x, start.y))
            let angle = rng.next() * 2 * .pi, r = shape.neighborDist * (1.5 + rng.next() * 1.5)
            drag.move(to: SIMD2(start.tx + cos(angle) * r, start.ty + sin(angle) * r), snapDistance: snapRadius)
            let landing = drag.drop(snapDistance: snapRadius)
            board.settleEasing()
            guard landing == .snapped else { continue }
            snapped += 1
            let members = Set(group)
            for g in group {
                let under = board.store.filter { !members.contains($0) && hypot($0.tx - g.tx, $0.ty - g.ty) < shape.occupiedEps * 0.9 }
                #expect(under.isEmpty, "a snapped group member sits on top of an existing tile")
            }
        }
        #expect(snapped > 20, "groups should still snap often (\(snapped) of 300)")
    }

    @Test func aLineOfThreeFindsTheSlotWhereAllOfItFitsNotJustTheNearestForOneTile() {
        // a wall of hexagons along y = 0; a horizontal row of three is dropped so that its
        // first tile is nearest to a slot that would push the third one into the wall
        let shape = TileShape.hexagon
        let d = shape.neighborDist
        let wall = (0..<8).map { makeTile(Double($0) * d, 0) }
        let board = makeBoard(tiles: wall)
        let row = (0..<3).map { makeTile(Double($0) * d, 1000) }
        for t in row { board.store.add(t) }
        let drag = DragSession(board: board, tiles: row, grabbedAt: SIMD2(0, 1000))
        drag.move(to: SIMD2(2 * d + 5, d * 0.4), snapDistance: snapRadius * 2)  // straddling the wall
        _ = drag.drop(snapDistance: snapRadius * 2)
        board.settleEasing()
        let onWall = row.filter { g in wall.contains { hypot($0.tx - g.tx, $0.ty - g.ty) < shape.occupiedEps * 0.9 } }
        #expect(onWall.isEmpty, "no member of the row may end up on the wall")
    }

    @Test func aGroupThatFitsNowhereStaysWhereItWasDropped() {
        let shape = TileShape.hexagon
        let d = shape.neighborDist
        // a solid 5x5 block: there is no free slot the whole 3-row could take next to it in the middle
        var tiles: [Tile] = []
        for x in 0..<5 { for y in 0..<5 { tiles.append(makeTile(Double(x) * d, Double(y) * d)) } }
        let board = makeBoard(tiles: tiles)
        let row = (0..<3).map { makeTile(Double($0) * d, 5000) }
        for t in row { board.store.add(t) }
        let drag = DragSession(board: board, tiles: row, grabbedAt: SIMD2(0, 5000))
        drag.move(to: SIMD2(2 * d, 2 * d), snapDistance: 4)  // dropped into the middle of the block, snap range tiny
        #expect(drag.drop(snapDistance: 4) == .free)
    }
}
