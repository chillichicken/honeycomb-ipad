import UIKit
import Core

/// How much detail a tile gets, decided once per frame from its on-screen size
/// (zoom is uniform, so it's the same for every tile). The fabric grain and the
/// dashed stitch seam are the most expensive parts of a draw, so they only
/// appear once a tile is big enough for them to resolve.
enum Detail {
    case merged  // under 3px: flat squares
    case simple  // fill + border
    case medium  // + inner honeycomb wall
    case full  // + fabric grain and stitched seam

    init(screenRadius r: Double) {
        self = r < 3 ? .merged : r < 12 ? .simple : r < 30 ? .medium : .full
    }
}

/// Draws the board with Core Graphics. Only what's on screen is visited: the
/// store's buckets that overlap the viewport, plus the few tiles mid-animation
/// and the ones being carried.
final class BoardRenderer {
    /// Beyond this many visible tiles they're a few pixels each and stacking order is skipped.
    private static let sortLimit = 65_536

    private var shadeCache: [UInt64: CGColor] = [:]
    private var fillCache: [TileColor: CGColor] = [:]
    private lazy var fabric = Self.makeFabric()
    private var lastFrameAt = CACurrentMediaTime()
    private var fps = 0.0

    @MainActor
    func draw(_ editor: Editor, in ctx: CGContext, bounds: CGRect) {
        let now = CACurrentMediaTime()
        // frames only draw when something changed, so a long gap is idleness, not a slow frame
        let dt = now - lastFrameAt
        if dt < 0.25 { fps = fps * 0.9 + (1 / max(dt, 0.001)) * 0.1 }
        lastFrameAt = now

        let camera = editor.camera
        let board = editor.board
        let shape = board.shape
        let zoom = camera.zoom

        drawBackdrop(ctx, bounds)
        drawGrid(ctx, camera, shape, bounds)

        // marquee preview: which shapes the frame touches right now
        var touched = Set<Tile>()
        if let m = editor.marquee {
            board.lattice.forEachTile(
                touchingMinX: min(m.from.x, m.to.x), minY: min(m.from.y, m.to.y),
                maxX: max(m.from.x, m.to.x), maxY: max(m.from.y, m.to.y)
            ) { touched.insert($0) }
        }

        // gather what's visible: bucket walk (minus easing tiles), easing tiles, carried tiles
        let r = camera.visibleRect(margin: tileSize * 1.5)
        var visible: [Tile] = []
        board.store.forEachBucket(inMinX: r.minX, minY: r.minY, maxX: r.maxX, maxY: r.maxY) { _, tiles in
            for t in tiles where !board.easing.contains(t) { visible.append(t) }
            return false
        }
        visible.append(contentsOf: board.easing)
        if let drag = editor.drag { visible.append(contentsOf: drag.items.map(\.tile)) }
        if visible.count <= Self.sortLimit { visible.sort { $0.z < $1.z } }

        let radius = tileSize * zoom
        let detail = Detail(screenRadius: radius)
        let phase = camera.toScreen(.zero)
        ctx.setLineJoin(.round)
        if detail == .merged {
            drawMerged(ctx, visible, camera, shape, bounds)
        } else {
            for t in visible {
                let c = camera.toScreen(SIMD2(t.x, t.y))
                if c.x < -radius || c.y < -radius || c.x > bounds.width + radius || c.y > bounds.height + radius { continue }
                let outlined = board.selected.contains(t) != touched.contains(t)  // the marquee toggles
                drawTile(ctx, t, shape, center: c, zoom: zoom, detail: detail, outlined: outlined, phase: phase)
            }
        }

        drawSnapGhost(ctx, editor, shape, camera)
        drawMarquee(ctx, editor, camera)
        drawStats(editor, visible: visible.count, bounds: bounds)
    }

    // MARK: Background

    private func drawBackdrop(_ ctx: CGContext, _ bounds: CGRect) {
        let space = CGColorSpaceCreateDeviceRGB()
        let gradient = CGGradient(
            colorsSpace: space, colors: [Theme.bgCenter.cgColor, Theme.bgEdge.cgColor] as CFArray, locations: [0, 1])!
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let farthestCorner = hypot(bounds.width, bounds.height) / 2
        ctx.drawRadialGradient(
            gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: farthestCorner,
            options: [.drawsAfterEndLocation])
    }

    /// Faint dot grid in world space so pan and zoom are perceptible on empty ground.
    private func drawGrid(_ ctx: CGContext, _ camera: Camera, _ shape: TileShape, _ bounds: CGRect) {
        var spacing = shape.neighborDist
        while spacing * camera.zoom < 28 { spacing *= 2 }  // thin out when zoomed far away
        let tl = camera.toWorld(.zero)
        let br = camera.toWorld(CGPoint(x: bounds.width, y: bounds.height))
        let r = 1.5
        ctx.setFillColor(Theme.gridDot.cgColor)
        var gx = (tl.x / spacing).rounded(.down) * spacing
        while gx <= br.x {
            var gy = (tl.y / spacing).rounded(.down) * spacing
            while gy <= br.y {
                let p = camera.toScreen(SIMD2(gx, gy))
                ctx.addEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: r * 2, height: r * 2))
                gy += spacing
            }
            gx += spacing
        }
        ctx.fillPath()  // all dots in one path, one fill
    }

    // MARK: Tiles

    /// Zoomed far out a tile is a few pixels: flat squares, padded so neighbors overlap
    /// (a square doesn't tile a hex lattice exactly, and gaps would speckle the background).
    private func drawMerged(_ ctx: CGContext, _ tiles: [Tile], _ camera: Camera, _ shape: TileShape, _ bounds: CGRect) {
        let side = max(shape.neighborDist * camera.zoom, 1) * 2.1
        var current: TileColor?
        for t in tiles {
            let c = camera.toScreen(SIMD2(t.tx, t.ty))
            if c.x < -side || c.y < -side || c.x > bounds.width + side || c.y > bounds.height + side { continue }
            if t.color != current {
                ctx.setFillColor(fill(t.color))
                current = t.color
            }
            ctx.fill(CGRect(x: c.x - side / 2, y: c.y - side / 2, width: side, height: side))
        }
    }

    private func drawTile(
        _ ctx: CGContext, _ t: Tile, _ shape: TileShape, center c: CGPoint, zoom: Double, detail: Detail,
        outlined: Bool, phase: CGPoint
    ) {
        let units = shape.cornerUnitVectors[t.orientation]
        let R = tileSize * zoom

        ctx.setFillColor(fill(t.color))
        path(ctx, units, c, R)
        ctx.fillPath()

        if detail == .full {
            // fabric grain, clipped to the tile so it never bleeds past the border
            ctx.saveGState()
            path(ctx, units, c, R)
            ctx.clip()
            ctx.setBlendMode(.overlay)
            ctx.setAlpha(0.85)
            ctx.setPatternPhase(CGSize(width: phase.x, height: phase.y))
            fabric.setFill()
            ctx.fill(CGRect(x: c.x - R, y: c.y - R, width: R * 2, height: R * 2))
            ctx.restoreGState()
        }

        ctx.setStrokeColor(shade(t.color, -60))
        ctx.setLineWidth(3 * zoom)
        path(ctx, units, c, R - 1.5 * zoom)
        ctx.strokePath()

        if detail == .full {
            // stitched seam, like adjoining patchwork squares sewn together
            ctx.saveGState()
            ctx.setLineDash(phase: 0, lengths: [2.5 * zoom, 3 * zoom])
            ctx.setStrokeColor(UIColor(red: 1, green: 0.98, blue: 0.92, alpha: 0.5).cgColor)
            ctx.setLineWidth(1.2 * zoom)
            path(ctx, units, c, R - 6 * zoom)
            ctx.strokePath()
            ctx.restoreGState()
        }

        if detail != .simple {
            // inner cell wall for the honeycomb look
            ctx.setStrokeColor(shade(t.color, 35))
            ctx.setLineWidth(2 * zoom)
            path(ctx, units, c, R * 0.72)
            ctx.strokePath()
        }

        if outlined {
            ctx.setStrokeColor(Theme.accent.withAlphaComponent(0.95).cgColor)
            ctx.setLineWidth(max(2.5 * zoom, 1.5))
            path(ctx, units, c, R + 4 * zoom)
            ctx.strokePath()
        }
    }

    private func path(_ ctx: CGContext, _ units: [SIMD2<Double>], _ c: CGPoint, _ r: CGFloat) {
        ctx.move(to: CGPoint(x: c.x + units[0].x * r, y: c.y + units[0].y * r))
        for u in units.dropFirst() { ctx.addLine(to: CGPoint(x: c.x + u.x * r, y: c.y + u.y * r)) }
        ctx.closePath()
    }

    // MARK: Overlays

    @MainActor
    private func drawSnapGhost(_ ctx: CGContext, _ editor: Editor, _ shape: TileShape, _ camera: Camera) {
        guard let snap = editor.drag?.snapCandidate else { return }
        let c = camera.toScreen(SIMD2(snap.slot.x, snap.slot.y))
        ctx.setStrokeColor(Theme.accent.cgColor)
        ctx.setLineWidth(2)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        path(ctx, shape.cornerUnitVectors[snap.slot.orientation], c, tileSize * camera.zoom)
        ctx.strokePath()
        ctx.setLineDash(phase: 0, lengths: [])
    }

    @MainActor
    private func drawMarquee(_ ctx: CGContext, _ editor: Editor, _ camera: Camera) {
        guard let m = editor.marquee else { return }
        let a = camera.toScreen(m.from), b = camera.toScreen(m.to)
        let rect = CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y))
        ctx.setFillColor(Theme.accent.withAlphaComponent(0.08).cgColor)
        ctx.fill(rect)
        ctx.setStrokeColor(Theme.accent.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [6, 4])
        ctx.stroke(rect)
        ctx.setLineDash(phase: 0, lengths: [])
    }

    /// A faint watermark readout, bottom right: the tile count big, details below.
    @MainActor
    private func drawStats(_ editor: Editor, visible: Int, bounds: CGRect) {
        let board = editor.board
        let total = board.store.size + (editor.drag?.items.count ?? 0)
        func right(_ text: String, font: UIFont, color: UIColor, baselineY: CGFloat) {
            let attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: bounds.width - 28 - size.width, y: baselineY - font.ascender), withAttributes: attrs)
        }
        right(String(total), font: .systemFont(ofSize: 110, weight: .bold), color: Theme.statsBigNumber, baselineY: bounds.height - 30)

        var lines = ["tile\(total == 1 ? "" : "s") · \(visible) on screen"]
        if !board.selected.isEmpty { lines.append("\(board.selected.count) selected") }
        if total > 1 {
            let c = editor.clusters
            lines.append(
                !c.ready ? "counting islands…" : c.counts.islands == 1 ? "1 island" : "\(c.counts.islands) islands · largest \(c.counts.largest)")
        }
        lines.append("zoom \(Int((editor.camera.zoom * 100).rounded()))%")
        lines.append("\(Int(fps.rounded())) fps")
        var y = bounds.height - 150
        for line in lines.reversed().reversed() {
            right(line, font: .systemFont(ofSize: 15, weight: .medium), color: Theme.statsLines, baselineY: y + 15)
            y -= 21
        }
    }

    // MARK: Colors

    private func fill(_ color: TileColor) -> CGColor {
        if let c = fillCache[color] { return c }
        let c = UIColor(tile: color).cgColor
        fillCache[color] = c
        return c
    }

    /// The color brightened or darkened by `amount` on each channel, cached (a
    /// board has few distinct colors, and this runs per tile per frame).
    private func shade(_ color: TileColor, _ amount: Int) -> CGColor {
        let key = UInt64(color) << 16 | UInt64(amount + 256)
        if let c = shadeCache[key] { return c }
        func ch(_ shift: UInt32) -> CGFloat {
            CGFloat(max(0, min(255, Int((color >> shift) & 0xFF) + amount))) / 255
        }
        let c = UIColor(red: ch(16), green: ch(8), blue: ch(0), alpha: 1).cgColor
        if shadeCache.count > 8192 { shadeCache.removeAll() }
        shadeCache[key] = c
        return c
    }

    /// A small tileable woven-cloth grain: a twill crosshatch plus noise. It's
    /// blended over each tile with "overlay", so it darkens and lightens the tile
    /// color the way light catches actual threads instead of just painting on top.
    private static func makeFabric() -> UIColor {
        let size = 14
        var pixels = [UInt8](repeating: 255, count: size * size * 4)
        var rng = SystemRandomNumberGenerator()
        for y in 0..<size {
            for x in 0..<size {
                let weave: Double = (x + y) % 4 < 2 ? 34 : -34
                let grain = (Double.random(in: 0..<1, using: &rng) - 0.5) * 34
                let v = UInt8(max(0, min(255, 128 + weave + grain)))
                let i = (y * size + x) * 4
                pixels[i] = v; pixels[i + 1] = v; pixels[i + 2] = v
            }
        }
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: size, height: size, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: size * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)!
        return UIColor(patternImage: UIImage(cgImage: image, scale: 1, orientation: .up))
    }
}
