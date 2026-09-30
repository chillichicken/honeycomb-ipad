import Foundation
import Testing
@testable import Core

@Suite struct ShapeTests {
    @Test(arguments: ShapeID.allCases)
    func neighborSlotsSitAtNeighborDist(id: ShapeID) {
        let shape = Shape.of(id)
        for slots in shape.neighborSlots {
            for s in slots {
                #expect(abs(hypot(s.dx, s.dy) - shape.neighborDist) < 1e-6)
            }
        }
    }

    @Test(arguments: ShapeID.allCases)
    func neighborRelationIsSymmetric(id: ShapeID) {
        let shape = Shape.of(id)
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
        let shape = Shape.of(id)
        #expect(abs(shape.occupiedEps - shape.neighborDist / 2) < 1e-9)
    }

    @Test(arguments: ShapeID.allCases)
    func containsAcceptsInsideAndRejectsOutside(id: ShapeID) {
        let shape = Shape.of(id)
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
        let tri = Shape.triangle
        #expect(tri.orientations == 2)
        #expect(tri.neighborSlots[0].allSatisfy { $0.orientation == 1 })
        #expect(tri.neighborSlots[1].allSatisfy { $0.orientation == 0 })
    }

    @Test func idsRoundTripThroughRawValue() {
        #expect(ShapeID(rawValue: "hexagon") == .hexagon)
        #expect(ShapeID(rawValue: "toString") == nil)
    }
}
