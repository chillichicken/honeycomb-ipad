import Foundation
import Testing
@testable import Core

@Suite struct DragFuzzTests {
    /// Tiles (other than `tile`) whose settled position is on top of `tile`'s.
    func stackedUnder(_ tile: Tile, in board: Board) -> [Tile] {
        board.store.filter { $0 !== tile && hypot($0.tx - tile.tx, $0.ty - tile.ty) < board.shape.occupiedEps * 0.9 }
    }

    /// A compact build of `n` tiles grown with "+".
    func makeBoard(_ shape: TileShape, tiles n: Int) -> Board {
        let board = Board(shape: shape)
        for _ in 0..<n { board.spawnTile(color: 1, cameraCenter: .zero) }
        board.settleEasing()
        return board
    }

    @Test(arguments: [TileShape.hexagon, .triangle, .diamond])
    func aSingleTileDroppedNearThePiecesNeverLandsOnTopOfOneWhenARoomyEdgeIsClose(shape: TileShape) {
        var rng = SeededRandom(seed: 42)
        let board = makeBoard(shape, tiles: 60)
        let reach = shape.neighborDist * 4
        var failures: [String] = []

        for round in 0..<400 {
            let all = Array(board.store)
            let pick = all[Int(rng.next() * Double(all.count))]
            let drag = DragSession(board: board, tiles: [pick], grabbedAt: SIMD2(pick.x, pick.y))
            let target = SIMD2((rng.next() - 0.5) * reach * 2, (rng.next() - 0.5) * reach * 2)
            drag.move(to: target, snapDistance: snapRadius)
            let nearestFree = board.lattice.freeSlot(nearX: target.x, target.y, maxDist: 1e9, orientation: pick.orientation)?.distance ?? .infinity
            let landing = drag.drop(snapDistance: snapRadius)
            board.settleEasing()

            let under = stackedUnder(pick, in: board)
            if !under.isEmpty && nearestFree <= shape.neighborDist * 2 {
                failures.append("round \(round): landing \(landing), free slot \(Int(nearestFree))px from the drop, but the tile sits on \(under.count) other(s) — pick o\(pick.orientation) at (\(Int(pick.tx)),\(Int(pick.ty))), other o\(under[0].orientation) at (\(Int(under[0].tx)),\(Int(under[0].ty)))")
            }
        }
        #expect(failures.isEmpty, "\(failures.count) bad drops, first: \(failures.first ?? "")")
    }

    @Test(arguments: [TileShape.hexagon, .triangle, .diamond])
    func aSingleTileDroppedWithinRangeOfAFreeSlotLandsInIt(shape: TileShape) {
        var rng = SeededRandom(seed: 7)
        let board = makeBoard(shape, tiles: 40)
        for round in 0..<200 {
            let all = Array(board.store)
            let pick = all[Int(rng.next() * Double(all.count))]
            let drag = DragSession(board: board, tiles: [pick], grabbedAt: SIMD2(pick.x, pick.y))
            let owners = board.store.filter { $0 !== pick }
            let owner = owners[Int(rng.next() * Double(owners.count))]
            let slots = shape.neighborSlots[owner.orientation].filter { $0.orientation == pick.orientation }
            guard let slot = slots.first(where: { board.lattice.tile(inSlotAt: owner.tx + $0.dx, owner.ty + $0.dy) == nil }) else {
                drag.drop(snapDistance: snapRadius)
                continue
            }
            let sx = owner.tx + slot.dx, sy = owner.ty + slot.dy
            let angle = rng.next() * 2 * .pi, r = rng.next() * snapRadius * 0.6
            drag.move(to: SIMD2(sx + cos(angle) * r, sy + sin(angle) * r), snapDistance: snapRadius)
            let landing = drag.drop(snapDistance: snapRadius)
            board.settleEasing()
            #expect(landing == .snapped, "round \(round): dropped \(Int(r))px from a free slot but it did not snap")
            #expect(stackedUnder(pick, in: board).isEmpty, "round \(round): stacked after snapping")
            if landing != .snapped { return }
        }
    }
}
