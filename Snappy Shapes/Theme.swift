import SwiftUI
import UIKit

/// One hue, with every role a saturation/lightness step off it (the same theme
/// as the desktop game): change `hue` and the whole app follows.
enum Theme {
    static let hue = 230.0

    /// HSL with s and l as fractions (0...1).
    static func hsl(_ s: Double, _ l: Double, alpha: Double = 1, hue h: Double = hue) -> UIColor {
        let c = (1 - abs(2 * l - 1)) * s
        let hp = h / 60
        let x = c * (1 - abs(hp.truncatingRemainder(dividingBy: 2) - 1))
        let m = l - c / 2
        let (r, g, b): (Double, Double, Double) =
            switch Int(hp) % 6 {
            case 0: (c, x, 0)
            case 1: (x, c, 0)
            case 2: (0, c, x)
            case 3: (0, x, c)
            case 4: (x, 0, c)
            default: (c, 0, x)
            }
        return UIColor(red: r + m, green: g + m, blue: b + m, alpha: alpha)
    }

    static let bgEdge = hsl(0.35, 0.10)
    static let bgCenter = hsl(0.38, 0.16)
    static let panel = hsl(0.34, 0.13)
    static let panel2 = hsl(0.34, 0.16)
    static let border = hsl(0.32, 0.60)
    static let text = hsl(0.22, 0.86)
    static let textBright = hsl(0.22, 0.94)
    static let muted = hsl(0.18, 0.55)
    static let accent = hsl(0.55, 0.58)

    static let gridDot = border.withAlphaComponent(0.12)
    static let statsBigNumber = border.withAlphaComponent(0.14)
    static let statsLines = border.withAlphaComponent(0.28)
}

extension Color {
    init(_ ui: UIColor) { self.init(uiColor: ui) }
}

/// The dark radial backdrop shared by the canvas and the start screen.
struct Backdrop: View {
    var body: some View {
        RadialGradient(
            colors: [Color(Theme.bgCenter), Color(Theme.bgEdge)],
            center: .center, startRadius: 0, endRadius: 900
        )
        .ignoresSafeArea()
    }
}

/// A translucent dark panel with a hairline border, used for bars and cards.
struct PanelBackground<S: Shape>: ViewModifier {
    let shape: S
    func body(content: Content) -> some View {
        content.background(Color(Theme.panel).opacity(0.94), in: shape)
            .overlay(shape.stroke(Color(Theme.border).opacity(0.25), lineWidth: 1))
    }
}

extension View {
    func panel<S: Shape>(_ shape: S) -> some View { modifier(PanelBackground(shape: shape)) }
}

extension UIColor {
    /// rgba as a GPU vector.
    var simd: SIMD4<Float> {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return SIMD4(Float(r), Float(g), Float(b), Float(a))
    }
}
