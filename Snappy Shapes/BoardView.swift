import SwiftUI
import Core
import MetalKit
import UIKit

/// The canvas: a UIView that draws the board and turns fingers into `Editor` calls.
struct BoardView: UIViewRepresentable {
    let editor: Editor

    func makeUIView(context: Context) -> BoardUIView { BoardUIView(editor: editor) }
    func updateUIView(_ view: BoardUIView, context: Context) {}
}

final class BoardUIView: UIView, UIGestureRecognizerDelegate {
    private let editor: Editor
    private let metalView = MTKView()
    private var renderer: TileRenderer?
    private let overlay = CanvasOverlay()
    private var link: CADisplayLink?
    private var renderedVersion = -1
    private var lastFrameAt = CACurrentMediaTime()
    private var lastTickAt = CACurrentMediaTime()
    private var fps = 0.0
    private var lastStats = FrameStats()

    init(editor: Editor) {
        self.editor = editor
        super.init(frame: .zero)
        isMultipleTouchEnabled = true

        if let device = MTLCreateSystemDefaultDevice() {
            metalView.device = device
            metalView.colorPixelFormat = .bgra8Unorm
            metalView.framebufferOnly = true
            metalView.isPaused = true  // we draw when something changed, not on a timer
            metalView.enableSetNeedsDisplay = false
            metalView.isUserInteractionEnabled = false
            addSubview(metalView)
            renderer = TileRenderer(device: device, view: metalView)
        }
        overlay.attach(to: self)

        // one finger: the current mode's action (press and drag)
        let one = UIPanGestureRecognizer(target: self, action: #selector(oneFinger))
        one.minimumNumberOfTouches = 1
        one.maximumNumberOfTouches = 1
        one.delegate = self
        addGestureRecognizer(one)

        // two fingers on the glass: always navigate
        let two = UIPanGestureRecognizer(target: self, action: #selector(twoFingers))
        two.minimumNumberOfTouches = 2
        two.maximumNumberOfTouches = 2
        two.delegate = self
        addGestureRecognizer(two)

        // a trackpad or wheel scroll is its own kind of input: it needs a recognizer that
        // takes scroll events and no touches (a touch recognizer never sees them)
        let scroll = UIPanGestureRecognizer(target: self, action: #selector(twoFingers))
        scroll.allowedScrollTypesMask = .all
        scroll.allowedTouchTypes = []
        scroll.delegate = self
        addGestureRecognizer(scroll)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    // UI tests find the canvas by this identifier and read the camera/selection from its value
    override var isAccessibilityElement: Bool { get { true } set {} }
    override var accessibilityIdentifier: String? { get { "board" } set {} }
    override var accessibilityTraits: UIAccessibilityTraits { get { .allowsDirectInteraction } set {} }
    override var accessibilityValue: String? {
        get { MainActor.assumeIsolated { editor.stateSummary } }
        set {}
    }

    // MARK: Render loop

    override func didMoveToWindow() {
        link?.invalidate()
        link = nil
        guard window != nil else { return }
        let l = CADisplayLink(target: self, selector: #selector(tick))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        metalView.frame = bounds
        overlay.layout(in: bounds)
        editor.camera.size = bounds.size
        editor.touch()
    }

    /// Redraws only when something could look different.
    @objc private func tick() {
        MainActor.assumeIsolated {
            let tickAt = CACurrentMediaTime()
            editor.frameTick(dt: min(max(tickAt - lastTickAt, 0.001), 0.05))
            lastTickAt = tickAt
            guard editor.version != renderedVersion, let renderer,
                let stats = renderer.draw(editor, in: metalView)
            else { return }
            renderedVersion = editor.version
            // frames only draw when something changed, so a long gap is idleness, not a slow frame
            let now = CACurrentMediaTime()
            let dt = now - lastFrameAt
            if dt < 0.25 { fps = fps * 0.9 + (1 / max(dt, 0.001)) * 0.1 }
            lastFrameAt = now
            lastStats = stats
            overlay.update(editor, stats: stats, fps: fps, bounds: bounds)
        }
    }

    // MARK: Gestures

    @objc private func oneFinger(_ g: UIPanGestureRecognizer) {
        let p = g.location(in: self)
        switch g.state {
        case .began:
            // the recognizer fires after a little movement; start where the finger went down
            let t = g.translation(in: self)
            editor.beginDrag(at: CGPoint(x: p.x - t.x, y: p.y - t.y))
            editor.continueDrag(to: p)
        case .changed:
            editor.continueDrag(to: p)
        case .ended, .cancelled, .failed:
            editor.endDrag()
        default:
            break
        }
    }

    @objc private func twoFingers(_ g: UIPanGestureRecognizer) {
        guard g.state == .changed else { return }
        let t = g.translation(in: self)
        if g.modifierFlags.contains(.command) {
            // ⌘ + scroll zooms: the way to zoom with a trackpad or wheel where the
            // pinch never arrives (the Simulator only forwards two-finger scrolls)
            editor.zoom(by: exp(-Double(t.y) / 200), around: g.location(in: self))
        } else {
            editor.pan(byScreen: t)
        }
        g.setTranslation(.zero, in: self)
    }

    @objc private func pinch(_ g: UIPinchGestureRecognizer) {
        guard g.state == .changed else { return }
        editor.zoom(by: Double(g.scale), around: g.location(in: self))
        g.scale = 1
    }

    @objc private func tap(_ g: UITapGestureRecognizer) {
        editor.tap(at: g.location(in: self))
    }

    /// Pinch and two-finger pan work together; the one-finger pan stands alone.
    func gestureRecognizer(_ a: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith b: UIGestureRecognizer) -> Bool {
        a is UIPinchGestureRecognizer != b is UIPinchGestureRecognizer
    }
}
