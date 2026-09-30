import Foundation

/// A puzzle uses exactly one shape for all its tiles.
public enum ShapeID: String, CaseIterable, Sendable {
    case hexagon, triangle, diamond
}

/// A neighbor slot: a world-space offset from a tile's center, plus the
/// orientation a tile must have to fill it.
public struct NeighborSlot: Sendable {
    public let dx: Double
    public let dy: Double
    public let orientation: Int
}

/// Static geometry of one shape. Hexagons and diamonds have one orientation;
/// triangles alternate up/down, and every neighbor of one is the other.
/// Everything derived from angles is computed once here, so hot paths (snap
/// search, rendering) read constants instead of redoing trig.
public struct Shape: Sendable {
    public let id: ShapeID
    public let label: String
    public var orientations: Int { cornerUnitVectors.count }
    /// (cos, sin) per corner, per orientation.
    public let cornerUnitVectors: [[SIMD2<Double>]]
    /// Neighbor slots, per orientation.
    public let neighborSlots: [[NeighborSlot]]
    /// Center-to-center spacing of snapped neighbors.
    public let neighborDist: Double
    /// A slot counts as taken within this distance of a tile center.
    public var occupiedEps: Double { neighborDist * 0.5 }

    /// Angles are in degrees.
    private init(
        id: ShapeID,
        label: String,
        corners: [[Double]],
        slots: [(angles: [Double], orientation: Int)],
        neighborDist: Double
    ) {
        self.id = id
        self.label = label
        self.neighborDist = neighborDist
        cornerUnitVectors = corners.map { $0.map { Self.unit($0) } }
        neighborSlots = slots.map { group in
            group.angles.map { angle in
                let u = Self.unit(angle)
                return NeighborSlot(dx: u.x * neighborDist, dy: u.y * neighborDist, orientation: group.orientation)
            }
        }
    }

    private static func unit(_ degrees: Double) -> SIMD2<Double> {
        let r = degrees * .pi / 180
        return SIMD2(cos(r), sin(r))
    }

    public static let hexagon = Shape(
        id: .hexagon, label: "Hexagon",
        corners: [[0, 60, 120, 180, 240, 300]],
        slots: [([30, 90, 150, 210, 270, 330], 0)],
        neighborDist: 3.0.squareRoot() * tileSize
    )

    public static let triangle = Shape(
        id: .triangle, label: "Triangle",
        corners: [
            [270, 30, 150],  // 0 = pointing up
            [90, 210, 330],  // 1 = pointing down
        ],
        slots: [([90, 210, 330], 1), ([270, 30, 150], 0)],
        neighborDist: tileSize
    )

    public static let diamond = Shape(
        id: .diamond, label: "Diamond",
        corners: [[0, 90, 180, 270]],
        slots: [([45, 135, 225, 315], 0)],
        neighborDist: tileSize * 2.0.squareRoot()
    )

    public static func of(_ id: ShapeID) -> Shape {
        switch id {
        case .hexagon: .hexagon
        case .triangle: .triangle
        case .diamond: .diamond
        }
    }

    /// Exact point-in-polygon test against the outline that gets drawn. Every
    /// shape is convex, so "inside" means the point is on the same side of
    /// every edge.
    public func contains(
        orientation: Int, center: SIMD2<Double>, radius: Double, point: SIMD2<Double>
    ) -> Bool {
        let units = cornerUnitVectors[orientation]
        var start = center + units[units.count - 1] * radius
        var sign = 0.0
        for unit in units {
            let end = center + unit * radius
            let cross = (end.x - start.x) * (point.y - start.y) - (end.y - start.y) * (point.x - start.x)
            if cross != 0 {
                let s: Double = cross > 0 ? 1 : -1
                if sign == 0 { sign = s } else if s != sign { return false }
            }
            start = end
        }
        return true
    }
}
