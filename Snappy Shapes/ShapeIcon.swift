import SwiftUI
import Core

/// A shape's real corner geometry as an icon, so it can never drift out of sync
/// with the tiles it represents.
struct ShapeIcon: View {
    let id: ShapeID

    var body: some View {
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height / 2)
            let units = TileShape.of(id).cornerUnitVectors[0]
            let path = Path { p in
                for (i, u) in units.enumerated() {
                    let pt = CGPoint(x: center.x + u.x * side * 0.375, y: center.y + u.y * side * 0.375)
                    i == 0 ? p.move(to: pt) : p.addLine(to: pt)
                }
                p.closeSubpath()
            }
            path.fill(Color(red: 1, green: 0.69, blue: 0.125))
            path.stroke(Color(red: 0.7, green: 0.42, blue: 0), style: StrokeStyle(lineWidth: side * 0.05, lineJoin: .round))
        }
    }
}
