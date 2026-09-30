import Foundation
import Testing
@testable import Core

@Suite struct ShapeTests {
    @Test(arguments: ShapeID.allCases)
    func neighborSlotsSitAtNeighborDist(id: ShapeID) {
        let shape = TileShape.of(id)
        for slots in shape.neighborSlots {
            for s in slots {
                #expect(abs(hypot(s.dx, s.dy) - shape.neighborDist) < 1e-6)
            }
        }
    }

    @Test(arguments: ShapeID.allCases)
    func neighborRelationIsSymmetric(id: ShapeID) {
        let shape = TileShape.of(id)
        for o in 0..<shape.orientations {
            for s in shape.neighborSlots[o] {
                let back = shape.neighborSlots[s.orientation].first {
                    $0.orientation == o && abs($0.dx + s.dx) < 1e-6 && abs($0.dy + s.dy) < 1e-6
                }
                #expect(back != nil)
            }
        }
    }

    @Test(arguments: ShapeID.allCases)
    func occupiedEpsIsHalfNeighborDist(id: ShapeID) {
        let shape = TileShape.of(id)
        #expect(abs(shape.occupiedEps - shape.neighborDist / 2) < 1e-9)
    }

    @Test(arguments: ShapeID.allCases)
    func containsAcceptsInsideAndRejectsOutside(id: ShapeID) {
        let shape = TileShape.of(id)
        let c = SIMD2(100.0, 100.0)
        for o in 0..<shape.orientations {
            #expect(shape.contains(orientation: o, center: c, radius: tileSize, point: c))
            for u in shape.cornerUnitVectors[o] {
                let inside = c + u * (tileSize * 0.95)
                let outside = c + u * (tileSize * 1.3)
                #expect(shape.contains(orientation: o, center: c, radius: tileSize, point: inside))
                #expect(!shape.contains(orientation: o, center: c, radius: tileSize, point: outside))
            }
            let far = c + SIMD2(tileSize * 5, 0)
            #expect(!shape.contains(orientation: o, center: c, radius: tileSize, point: far))
        }
    }

    @Test func trianglesAlternateOrientationAcrossEveryEdge() {
        let tri = TileShape.triangle
        #expect(tri.orientations == 2)
        #expect(tri.neighborSlots[0].allSatisfy { $0.orientation == 1 })
        #expect(tri.neighborSlots[1].allSatisfy { $0.orientation == 0 })
    }

    @Test func idsRoundTripThroughRawValue() {
        #expect(ShapeID(rawValue: "hexagon") == .hexagon)
        #expect(ShapeID(rawValue: "toString") == nil)
    }
}

@Suite struct ShapeIntersectionTests {
    let c = SIMD2(100.0, 100.0)
    let r = tileSize

    func hits(_ shape: TileShape, _ minX: Double, _ minY: Double, _ maxX: Double, _ maxY: Double, orientation: Int = 0) -> Bool {
        shape.intersects(orientation: orientation, center: c, radius: r, minX: minX, minY: minY, maxX: maxX, maxY: maxY)
    }

    @Test(arguments: ShapeID.allCases)
    func aRectInsideOrAroundOrOverlappingTheTileHits(id: ShapeID) {
        let s = TileShape.of(id)
        #expect(hits(s, 95, 95, 105, 105))  // inside
        #expect(hits(s, 0, 0, 300, 300))  // around
        #expect(hits(s, 100, 100, 300, 300))  // overlapping the center
    }

    @Test(arguments: ShapeID.allCases)
    func aRectFarAwayMisses(id: ShapeID) {
        #expect(!hits(TileShape.of(id), 400, 400, 500, 500))
        #expect(!hits(TileShape.of(id), -500, 100, -300, 120))
    }

    @Test func aRectInTheBoundingBoxCornerButOutsideTheHexagonMisses() {
        // flat-top hexagon: near (cx + 0.9R, cy + 0.8R) the polygon has already fallen away
        #expect(!hits(.hexagon, c.x + 0.9 * r, c.y + 0.8 * r, c.x + 2 * r, c.y + 2 * r))
        #expect(hits(.hexagon, c.x + 0.9 * r, c.y - 0.1 * r, c.x + 2 * r, c.y + 0.1 * r))
    }

    @Test func triangleCornersAreExact() {
        // up-pointing triangle: its top corner is at (cx, cy - R); the bbox corners are empty
        #expect(hits(.triangle, c.x - 2, c.y - r - 5, c.x + 2, c.y - r + 5))
        #expect(!hits(.triangle, c.x + 0.7 * r, c.y - r, c.x + 2 * r, c.y - 0.7 * r))
    }

    @Test func touchingTheEdgeCounts() {
        #expect(hits(.diamond, c.x + r - 1, c.y - 1, c.x + r + 50, c.y + 1))
    }
}

@Suite struct TouchingQueryTests {
    @Test func selectsShapesTheFrameTouchesNotOnlyThoseWhoseCenterIsInside() {
        let board = makeBoard(tiles: [makeTile(0, 0), makeTile(200, 0), makeTile(1000, 0)])
        let lattice = board.lattice
        var touched: [Tile] = []
        // a frame whose right edge just clips the tile at x=200 (its center is outside the frame)
        lattice.forEachTile(touchingMinX: -10, minY: -10, maxX: 200 - tileSize + 5, maxY: 10) { touched.append($0) }
        #expect(touched.count == 2)
        #expect(ids(touched) == ids(board.store.filter { $0.tx <= 200 }))
        var centersOnly: [Tile] = []
        board.store.forEachTile(inMinX: -10, minY: -10, maxX: 200 - tileSize + 5, maxY: 10) { centersOnly.append($0) }
        #expect(centersOnly.count == 1)
    }

    @Test func aTinyFrameOnATileSelectsIt() {
        let t = makeTile(500, 500)
        let board = makeBoard(tiles: [t, makeTile(900, 500)])
        var touched: [Tile] = []
        board.lattice.forEachTile(touchingMinX: 510, minY: 510, maxX: 512, maxY: 512) { touched.append($0) }
        #expect(touched.count == 1 && touched[0] === t)
    }
}
