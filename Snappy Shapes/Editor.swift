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
    let sound = SoundPlayer()
    var mode: Mode = .grab
    var paintColor: TileColor = Palette.classic
    private(set) var selectionCount = 0
    /// A short message shown over the canvas, then cleared.
    private(set) var toast: String?

    // Read by the render loop every frame, so kept out of SwiftUI observation.
    @ObservationIgnored var camera = Camera()
    /// Bumps whenever anything visible could have changed.
    @ObservationIgnored private(set) var version = 0
    @ObservationIgnored private(set) var drag: DragSession?
    @ObservationIgnored private(set) var marquee: (from: SIMD2<Double>, to: SIMD2<Double>)?
    @ObservationIgnored private var panning = false
    @ObservationIgnored private var lastPoint = CGPoint.zero
    @ObservationIgnored private(set) var lastEditAt = Date.distantPast
    @ObservationIgnored let clusters: ClusterTracker
    @ObservationIgnored private var clusterVersion = 0

    init() { clusters = ClusterTracker(store: board.store) }

    func touch() { version += 1 }

    /// A change to the board itself (as opposed to the camera or a mode switch).
    private func edited() {
        lastEditAt = Date()
        touch()
    }

    /// Called every display frame: eases tiles, and works through island counting
    /// in small slices (held back while a finger is carrying tiles).
    func frameTick(dt: Double) {
        // the same glide at 60 Hz or 120 Hz: 25% of the remaining distance per 60th of a second
        board.easeTowardTargets(skipping: drag?.tiles ?? [], factor: 1 - pow(0.75, dt * 60))
        if !board.easing.isEmpty { touch() }
        if drag == nil { clusters.step(shape: board.shape, budget: .milliseconds(3)) }
        if clusters.version != clusterVersion {
            clusterVersion = clusters.version
            touch()
        }
    }

    func showToast(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(for: .seconds(3))
            if toast == message { toast = nil }
        }
    }

    /// A new board of `shape` with one seed tile, so it isn't empty. The seed is
    /// placement, not an edit: nothing is saved until the player does something.
    func reset(shape: TileShape) {
        board.replace(shape: shape, tiles: [])
        board.spawnTile(color: paintColor, cameraCenter: .zero)
        board.settleEasing()
        _ = board.store.takeDirty()
        camera.center = .zero
        camera.zoom = 1
        mode = .grab
        selectionCount = 0
        touch()
    }

    /// After a puzzle was loaded into the board.
    func didLoad(centroid: SIMD2<Double>) {
        camera.center = centroid
        camera.zoom = 1
        mode = .grab
        selectionCount = 0
        touch()
    }

    private var snapDistance: Double { snapRadius / min(camera.zoom, 1) }

    private func syncSelection() { selectionCount = board.selected.count }

    // MARK: Buttons

    /// "+": grows the build from the last tile, then goes back to grabbing.
    /// Returns false when the board is full.
    @discardableResult
    func addTile() -> Bool {
        guard board.canAdd(1) else {
            showToast("Board is at its \(board.maxTiles.formatted())-tile limit")
            return false
        }
        board.spawnTile(color: paintColor, cameraCenter: camera.center)
        mode = .grab
        sound.playTileAdd()
        edited()
        return true
    }

    func deleteSelection() {
        board.remove(board.selected)
        syncSelection()
        edited()
    }

    /// Picking a color paints the whole selection, if there is one.
    func pick(color: TileColor) {
        paintColor = color
        for t in board.selected { board.store.setColor(t, color) }
        if !board.selected.isEmpty { edited() } else { touch() }
    }

    // MARK: Two fingers

    func pan(byScreen d: CGPoint) {
        camera.pan(byScreen: d)
        touch()
    }

    /// Zoom by a fixed step around the middle of the screen.
    func zoomStep(_ factor: Double) {
        zoom(by: factor, around: CGPoint(x: camera.size.width / 2, y: camera.size.height / 2))
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
            edited()
            return
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
            let moved = drag.moved
            let landing = drag.drop(snapDistance: snapDistance)
            self.drag = nil
            if moved { lastEditAt = Date() }  // a plain tap isn't an edit
            if landing != .free { sound.playSnap() }
        }
        if let m = marquee {
            // every shape the frame touches toggles; a marquee always adds to what's selected
            board.lattice.forEachTile(
                touchingMinX: min(m.from.x, m.to.x), minY: min(m.from.y, m.to.y),
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

    /// What UI tests read back to check what the fingers did.
    var stateSummary: String {
        String(
            format: "zoom=%.3f;cx=%.1f;cy=%.1f;tiles=%d;selected=%d;islands=%d;mode=%@", camera.zoom, camera.center.x, camera.center.y,
            board.store.size + (drag?.items.count ?? 0), board.selected.count, clusters.ready ? clusters.counts.islands : -1, "\(mode)")
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
        let radius = TileShape.hexagon.neighborDist * Double(board.store.size).squareRoot() * 0.6
        if camera.size.width > 0 {
            camera.zoom = min(max(min(camera.size.width, camera.size.height) / 2 / radius, 0.05), 1)
        }
        mode = .grab
        touch()
    }
    #endif
}
