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
