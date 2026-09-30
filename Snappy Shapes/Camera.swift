import CoreGraphics

/// Which part of the world the screen shows.
struct Camera {
    static let zoomRange = 0.02...4.0

    var center = SIMD2<Double>.zero
    var zoom = 1.0
    var size = CGSize.zero

    func toScreen(_ w: SIMD2<Double>) -> CGPoint {
        CGPoint(x: (w.x - center.x) * zoom + size.width / 2, y: (w.y - center.y) * zoom + size.height / 2)
    }

    func toWorld(_ p: CGPoint) -> SIMD2<Double> {
        SIMD2((p.x - size.width / 2) / zoom + center.x, (p.y - size.height / 2) / zoom + center.y)
    }

    /// World rectangle currently on screen, grown by `margin` world units.
    func visibleRect(margin: Double = 0) -> (minX: Double, minY: Double, maxX: Double, maxY: Double) {
        let a = toWorld(.zero)
        let b = toWorld(CGPoint(x: size.width, y: size.height))
        return (a.x - margin, a.y - margin, b.x + margin, b.y + margin)
    }

    /// Pans by a screen-space movement.
    mutating func pan(byScreen d: CGPoint) {
        center -= SIMD2(Double(d.x), Double(d.y)) / zoom
    }

    /// Zooms by `factor` keeping the world point under `p` where it is.
    mutating func zoom(by factor: Double, around p: CGPoint) {
        let anchor = toWorld(p)
        zoom = min(max(zoom * factor, Self.zoomRange.lowerBound), Self.zoomRange.upperBound)
        center = anchor - SIMD2((p.x - size.width / 2) / zoom, (p.y - size.height / 2) / zoom)
    }
}
