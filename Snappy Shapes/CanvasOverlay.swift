import UIKit
import Core

/// The few things drawn over the GPU canvas: the selection frame, the snap ghost and the
/// stats watermark. Small layers and labels rather than a full-screen bitmap, so
/// updating them every frame stays cheap.
@MainActor
final class CanvasOverlay {
    private let marquee = CAShapeLayer()
    private let ghost = CAShapeLayer()
    private let bigNumber = UILabel()
    private let lines = UILabel()

    func attach(to view: UIView) {
        for layer in [marquee, ghost] {
            layer.lineDashPattern = [6, 4]
            layer.isHidden = true
            layer.actions = ["path": NSNull(), "hidden": NSNull(), "position": NSNull()]  // no implicit animation
            view.layer.addSublayer(layer)
        }
        marquee.fillColor = Theme.accent.withAlphaComponent(0.08).cgColor
        marquee.strokeColor = Theme.accent.withAlphaComponent(0.8).cgColor
        marquee.lineWidth = 1.5
        ghost.fillColor = nil
        ghost.strokeColor = Theme.accent.cgColor
        ghost.lineWidth = 2

        bigNumber.font = .systemFont(ofSize: 110, weight: .bold)
        bigNumber.textColor = Theme.statsBigNumber
        lines.font = .systemFont(ofSize: 15, weight: .medium)
        lines.textColor = Theme.statsLines
        lines.numberOfLines = 0
        lines.textAlignment = .right
        for label in [bigNumber, lines] {
            label.isUserInteractionEnabled = false
            view.addSubview(label)
        }
    }

    func update(_ editor: Editor, stats: FrameStats, fps: Double, bounds: CGRect) {
        let camera = editor.camera
        let board = editor.board

        if let m = editor.marquee {
            let a = camera.toScreen(m.from), b = camera.toScreen(m.to)
            marquee.path = CGPath(rect: CGRect(x: min(a.x, b.x), y: min(a.y, b.y), width: abs(a.x - b.x), height: abs(a.y - b.y)), transform: nil)
            marquee.isHidden = false
        } else {
            marquee.isHidden = true
        }

        if let snap = editor.drag?.snapCandidate {
            let c = camera.toScreen(SIMD2(snap.slot.x, snap.slot.y))
            let r = tileSize * camera.zoom
            let path = CGMutablePath()
            for (i, u) in board.shape.cornerUnitVectors[snap.slot.orientation].enumerated() {
                let p = CGPoint(x: c.x + u.x * r, y: c.y + u.y * r)
                i == 0 ? path.move(to: p) : path.addLine(to: p)
            }
            path.closeSubpath()
            ghost.path = path
            ghost.isHidden = false
        } else {
            ghost.isHidden = true
        }

        let total = board.store.size + (editor.drag?.items.count ?? 0)
        var text = ["tile\(total == 1 ? "" : "s") · \(stats.drawnTiles) on screen"]
        if !board.selected.isEmpty { text.append("\(board.selected.count) selected") }
        if total > 1 {
            let c = editor.clusters
            text.append(!c.ready ? "counting islands…" : c.counts.islands == 1 ? "1 island" : "\(c.counts.islands) islands · largest \(c.counts.largest)")
        }
        text.append("zoom \(Int((camera.zoom * 100).rounded()))%")
        text.append("\(Int(fps.rounded())) fps · cpu \(String(format: "%.1f", stats.cpuMs)) ms · gpu \(String(format: "%.1f", stats.gpuMs)) ms")
        setText(bigNumber, String(total))
        setText(lines, text.reversed().joined(separator: "\n"))  // the first line sits at the bottom
        layout(in: bounds)
    }

    func layout(in bounds: CGRect) {
        let big = bigNumber.sizeThatFits(bounds.size)
        bigNumber.frame = CGRect(x: bounds.width - 28 - big.width, y: bounds.height - 6 - big.height, width: big.width, height: big.height)
        let small = lines.sizeThatFits(CGSize(width: bounds.width, height: bounds.height))
        lines.frame = CGRect(x: bounds.width - 28 - small.width, y: bounds.height - 120 - small.height, width: small.width, height: small.height)
    }

    private func setText(_ label: UILabel, _ text: String) {
        if label.text != text { label.text = text }
    }
}
