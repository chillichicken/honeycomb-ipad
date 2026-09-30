import SwiftUI
import Core

/// Mode buttons on the left, actions ("+", delete) on the right. In recolor
/// mode a color strip drops down underneath.
struct TopBar: View {
    @Bindable var editor: Editor

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 12) {
                HStack(spacing: 4) {
                    modeButton(.grab, "hand.draw", "Grab")
                    modeButton(.select, "rectangle.dashed", "Select")
                    modeButton(.recolor, "drop.fill", "Recolor", tint: Color(tile: editor.paintColor))
                }
                .padding(4)
                .background(.thinMaterial, in: Capsule())

                Spacer()

                if editor.selectionCount > 0 {
                    Button(role: .destructive) { editor.deleteSelection() } label: {
                        Label("\(editor.selectionCount)", systemImage: "trash")
                            .labelStyle(.titleAndIcon)
                            .padding(.horizontal, 14).padding(.vertical, 10)
                    }
                    .background(.thinMaterial, in: Capsule())
                }

                #if DEBUG
                Menu {
                    Button("Add 1,000 tiles") { editor.debugFill(1_000) }
                    Button("Add 10,000 tiles") { editor.debugFill(10_000) }
                    Button("Add 100,000 tiles") { editor.debugFill(100_000) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 44, height: 44)
                }
                .background(.thinMaterial, in: Circle())
                #endif

                Button { editor.addTile() } label: {
                    Image(systemName: "plus").font(.title2.weight(.semibold)).frame(width: 44, height: 44)
                }
                .background(.thinMaterial, in: Circle())
            }

            if editor.mode == .recolor {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(Palette.colors, id: \.self) { color in
                            Button { editor.pick(color: color) } label: {
                                Circle().fill(Color(tile: color)).frame(width: 34, height: 34)
                                    .overlay(Circle().stroke(.primary.opacity(color == editor.paintColor ? 0.9 : 0.15), lineWidth: 3))
                            }
                        }
                    }
                    .padding(8)
                }
                .background(.thinMaterial, in: Capsule())
                .frame(maxWidth: 520)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    private func modeButton(_ mode: Mode, _ symbol: String, _ label: String, tint: Color? = nil) -> some View {
        Button { editor.mode = mode } label: {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(editor.mode == mode ? Color.white : (tint ?? Color.primary))
                .frame(width: 52, height: 44)
                .background(editor.mode == mode ? Color.accentColor : Color.clear, in: Capsule())
        }
        .accessibilityLabel(label)
    }
}
