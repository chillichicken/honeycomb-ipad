import SwiftUI
import UIKit
import Core

enum Palette {
    static let colors: [TileColor] = [
        0xE74C3C, 0xE67E22, 0xF1C40F, 0x2ECC71, 0x1ABC9C, 0x3498DB,
        0x9B59B6, 0xE84393, 0x8D6E63, 0xECF0F1, 0x95A5A6, 0x2C3E50,
    ]
}

extension UIColor {
    convenience init(tile rgb: TileColor) {
        self.init(
            red: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: 1)
    }
}

extension Color {
    init(tile rgb: TileColor) { self.init(uiColor: UIColor(tile: rgb)) }
}
