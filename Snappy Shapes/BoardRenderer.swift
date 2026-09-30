import UIKit
import Core

/// Draws the board with Core Graphics. Only what's on screen is visited: the
/// store's buckets that overlap the viewport, plus the few tiles mid-animation
/// and the ones being carried.
final class BoardRenderer {
    private var strokeColors: [TileColor: CGColor] = [:]
    private var fillColors: [TileColor: CGColor] = [:]
    private var lastMs = 0.0

    private let background = UIColor(red: 0.95, green: 0.93, blue: 0.89, alpha: 1)

    @MainActor
    func draw(_ editor: Editor, in ctx: CGContext, bounds: CGRect) {
        let start = CACurrentMediaTime()
        let camera = editor.camera
        let board = editor.board
        let shape = board.shape

        ctx.setFillColor(background.cgColor)
        ctx.fill(bounds)

        // gather what's visible: bucket walk (minus easing tiles), easing tiles, carried tiles
        let r = camera.visibleRect(margin: tileSize * 1.5)
        var visible: [Tile] = []
        board.store.forEachBucket(inMinX: r.minX, minY: r.minY, maxX: r.maxX, maxY: r.maxY) { _, tiles in
            for t in tiles where !board.easing.contains(t) { visible.append(t) }
            return false
        }
        visible.append(contentsOf: board.easing)
        if let drag = editor.drag { visible.append(contentsOf: drag.items.map(\.tile)) }
        visible.sort { $0.z < $1.z }

        let radius = tileSize * camera.zoom
        let tiny = radius < 3
        ctx.setLineJoin(.round)
        for t in visible {
            let c = camera.toScreen(SIMD2(t.x, t.y))
            if c.x < -radius || c.y < -radius || c.x > bounds.width + radius || c.y > bounds.height + radius { continue }
            let selected = board.selected.contains(t)
            ctx.setFillColor(fill(t.color))
            if tiny {
                let s = radius * 1.6
                ctx.fill(CGRect(x: c.x - s / 2, y: c.y - s / 2, width: s, height: s))
                continue
            }
            addPath(ctx, shape: shape, orientation: t.orientation, center: c, radius: radius)
            ctx.fillPath()
            ctx.setStrokeColor(stroke(t.color))
            ctx.setLineWidth(max(1, radius * 0.06))
            addPath(ctx, shape: shape, orientation: t.orientation, center: c, radius: radius)
            ctx.strokePath()
            if selected {
                ctx.setStrokeColor(UIColor.systemOrange.cgColor)
                ctx.setLineWidth(max(2, radius * 0.1))
                addPath(ctx, shape: shape, orientation: t.orientation, center: c, radius: radius * 0.92)
                ctx.strokePath()
            }
        }

        if let snap = editor.drag?.snapCandidate {
            ctx.setStrokeColor(UIColor.systemBlue.cgColor)
            ctx.setLineWidth(2)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            addPath(
                ctx, shape: shape, orientation: snap.slot.orientation,
                center: camera.toScreen(SIMD2(snap.slot.x, snap.slot.y)), radius: radius)
            ctx.strokePath()
            ctx.setLineDash(phase: 0, lengths: [])
        }

        if let m = editor.marquee {
            let a = camera.toScreen(m.from), b = camera.toScreen(m.to)
            let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
            ctx.setFillColor(UIColor.systemBlue.withAlphaComponent(0.12).cgColor)
            ctx.fill(rect)
            ctx.setStrokeColor(UIColor.systemBlue.cgColor)
            ctx.setLineWidth(1.5)
            ctx.setLineDash(phase: 0, lengths: [6, 4])
            ctx.stroke(rect)
            ctx.setLineDash(phase: 0, lengths: [])
        }

        drawStats(editor, visible: visible.count, ms: lastMs, bounds: bounds)
        lastMs = (CACurrentMediaTime() - start) * 1000
    }

    private func addPath(_ ctx: CGContext, shape: Shape, orientation: Int, center: CGPoint, radius: CGFloat) {
        let units = shape.cornerUnitVectors[orientation]
        ctx.move(to: CGPoint(x: center.x + units[0].x * radius, y: center.y + units[0].y * radius))
        for u in units.dropFirst() {
            ctx.addLine(to: CGPoint(x: center.x + u.x * radius, y: center.y + u.y * radius))
        }
        ctx.closePath()
    }

    private func fill(_ color: TileColor) -> CGColor {
        if let c = fillColors[color] { return c }
        let c = UIColor(tile: color).cgColor
        fillColors[color] = c
        return c
    }

    /// A darker shade of the fill, for outlines.
    private func stroke(_ color: TileColor) -> CGColor {
        if let c = strokeColors[color] { return c }
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0
        UIColor(tile: color).getRed(&r, green: &g, blue: &b, alpha: nil)
        let c = UIColor(red: r * 0.65, green: g * 0.65, blue: b * 0.65, alpha: 1).cgColor
        strokeColors[color] = c
        return c
    }

    @MainActor
    private func drawStats(_ editor: Editor, visible: Int, ms: Double, bounds: CGRect) {
        let carried = editor.drag?.items.count ?? 0
        let text = "\(editor.board.store.size + carried) tiles · \(visible) drawn · \(String(format: "%.1f", ms)) ms"
        let attrs: [NSAttributedString.Key: Any] = [
            .font: UIFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: UIColor.black.withAlphaComponent(0.55),
        ]
        (text as NSString).draw(at: CGPoint(x: 12, y: bounds.height - 28), withAttributes: attrs)
    }
}
