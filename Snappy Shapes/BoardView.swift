import SwiftUI
import UIKit

/// The canvas: a UIView that draws the board and turns fingers into `Editor` calls.
struct BoardView: UIViewRepresentable {
    let editor: Editor

    func makeUIView(context: Context) -> BoardUIView { BoardUIView(editor: editor) }
    func updateUIView(_ view: BoardUIView, context: Context) {}
}

final class BoardUIView: UIView, UIGestureRecognizerDelegate {
    private let editor: Editor
    private let renderer = BoardRenderer()
    private var link: CADisplayLink?
    private var renderedVersion = -1

    init(editor: Editor) {
        self.editor = editor
        super.init(frame: .zero)
        isMultipleTouchEnabled = true
        contentMode = .redraw

        // one finger: the current mode's action (press and drag)
        let one = UIPanGestureRecognizer(target: self, action: #selector(oneFinger))
        one.minimumNumberOfTouches = 1
        one.maximumNumberOfTouches = 1
        one.delegate = self
        addGestureRecognizer(one)

        // two fingers (or trackpad scroll): always navigate
        let two = UIPanGestureRecognizer(target: self, action: #selector(twoFingers))
        two.minimumNumberOfTouches = 2
        two.maximumNumberOfTouches = 2
        two.allowedScrollTypesMask = .all
        two.delegate = self
        addGestureRecognizer(two)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(pinch))
        pinch.delegate = self
        addGestureRecognizer(pinch)

        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap)))
    }

    required init?(coder: NSCoder) { fatalError("not used") }

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
        editor.camera.size = bounds.size
        editor.touch()
    }

    /// Redraws only when something could look different.
    @objc private func tick() {
        MainActor.assumeIsolated {
            editor.board.easeTowardTargets(skipping: editor.drag?.tiles ?? [])
            if !editor.board.easing.isEmpty { editor.touch() }
            if editor.version != renderedVersion {
                renderedVersion = editor.version
                setNeedsDisplay()
            }
        }
    }

    override func draw(_ rect: CGRect) {
        guard let ctx = UIGraphicsGetCurrentContext() else { return }
        MainActor.assumeIsolated { renderer.draw(editor, in: ctx, bounds: bounds) }
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
        editor.pan(byScreen: g.translation(in: self))
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
