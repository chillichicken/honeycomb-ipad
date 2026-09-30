import SwiftUI
import Core

enum Mode {
    case grab, select, recolor
}

/// Turns touches into board actions, depending on the current mode. The views
/// only report what the fingers did; everything that changes the board lives here.
@Observable @MainActor
final class Editor {
    let board = Board()
    var mode: Mode = .grab
    var paintColor: TileColor = Palette.colors[5]
    private(set) var selectionCount = 0

    // Read by the render loop every frame, so kept out of SwiftUI observation.
    @ObservationIgnored var camera = Camera()
    /// Bumps whenever anything visible could have changed.
    @ObservationIgnored private(set) var version = 0
    @ObservationIgnored private(set) var drag: DragSession?
    @ObservationIgnored private(set) var marquee: (from: SIMD2<Double>, to: SIMD2<Double>)?
    @ObservationIgnored private var panning = false
    @ObservationIgnored private var lastPoint = CGPoint.zero

    func touch() { version += 1 }

    private var snapDistance: Double { snapRadius / min(camera.zoom, 1) }

    private func syncSelection() { selectionCount = board.selected.count }

    // MARK: Buttons

    /// "+": grows the build from the last tile, then goes back to grabbing.
    func addTile() {
        guard board.canAdd(1) else { return }  // TODO: toast
        board.spawnTile(color: paintColor, cameraCenter: camera.center)
        mode = .grab
        touch()
    }

    func deleteSelection() {
        board.remove(board.selected)
        syncSelection()
        touch()
    }

    /// Picking a color paints the whole selection, if there is one.
    func pick(color: TileColor) {
        paintColor = color
        for t in board.selected { board.store.setColor(t, color) }
        touch()
    }

    // MARK: Two fingers

    func pan(byScreen d: CGPoint) {
        camera.pan(byScreen: d)
        touch()
    }

    func zoom(by factor: Double, around p: CGPoint) {
        camera.zoom(by: factor, around: p)
        touch()
    }

    // MARK: One finger

    func tap(at p: CGPoint) {
        let w = camera.toWorld(p)
        guard let tile = board.lattice.tileAt(w.x, w.y) else { return }
        switch mode {
        case .grab:
            break
        case .select:
            if board.selected.remove(tile) == nil { board.selected.insert(tile) }
            syncSelection()
        case .recolor:
            // the tile itself, or the whole selection it belongs to
            let targets = board.selected.contains(tile) ? Array(board.selected) : [tile]
            for t in targets { board.store.setColor(t, paintColor) }
        }
        touch()
    }

    func beginDrag(at p: CGPoint) {
        let w = camera.toWorld(p)
        lastPoint = p
        switch mode {
        case .grab:
            if let tile = board.lattice.tileAt(w.x, w.y) {
                // grabbing outside the selection drops it
                if !board.selected.contains(tile) { board.selected = [] }
                let group = board.selected.contains(tile) ? Array(board.selected) : [tile]
                drag = DragSession(board: board, tiles: group, grabbedAt: w)
                syncSelection()
            } else {
                panning = true
            }
        case .select:
            marquee = (w, w)
        case .recolor:
            panning = true
        }
        touch()
    }

    func continueDrag(to p: CGPoint) {
        let w = camera.toWorld(p)
        if let drag {
            drag.move(to: w, snapDistance: snapDistance)
        } else if marquee != nil {
            marquee?.to = w
        } else if panning {
            camera.pan(byScreen: CGPoint(x: p.x - lastPoint.x, y: p.y - lastPoint.y))
        }
        lastPoint = p
        touch()
    }

    func endDrag() {
        if let drag {
            drag.drop(snapDistance: snapDistance)
            self.drag = nil
        }
        if let m = marquee {
            // every tile inside toggles; a marquee always adds to what's selected
            board.store.forEachTile(
                inMinX: min(m.from.x, m.to.x), minY: min(m.from.y, m.to.y),
                maxX: max(m.from.x, m.to.x), maxY: max(m.from.y, m.to.y)
            ) { tile in
                if board.selected.remove(tile) == nil { board.selected.insert(tile) }
            }
            marquee = nil
        }
        panning = false
        syncSelection()
        touch()
    }

    // MARK: Debug

    #if DEBUG
    /// Grows the build by `count` tiles at once, to see how big boards feel.
    func debugFill(_ count: Int) {
        let n = min(count, max(0, board.maxTiles - board.store.size))
        for _ in 0..<n {
            board.spawnTile(color: Palette.colors.randomElement()!, cameraCenter: camera.center)
        }
        board.settleEasing()
        let radius = Shape.hexagon.neighborDist * Double(board.store.size).squareRoot() * 0.6
        if camera.size.width > 0 {
            camera.zoom = min(max(min(camera.size.width, camera.size.height) / 2 / radius, 0.05), 1)
        }
        mode = .grab
        touch()
    }
    #endif
}
